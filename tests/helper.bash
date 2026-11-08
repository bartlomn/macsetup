# Shared bats helpers. Nothing here may touch the real HOME.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKES_DIR="$REPO_ROOT/tests/fakes"

# Gives a test a temp HOME, fake commands first on PATH, and a log of fake calls.
setup_sandbox() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export PATH="$FAKES_DIR:$PATH"
  export FAKE_LOG="$BATS_TEST_TMPDIR/fake.log"
  : > "$FAKE_LOG"
  export MACSETUP_NONINTERACTIVE=1
  # System paths and commands point into the sandbox, so no test reaches the real /etc/ssh.
  export MACSETUP_SSH_DIR="$BATS_TEST_TMPDIR/etc_ssh"
  mkdir -p "$MACSETUP_SSH_DIR/sshd_config.d"
  export MACSETUP_SSHD="$FAKES_DIR/sshd"
  export MACSETUP_SSH_KEYGEN="$FAKES_DIR/ssh-keygen"
  export MACSETUP_LAUNCHCTL="$FAKES_DIR/launchctl"
  export MACSETUP_SYSTEMSETUP="$FAKES_DIR/systemsetup"
  export MACSETUP_DSCL="$FAKES_DIR/dscl"
  export MACSETUP_PORT_WAIT=1
}
