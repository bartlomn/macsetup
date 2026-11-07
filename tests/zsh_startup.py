#!/usr/bin/python3
"""Starts a real interactive zsh on a pty in a temp HOME and checks what it does.

Usage: zsh_startup.py <repo> <mode>, where mode is full, delay, no-tools or no-omz.
The owner's Oh My Zsh is linked in and only read: its cache is redirected, and the run fails if
anything under it changes. Exits non-zero with the reason on a failed check.
"""
import fcntl
import os
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

REPORT = (
    'print -r -- "THEME=[$ZSH_THEME] LS=[$(alias ls)] PLUGINS=[$plugins] '
    'FNMHOOK=[$(typeset -f _fnm_autoload_hook | wc -l | tr -d " ")] '
    'DOCKER=[$DOCKER_HOST] LSWORKS=[$(ls / >/dev/null 2>&1; print $?)] END$((1+1))"; exit\n'
)
BAD_OUTPUT = ["command not found", "not found:", "no such file", "console output during zsh",
              "[oh-my-zsh] plugin", "[oh-my-zsh] theme", "parse error"]


def fail(message, output=""):
    sys.exit(f"FAIL: {message}\n--- output ---\n{output[-1500:]}")


def build_home(repo, real_home, with_omz, below_stub=""):
    home = tempfile.mkdtemp(prefix="zsh-startup-")
    os.symlink(repo, f"{home}/.macsetup")
    os.symlink(f"{repo}/p10k.zsh", f"{home}/.p10k.zsh")
    if with_omz:
        os.symlink(f"{real_home}/.oh-my-zsh", f"{home}/.oh-my-zsh")
    with open(f"{home}/.zshrc", "w") as stub:
        stub.write("source ~/.macsetup/zsh/zshrc.zsh\n"
                   "# Machine-specific settings and secrets go below this line\n" + below_stub)
    os.makedirs(f"{home}/Applications")
    os.makedirs(f"{home}/cache/omz")
    return home


def run_shell(home, path, extra_env=None):
    """Returns (seconds to first output, all output)."""
    env = {"HOME": home, "PATH": path, "TERM": "xterm-256color", "USER": os.environ.get("USER", "x"),
           "LANG": "en_US.UTF-8", "XDG_CACHE_HOME": f"{home}/cache", "ZSH_CACHE_DIR": f"{home}/cache/omz",
           "DISABLE_AUTO_UPDATE": "true", "HISTFILE": f"{home}/history",
           "MACSETUP_APPS_DIR": f"{home}/Applications"}
    env.update(extra_env or {})
    start = time.time()
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(home)
        os.execve("/bin/zsh", ["/bin/zsh", "-i"], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    output, first, sent, last = b"", None, False, time.time()
    while time.time() - start < 30 and b"END2" not in output:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
            last = time.time()
            if first is None:
                first = last - start
        if not sent and first is not None and time.time() - last > 1.5:
            os.write(fd, REPORT.encode())
            sent = True
    try:
        os.kill(pid, 9)
    except OSError:
        pass
    os.waitpid(pid, 0)
    text = output.decode("utf-8", "replace")
    if "END2" not in text:
        fail("the shell never finished the report", text)
    # Only the expanded report line: the shell also echoes the typed command, variables unexpanded.
    return first, text, text[text.rfind("THEME=["):]


def check_clean(text):
    lowered = text.lower()
    for bad in BAD_OUTPUT:
        if bad in lowered:
            fail(f"unexpected output: {bad}", text)


def need(condition, message, text):
    if not condition:
        fail(message, text)


def main():
    repo, mode = os.path.abspath(sys.argv[1]), sys.argv[2]
    real_home = os.environ["HOME"]
    omz_stamp = tempfile.NamedTemporaryFile()
    time.sleep(0.05)
    brew_path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    bare = {"MACSETUP_BREW_PATHS": ""}
    home = None
    try:
        if mode == "full":
            home = build_home(repo, real_home, True)
            os.makedirs(f"{home}/Applications/Docker.app")
            run_shell(home, brew_path)
            _, text, report = run_shell(home, brew_path)
            check_clean(text)
            need("THEME=[powerlevel10k/powerlevel10k]" in report, "wrong theme", text)
            need("eza --icons --group-directories-first" in report, "eza alias missing", text)
            need("zsh-autosuggestions" in report and "zsh-syntax-highlighting" in report, "plugins missing", text)
            need(f"DOCKER=[unix://{home}/.docker/run/docker.sock]" in report, "DOCKER_HOST not set", text)
            if shutil.which("fnm", path=brew_path):
                need("FNMHOOK=[0]" not in report, "fnm hook missing", text)
        elif mode == "delay":
            home = build_home(repo, real_home, True, below_stub="sleep 3\n")
            run_shell(home, brew_path)
            first, text, _ = run_shell(home, brew_path)
            check_clean(text)
            need(first is not None and first < 1.0, f"first output took {first:.2f}s", text)
        elif mode == "no-tools":
            home = build_home(repo, real_home, True)
            run_shell(home, "/usr/bin:/bin", bare)
            _, text, report = run_shell(home, "/usr/bin:/bin", bare)
            check_clean(text)
            need("eza" not in report, "ls is still aliased to eza", text)
            need("LSWORKS=[0]" in report, "ls does not work", text)
            need("FNMHOOK=[0]" in report, "fnm hook defined without fnm", text)
            need("DOCKER=[]" in report, "DOCKER_HOST set without Docker Desktop", text)
            plugins = report[report.index("PLUGINS=["):].split("]")[0]
            for absent in ("aws", "docker", "helm", "kubectl", "direnv"):
                need(absent not in plugins, f"plugin {absent} loaded without the tool", text)
        elif mode == "no-omz":
            home = build_home(repo, real_home, False)
            _, text, report = run_shell(home, brew_path)
            check_clean(text)
            need("Oh My Zsh is not installed" in text, "no clear message", text)
            need("LSWORKS=[0]" in report, "ls does not work", text)
        else:
            fail(f"unknown mode {mode}")
        changed = subprocess.run(
            ["find", "-L", f"{real_home}/.oh-my-zsh", "-newer", omz_stamp.name, "-type", "f"],
            capture_output=True, text=True).stdout.strip()
        need(not changed, f"the real Oh My Zsh changed: {changed[:300]}", "")
    finally:
        if home:
            shutil.rmtree(home, ignore_errors=True)
    print(f"{mode}: PASS")


main()
