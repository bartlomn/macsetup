#!/usr/bin/python3
"""Runs a bash snippet on a real pty and exits with its status. Gives up after 20 seconds."""
import os
import pty
import signal
import sys

pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", "-c", sys.argv[1]])

signal.signal(signal.SIGALRM, lambda *_: (os.kill(pid, signal.SIGKILL), sys.exit(124)))
signal.alarm(20)
try:
    while os.read(fd, 4096):
        pass
except OSError:
    pass
_, status = os.waitpid(pid, 0)
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
