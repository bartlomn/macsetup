#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  export MACSETUP_BREW_PATHS="$HOME/brew/bin/brew"
  export FAKE_BREW_INFO="$REPO_ROOT/tests/fixtures/brew_info.json"
  export MACSETUP_APPS_DIR="$BATS_TEST_TMPDIR/Applications"
  export MACSETUP_FONTS_DIR="$BATS_TEST_TMPDIR/Fonts"
  export MACSETUP_SOCKETFILTERFW="$FAKES_DIR/socketfilterfw"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  mkdir -p "$MACSETUP_APPS_DIR" "$MACSETUP_FONTS_DIR" "$HOME/Library" "$HOME/brew/bin"
  cp "$FAKES_DIR/brew" "$HOME/brew/bin/brew"
  local bare="$BATS_TEST_TMPDIR/addon.git" work="$BATS_TEST_TMPDIR/addon-work"
  git init -q --bare -b main "$bare"
  git clone -q "$bare" "$work" 2>/dev/null
  git -C "$work" commit -q --allow-empty -m first
  git -C "$work" push -q origin HEAD:main
  export MACSETUP_P10K_URL="$bare" MACSETUP_AUTOSUGGEST_URL="$bare" MACSETUP_SYNTAX_URL="$bare"
  CLONE="$HOME/.macsetup"
}

# A clone holding the real scripts, with a small Brewfile the fixture knows about.
make_tree() {
  local dir="$1"
  mkdir -p "$dir"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/ssh" "$REPO_ROOT/zsh" "$REPO_ROOT/p10k.zsh" "$REPO_ROOT/install.sh" "$REPO_ROOT/macos.sh" "$dir/"
  printf 'cask "zen"\ncask "vlc" # optional\nbrew "eza"\n' > "$dir/Brewfile"
  git init -q -b main "$dir"
  git -C "$dir" add .
  git -C "$dir" commit -qm first
}

run_install() {
  run /bin/bash "$CLONE/install.sh" "$@"
}

run_install_on_terminal() {
  unset MACSETUP_NONINTERACTIVE
  run "$REPO_ROOT/tests/in_pty.py" "/bin/bash '$CLONE/install.sh' $*"
}

bundled() {
  cat "$FAKE_LOG.bundle" 2>/dev/null
}

@test "mode selection: no terminal installs only defaults" {
  make_tree "$CLONE"
  run_install
  [ "$status" -eq 0 ]
  ! grep -q '^gum' "$FAKE_LOG" || false
  [ "$(bundled)" = $'cask "zen"\nbrew "eza"' ]
}

@test "mode selection: --all includes optional items" {
  make_tree "$CLONE"
  run_install --all
  [ "$status" -eq 0 ]
  ! grep -q '^gum' "$FAKE_LOG" || false
  [ "$(bundled)" = $'cask "zen"\ncask "vlc" # optional\nbrew "eza"' ]
}

@test "mode selection: a terminal gets the picker" {
  make_tree "$CLONE"
  run_install_on_terminal
  [ "$status" -eq 0 ]
  grep -q '^gum choose' "$FAKE_LOG"
  grep -q '^sudo -v' "$FAKE_LOG"
}

@test "mode selection: MACSETUP_NO_PICKER on a terminal uses defaults" {
  make_tree "$CLONE"
  export MACSETUP_NO_PICKER=1
  run_install_on_terminal
  [ "$status" -eq 0 ]
  ! grep -q '^gum' "$FAKE_LOG" || false
  [ "$(bundled)" = $'cask "zen"\nbrew "eza"' ]
}

@test "finds brew off PATH" {
  make_tree "$CLONE"
  local nobrew="$BATS_TEST_TMPDIR/nobrew"
  cp -R "$FAKES_DIR" "$nobrew"
  rm "$nobrew/brew"
  PATH="$nobrew:/usr/bin:/bin" run_install
  [ "$status" -eq 0 ]
  [ "$(bundled)" = $'cask "zen"\nbrew "eza"' ]
}

@test "no brew fails clearly and the rest still runs" {
  make_tree "$CLONE"
  MACSETUP_BREW_PATHS="$HOME/nothing/brew" run_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew"* ]]
  [ ! -e "$FAKE_LOG.bundle" ]
  [ -f "$HOME/.zshrc" ]
  grep -q '^defaults write' "$FAKE_LOG"
}

@test "runs from any directory" {
  make_tree "$CLONE"
  cd /
  run_install
  [ "$status" -eq 0 ]
  [ -f "$HOME/.zshrc" ]
}

@test "unknown flag" {
  make_tree "$CLONE"
  run_install --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
  [ ! -s "$FAKE_LOG" ]
  [ ! -e "$HOME/.zshrc" ]
}

@test "one failure does not stop the rest" {
  make_tree "$CLONE"
  FAKE_BREW_INFO_FAIL=1 run_install
  [ "$status" -eq 1 ]
  [ -f "$HOME/.zshrc" ]
  grep -q '^defaults write' "$FAKE_LOG"
}

@test "macOS settings summary is included" {
  make_tree "$CLONE"
  FAKE_DEFAULTS_WRITE_FAIL=autohide run_install
  [ "$status" -eq 1 ]
  [[ "$(printf '%s\n' "$output" | sed -n '/^FAILED:$/,$p')" == *"autohide"* ]]
}

@test "bootstrap failure carried through" {
  local tree="$BATS_TEST_TMPDIR/tree" bare="$BATS_TEST_TMPDIR/upstream.git"
  make_tree "$tree"
  git clone -q --bare "$tree" "$bare"
  FAKE_GUM_INSTALL_FAIL=1 MACSETUP_REPO_URL="$bare" run /bin/bash "$REPO_ROOT/bootstrap.sh"
  [ "$status" -eq 1 ]
  [[ "$(printf '%s\n' "$output" | sed -n '/^FAILED:$/,$p')" == *"gum install"* ]]
  [ "$(bundled)" = $'cask "zen"\nbrew "eza"' ]
}

@test "every bootstrap failure is named" {
  make_tree "$CLONE"
  MACSETUP_BOOTSTRAP_FAILURES="zprofile;repo update" run_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"zprofile"* ]]
  [[ "$output" == *"repo update"* ]]
}

@test "no sudo flag respected" {
  make_tree "$CLONE"
  MACSETUP_NO_SUDO=1 run_install
  [ "$status" -eq 2 ]
  ! grep -q '^sudo' "$FAKE_LOG" || false
  [[ "$output" == *"Skipped"* ]]
}

@test "no terminal without sudo credentials reports privileged steps" {
  make_tree "$CLONE"
  FAKE_SUDO_FAIL=1 run_install
  [ "$status" -eq 2 ]
  ! grep -q '^pmset -' "$FAKE_LOG" || false
  [[ "$output" == *"Skipped"* ]]
}

@test "uncommitted changes warn" {
  make_tree "$CLONE"
  echo '# tweak' >> "$CLONE/zsh/zshrc.zsh"
  run_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted"* ]]
}

@test "Terminal.app gets the font note, kitty does not" {
  make_tree "$CLONE"
  TERM_PROGRAM=Apple_Terminal run_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"MesloLGS NF"* ]]
  TERM_PROGRAM=kitty run_install
  [[ "$output" != *"MesloLGS NF"* ]]
}

@test "re-run is quiet" {
  make_tree "$CLONE"
  run_install --all
  [ "$status" -eq 0 ]
  : > "$FAKE_LOG"
  rm -f "$FAKE_LOG.bundle"
  run_install --all
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_LOG.bundle" ]
  ! grep -q '^defaults write' "$FAKE_LOG" || false
  ! grep -q '^killall' "$FAKE_LOG" || false
  ! grep -q '^pmset -[ca]' "$FAKE_LOG" || false
  ! grep -q '^omz-installer' "$FAKE_LOG" || false
  ! grep -q '^curl' "$FAKE_LOG" || false
  [ -z "$(ls -a "$HOME" | grep 'macsetup-bak')" ]
}

@test "ssh and screen sharing steps are optional files" {
  make_tree "$CLONE"
  printf 'ssh_step() { printf "ssh_step ran\\n" >> "$FAKE_LOG"; }\n' > "$CLONE/lib/ssh.sh"
  printf 'screensharing_step() { printf "screensharing_step ran\\n" >> "$FAKE_LOG"; }\n' > "$CLONE/lib/screensharing.sh"
  run_install
  grep -q '^ssh_step ran' "$FAKE_LOG"
  grep -q '^screensharing_step ran' "$FAKE_LOG"
}
