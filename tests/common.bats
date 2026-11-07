#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  source "$REPO_ROOT/lib/common.sh"
}

@test "step records failure and continues" {
  step "first thing" false || true
  step "second thing" touch "$HOME/ran"
  run print_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"first thing"* ]]
  [ -f "$HOME/ran" ]
}

@test "step returns the status" {
  step "a" false && step "b" touch "$HOME/b-ran" || true
  [ ! -e "$HOME/b-ran" ]
  run print_summary
  [[ "$output" != *"b"$'\n'* ]]
  [[ "$output" != *" b" ]]
}

@test "step passes arguments intact" {
  step "spaces" touch "$HOME/a file with spaces"
  [ -f "$HOME/a file with spaces" ]
}

@test "manual step alone exits 2" {
  step "fine" true
  manual_step "Turn on Remote Login"
  run print_summary
  [ "$status" -eq 2 ]
  [[ "$output" == *"Turn on Remote Login"* ]]
}

@test "all ok exits 0" {
  step "fine" true
  run print_summary
  [ "$status" -eq 0 ]
}

@test "failure beats manual" {
  manual_step "Do a thing"
  step "broken" false || true
  run print_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"Do a thing"* ]]
  [[ "$output" == *"broken"* ]]
}

@test "record_failure makes the run fail" {
  record_failure "gum install"
  run print_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"gum install"* ]]
}

@test "skip and warn do not change the exit code" {
  skip_step "pmset" "no sudo"
  warn "uncommitted changes"
  run print_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"pmset"* ]]
  [[ "$output" == *"no sudo"* ]]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "backup never collides" {
  local target="$HOME/config"
  echo one > "$target"
  timestamped_backup "$target"
  echo two > "$target"
  timestamped_backup "$target"
  [ ! -e "$target" ]
  [ "$(ls "$HOME" | grep -c '^config\.macsetup-bak-')" -eq 2 ]
  [ "$(cat "$HOME"/config.macsetup-bak-* | sort | tr '\n' ' ')" = "one two " ]
}

@test "backup moves a directory" {
  mkdir "$HOME/dir"
  echo kept > "$HOME/dir/file"
  timestamped_backup "$HOME/dir"
  [ ! -e "$HOME/dir" ]
  [ "$(cat "$HOME"/dir.macsetup-bak-*/file)" = "kept" ]
}

@test "backup moves a dangling symlink" {
  ln -s "$HOME/nowhere" "$HOME/link"
  timestamped_backup "$HOME/link"
  [ ! -L "$HOME/link" ]
  [ -L "$(ls -d "$HOME"/link.macsetup-bak-*)" ]
}

@test "backup moves a symlink rather than what it points to" {
  mkdir "$HOME/real"
  echo kept > "$HOME/real/file"
  ln -s "$HOME/real" "$HOME/link"
  timestamped_backup "$HOME/link"
  [ ! -L "$HOME/link" ]
  [ "$(cat "$HOME/real/file")" = "kept" ]
}

@test "download failure leaves dest untouched" {
  local dest="$HOME/dl/file"
  mkdir -p "$HOME/dl"
  echo original > "$dest"
  FAKE_CURL_FAIL=1 run download_atomic "https://example.invalid/x" "$dest"
  [ "$status" -ne 0 ]
  [ "$(cat "$dest")" = "original" ]
  [ "$(ls "$HOME/dl")" = "file" ]
}

@test "download replaces dest and is world readable" {
  local dest="$HOME/font.ttf"
  FAKE_CURL_BODY=new run download_atomic "https://example.invalid/x" "$dest"
  [ "$status" -eq 0 ]
  [ "$(cat "$dest")" = "new" ]
  [ "$(stat -f %Lp "$dest")" = "644" ]
  [ "$(ls "$HOME")" = "font.ttf" ]
  grep -q -- '-fsSL' "$FAKE_LOG"
}

@test "port_open reports the port state" {
  FAKE_OPEN_PORTS="22" run port_open 22
  [ "$status" -eq 0 ]
  FAKE_OPEN_PORTS="22" run port_open 5900
  [ "$status" -ne 0 ]
}

@test "is_interactive is false without a terminal" {
  unset MACSETUP_NONINTERACTIVE
  run is_interactive < /dev/null
  [ "$status" -ne 0 ]
}

in_pty() {
  "$REPO_ROOT/tests/in_pty.py" "$1"
}

@test "is_interactive is true on a terminal" {
  unset MACSETUP_NONINTERACTIVE
  run in_pty "source '$REPO_ROOT/lib/common.sh'; is_interactive"
  [ "$status" -eq 0 ]
}

@test "MACSETUP_NONINTERACTIVE overrides a terminal" {
  run in_pty "MACSETUP_NONINTERACTIVE=1; source '$REPO_ROOT/lib/common.sh'; is_interactive"
  [ "$status" -ne 0 ]
}
