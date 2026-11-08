#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
}

SNIPPET="source '$REPO_ROOT/lib/common.sh'; source '$REPO_ROOT/lib/screensharing.sh'; screensharing_step; step after true; print_summary"
LABEL="Screen Sharing: port open, not tested from another machine"

run_ss() {
  run /bin/bash -c "$SNIPPET"
}

called() {
  grep -q "^$1" "$FAKE_LOG"
}

# Nothing the step does may start, stop or reconfigure a service.
changed_nothing() {
  ! called sudo || false
  ! called launchctl || false
  ! called dseditgroup || false
  ! grep -q 'kickstart' "$FAKE_LOG" || false
}

@test "already open, access correct" {
  FAKE_OPEN_PORTS=5900 run_ss
  [ "$status" -eq 0 ]
  changed_nothing
  ! called open || false
  [[ "$output" == *"Done:"*"$LABEL"* ]]
}

@test "summary wording" {
  FAKE_OPEN_PORTS=5900 run_ss
  grep -qxF "  $LABEL" <<< "$output"
}

@test "already open, another account allowed" {
  FAKE_OPEN_PORTS=5900 FAKE_SS_ACCESS=user run_ss
  [ "$status" -eq 2 ]
  changed_nothing
  [[ "$output" == *"Do by hand:"*"Administrators"* ]]
  [[ "$output" != *"$LABEL"* ]]
}

@test "already open, another group allowed" {
  FAKE_OPEN_PORTS=5900 FAKE_SS_ACCESS=group run_ss
  [ "$status" -eq 2 ]
  [[ "$output" == *"Do by hand:"*"Administrators"* ]]
  [[ "$output" != *"$LABEL"* ]]
}

@test "already open, all users allowed" {
  FAKE_OPEN_PORTS=5900 FAKE_SS_ACCESS=all run_ss
  [ "$status" -eq 2 ]
  changed_nothing
  [[ "$output" == *"Do by hand:"*"Administrators"* ]]
  [[ "$output" != *"$LABEL"* ]]
}

@test "access unreadable" {
  FAKE_OPEN_PORTS=5900 FAKE_SS_ACCESS=error run_ss
  [ "$status" -eq 2 ]
  [[ "$output" == *"Do by hand:"*"Check who may use Screen Sharing"* ]]
  [[ "$output" != *"$LABEL"* ]]
}

@test "port closed: never starts the service itself" {
  run_ss
  [ "$status" -eq 2 ]
  changed_nothing
  [[ "$output" == *"Do by hand:"*"Turn on Screen Sharing in System Settings"* ]]
  [[ "$output" != *"FAILED"* ]]
  [[ "$output" == *"Done:"*"after"* ]]
}

@test "closed, no terminal: Sharing pane is not opened" {
  run_ss
  ! called open || false
}

@test "closed, terminal: Sharing pane is opened once" {
  unset MACSETUP_NONINTERACTIVE
  FAKE_SS_ACCESS=user run "$REPO_ROOT/tests/in_pty.py" "$SNIPPET"
  [ "$status" -eq 2 ]
  [ "$(grep -c '^open x-apple.systempreferences:com.apple.Sharing-Settings.extension' "$FAKE_LOG")" -eq 1 ]
}

@test "no sudo needed" {
  FAKE_OPEN_PORTS=5900 MACSETUP_NO_SUDO=1 run_ss
  [ "$status" -eq 0 ]
  [[ "$output" == *"$LABEL"* ]]
}
