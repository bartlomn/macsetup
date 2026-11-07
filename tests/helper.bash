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
}
