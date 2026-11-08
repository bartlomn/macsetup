# Mac setup utility script

## Running on Mac

Takes a fresh Mac to usable with one command. It is safe to re-run at any time: every step checks
first, and a re-run changes only what is missing.

```bash
f="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/bartlomn/macsetup/main/bootstrap.sh -o "$f" && /bin/bash "$f"
```

This installs Homebrew, clones the repo to `~/.macsetup`, and runs `~/.macsetup/install.sh`. The
account must be an administrator, and you'll be asked for your password once.

To re-run later:

```bash
~/.macsetup/install.sh         # Choose apps in the picker
~/.macsetup/install.sh --all   # Install everything not yet installed or declined
~/.macsetup/macos.sh           # macOS settings only
```

With no terminal, as in a plain `ssh host ~/.macsetup/install.sh`, only default apps are installed.

The run ends with a summary. Exit codes: `0` all done, `1` something failed, `2` nothing failed but
manual steps remain.

### Apps

`Brewfile` lists everything, and `# optional` marks items that start unchecked. Apps already
installed are listed above the picker. Unchecking a default records it in
`~/.config/macsetup/declined`, so it starts unchecked next time. Nothing is ever uninstalled.

### Shell

`~/.zshrc` is a small stub that loads `~/.macsetup/zsh/zshrc.zsh`. Put machine-specific settings and
secrets below the stub line, as this repo is public. Any previous `~/.zshrc` is kept with a
`.macsetup-bak-<timestamp>` suffix.

If `p10k configure` offers to edit `~/.zshrc`, decline, because the prompt is already loaded.

Icons work in kitty as it is. Terminal.app needs its font set to `MesloLGS NF` by hand.

### SSH

The run adds the public key in `ssh/authorized_key.pub` to `~/.ssh/authorized_keys`, turns off
password and keyboard-interactive login with `/etc/ssh/sshd_config.d/000-macsetup.conf`, and turns
on Remote Login. The setting is checked with `sshd -t` and `sshd -T` before anything is turned on,
and put back as it was if a check fails. Once it is on, only that key can log in, so losing it means
going to the Mac in person.

Tested on an M1 Mac mini with macOS 27.2:

- The script turned Remote Login on itself, with no visit to System Settings.
- Key login works, and the Mac offers no login method but `publickey`.
- With FileVault off, SSH is back about 15 seconds after a restart, before anyone logs in.
- A run over SSH with no terminal installs nothing optional and doesn't prompt.
- `<name>.local` didn't resolve on the home network, so connect by IP address, ideally one reserved
  for the Mac on the router.

### Screen Sharing

Turn it on once by hand in System Settings > General > Sharing. The run checks that port 5900 is
open and that only Administrators may connect, and lists anything else under "Do by hand". It
reports "port open, not tested from another machine", as an open port is all it can check.

The script doesn't turn Screen Sharing on itself. On macOS 27.2, starting it with `launchctl` opens
the port and accepts the password, but without the permissions to show the screen or take control,
which only the switch in System Settings grants. Viewers then get "Screen Sharing is not permitted".
If that happens, switch it off and on again in System Settings.

Connect with `vnc://<IP address>` using the Mac's account password. It doesn't use the SSH key.

### Changing the setup

`~/.macsetup` is a working copy, and `~/.p10k.zsh` links into it, so edits show up in its
`git status`, and the summary warns about them. It's cloned over HTTPS, as a new Mac has no SSH key.
To push from a Mac that holds the key:

```bash
git -C ~/.macsetup remote set-url origin git@github.com:bartlomn/macsetup.git
git -C ~/.macsetup push
```

### Tests

For development, `brew install bats-core shellcheck gum`, then:

```bash
bats tests/
shellcheck -x bootstrap.sh install.sh macos.sh lib/*.sh
```

The tests use a temporary `HOME` and fake commands. Don't run the scripts themselves on a Mac you
don't want changed.

## Running on Ubuntu

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/bartlomn/macsetup/main/ubuntu_setup.sh)"
```
