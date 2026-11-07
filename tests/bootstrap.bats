#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  export MACSETUP_BREW_PATHS="$HOME/brew/bin/brew"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  UPSTREAM="$BATS_TEST_TMPDIR/upstream.git"
  make_upstream "$UPSTREAM"
  export MACSETUP_REPO_URL="$UPSTREAM"
}

# A bare repo whose install.sh logs its arguments and the handover environment.
make_upstream() {
  local bare="$1" work="$BATS_TEST_TMPDIR/work-$RANDOM"
  git init -q --bare -b main "$bare"
  git clone -q "$bare" "$work" 2>/dev/null
  cat > "$work/install.sh" <<'SCRIPT'
#!/bin/bash
printf 'install.sh args=[%s] no_picker=[%s] failures=[%s] no_sudo=[%s]\n' "$*" "${MACSETUP_NO_PICKER:-}" "${MACSETUP_BOOTSTRAP_FAILURES:-}" "${MACSETUP_NO_SUDO:-}" >> "$FAKE_LOG"
SCRIPT
  chmod +x "$work/install.sh"
  git -C "$work" add . && git -C "$work" commit -qm first && git -C "$work" push -q origin HEAD:main
  git -C "$work" checkout -q -b foo && echo foo > "$work/on-foo"
  git -C "$work" add . && git -C "$work" commit -qm foo && git -C "$work" push -q origin foo
  git -C "$work" checkout -q main
  WORK="$work"
}

install_fake_brew() {
  mkdir -p "$HOME/brew/bin"
  cp "$FAKES_DIR/brew" "$HOME/brew/bin/brew"
}

run_bootstrap() {
  run /bin/bash "$REPO_ROOT/bootstrap.sh" "$@"
}

run_bootstrap_on_terminal() {
  unset MACSETUP_NONINTERACTIVE
  run "$REPO_ROOT/tests/in_pty.py" "/bin/bash '$REPO_ROOT/bootstrap.sh'"
}

handed_over() {
  grep -q '^install.sh ' "$FAKE_LOG"
}

@test "non-admin stops" {
  install_fake_brew
  FAKE_ID_GROUPS="staff" run_bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"administrator"* ]]
  ! grep -q '^brew ' "$FAKE_LOG"
  [ ! -e "$HOME/.macsetup" ]
}

@test "no terminal and no brew stops" {
  run_bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"Homebrew"* ]]
  ! grep -q '^brew-installer' "$FAKE_LOG"
  ! handed_over
}

@test "no terminal with brew continues" {
  install_fake_brew
  run_bootstrap --all
  [ "$status" -eq 0 ]
  grep -q 'install.sh args=\[--all\]' "$FAKE_LOG"
  ! grep -q '^sudo -v' "$FAKE_LOG"
}

@test "fresh Mac installs brew noninteractively, then gum, then clones" {
  run_bootstrap_on_terminal
  [ "$status" -eq 0 ]
  grep -q '^sudo -v' "$FAKE_LOG"
  grep -q '^brew-installer NONINTERACTIVE=1' "$FAKE_LOG"
  grep -q '^brew install gum' "$FAKE_LOG"
  [ "$(grep -n '^brew-installer' "$FAKE_LOG" | cut -d: -f1)" -lt "$(grep -n '^brew install gum' "$FAKE_LOG" | cut -d: -f1)" ]
  [ -f "$HOME/.macsetup/install.sh" ]
  handed_over
}

@test "brew install failure stops" {
  FAKE_BREW_INSTALL_FAIL=1 run_bootstrap_on_terminal
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.macsetup" ]
  ! handed_over
}

@test "brew installer download failure stops" {
  FAKE_CURL_FAIL=1 run_bootstrap_on_terminal
  [ "$status" -ne 0 ]
  ! grep -q '^brew-installer' "$FAKE_LOG"
  ! handed_over
}

@test "gum failure continues" {
  install_fake_brew
  FAKE_GUM_INSTALL_FAIL=1 run_bootstrap
  [ "$status" -eq 0 ]
  grep -q 'no_picker=\[1\] failures=\[gum install\]' "$FAKE_LOG"
}

@test "gum already installed is not reinstalled" {
  install_fake_brew
  FAKE_GUM_INSTALLED=1 run_bootstrap
  [ "$status" -eq 0 ]
  ! grep -q '^brew install' "$FAKE_LOG"
  grep -q 'no_picker=\[\] failures=\[\]' "$FAKE_LOG"
}

@test "sudo failure, brew missing, stops" {
  FAKE_SUDO_FAIL=1 run_bootstrap_on_terminal
  [ "$status" -ne 0 ]
  ! grep -q '^brew-installer' "$FAKE_LOG"
  ! handed_over
}

@test "sudo failure, brew present, continues" {
  install_fake_brew
  FAKE_SUDO_FAIL=1 run_bootstrap_on_terminal
  [ "$status" -eq 0 ]
  grep -q 'no_sudo=\[1\]' "$FAKE_LOG"
}

@test "no terminal without sudo credentials flags it" {
  install_fake_brew
  FAKE_SUDO_FAIL=1 run_bootstrap
  [ "$status" -eq 0 ]
  grep -q 'no_sudo=\[1\]' "$FAKE_LOG"
}

@test "fresh clone" {
  install_fake_brew
  run_bootstrap
  [ "$status" -eq 0 ]
  [ "$(git -C "$HOME/.macsetup" rev-parse --abbrev-ref HEAD)" = "main" ]
  [ -z "$(ls -a "$HOME" | grep '\.tmp\.')" ]
}

@test "branch is honoured" {
  install_fake_brew
  MACSETUP_BRANCH=foo run_bootstrap
  [ "$status" -eq 0 ]
  [ -f "$HOME/.macsetup/on-foo" ]
}

@test "clone failure stops" {
  install_fake_brew
  MACSETUP_REPO_URL="$BATS_TEST_TMPDIR/no-such-repo.git" run_bootstrap
  [ "$status" -ne 0 ]
  ! handed_over
  [ ! -e "$HOME/.macsetup" ]
  [ -z "$(ls -a "$HOME" | grep '\.tmp\.')" ]
}

@test "re-run pulls" {
  install_fake_brew
  run_bootstrap
  echo new > "$WORK/new-file"
  git -C "$WORK" add . && git -C "$WORK" commit -qm second && git -C "$WORK" push -q origin HEAD:main
  run_bootstrap
  [ "$status" -eq 0 ]
  [ -f "$HOME/.macsetup/new-file" ]
}

@test "uncommitted changes skip the pull" {
  install_fake_brew
  run_bootstrap
  echo '# mine' >> "$HOME/.macsetup/install.sh"
  echo new > "$WORK/new-file"
  git -C "$WORK" add . && git -C "$WORK" commit -qm second && git -C "$WORK" push -q origin HEAD:main
  : > "$FAKE_LOG"
  run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.macsetup/new-file" ]
  grep -q mine "$HOME/.macsetup/install.sh"
  [[ "$output" == *"uncommitted"* ]]
  handed_over
}

@test "failed pull keeps the clone and reports it" {
  install_fake_brew
  run_bootstrap
  mv "$UPSTREAM" "$UPSTREAM.gone"
  : > "$FAKE_LOG"
  mkdir "$UPSTREAM"
  run_bootstrap
  [ "$status" -eq 0 ]
  [ -f "$HOME/.macsetup/install.sh" ]
  grep -q 'failures=\[repo update\]' "$FAKE_LOG"
}

@test "invalid clone moved aside" {
  install_fake_brew
  mkdir "$HOME/.macsetup"
  echo precious > "$HOME/.macsetup/file"
  run_bootstrap
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME"/.macsetup.macsetup-bak-*/file)" = "precious" ]
  git -C "$HOME/.macsetup" rev-parse --git-dir >/dev/null
  handed_over
}

@test "different repo moved aside" {
  install_fake_brew
  make_upstream "$BATS_TEST_TMPDIR/other.git"
  git clone -q "$BATS_TEST_TMPDIR/other.git" "$HOME/.macsetup"
  run_bootstrap
  [ "$status" -eq 0 ]
  [ "$(git -C "$HOME/.macsetup" remote get-url origin)" = "$UPSTREAM" ]
  [ "$(git -C "$HOME"/.macsetup.macsetup-bak-* remote get-url origin)" = "$BATS_TEST_TMPDIR/other.git" ]
}

@test "clone switched to the SSH remote still counts as this repo" {
  install_fake_brew
  mkdir -p "$HOME/.macsetup"
  git init -q -b main "$HOME/.macsetup"
  git -C "$HOME/.macsetup" remote add origin git@github.com:bartlomn/macsetup.git
  cp "$UPSTREAM/HEAD" "$HOME/.macsetup/untouched"
  touch "$HOME/.macsetup/install.sh"
  GIT_SSH_COMMAND=false MACSETUP_REPO_URL="https://github.com/bartlomn/macsetup.git" run_bootstrap
  [ -f "$HOME/.macsetup/untouched" ]
  [ -z "$(ls -a "$HOME" | grep 'macsetup-bak')" ]
}

@test "zprofile line added once" {
  install_fake_brew
  run_bootstrap
  run_bootstrap
  [ "$(grep -c 'brew shellenv' "$HOME/.zprofile")" -eq 1 ]
}

@test "zprofile keeps an existing last line intact" {
  install_fake_brew
  printf 'export KEPT=1' > "$HOME/.zprofile"
  run_bootstrap
  grep -qx 'export KEPT=1' "$HOME/.zprofile"
}

@test "unwritable zprofile is reported" {
  install_fake_brew
  mkdir "$HOME/.zprofile"
  run_bootstrap
  [ "$status" -eq 0 ]
  grep -q 'failures=\[zprofile\]' "$FAKE_LOG"
}

@test "failures are joined for install.sh" {
  install_fake_brew
  mkdir "$HOME/.zprofile"
  FAKE_GUM_INSTALL_FAIL=1 run_bootstrap
  grep -q 'failures=\[zprofile;gum install\]' "$FAKE_LOG"
}

@test "truncated script does nothing" {
  install_fake_brew
  local count half="$BATS_TEST_TMPDIR/half.sh"
  count="$(wc -l < "$REPO_ROOT/bootstrap.sh")"
  head -n $((count / 2)) "$REPO_ROOT/bootstrap.sh" > "$half"
  run /bin/bash "$half"
  [ ! -s "$FAKE_LOG" ]
  [ ! -e "$HOME/.macsetup" ]
  head -n $((count - 1)) "$REPO_ROOT/bootstrap.sh" > "$half"
  run /bin/bash "$half"
  [ ! -s "$FAKE_LOG" ]
  [ ! -e "$HOME/.macsetup" ]
}

@test "one-liner fails on bad URL" {
  export FAKE_CURL_FAIL=1
  run /bin/bash -c 'f="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/bartlomn/macsetup/main/bootstrap.sh -o "$f" && /bin/bash "$f"'
  [ "$status" -ne 0 ]
  ! grep -q '^brew' "$FAKE_LOG"
  ! grep -q '^sudo' "$FAKE_LOG"
}
