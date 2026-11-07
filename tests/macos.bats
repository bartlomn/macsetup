#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  export MACSETUP_SOCKETFILTERFW="$FAKES_DIR/socketfilterfw"
  mkdir "$HOME/Library"
  /usr/bin/chflags hidden "$HOME/Library"
}

run_macos() {
  run /bin/bash "$REPO_ROOT/macos.sh"
}

writes() {
  grep -c '^defaults write' "$FAKE_LOG" || true
}

wrote() {
  grep -qxF "defaults write $1" "$FAKE_LOG"
}

@test "first run writes and restarts" {
  run_macos
  [ "$status" -eq 0 ]
  [ "$(writes)" -eq 23 ]
  wrote "com.apple.dock autohide -bool true"
  wrote "com.apple.dock static-only -bool true"
  wrote "com.apple.dock mru-spaces -bool false"
  wrote "com.apple.dock tilesize -int 66"
  wrote "com.apple.dock largesize -int 90"
  wrote "com.apple.finder FXPreferredViewStyle -string clmv"
  wrote "com.apple.finder FXDefaultSearchScope -string SCcf"
  wrote "com.apple.finder _FXSortFoldersFirst -bool true"
  wrote "NSGlobalDomain KeyRepeat -int 2"
  wrote "NSGlobalDomain InitialKeyRepeat -int 15"
  wrote "NSGlobalDomain ApplePressAndHoldEnabled -bool false"
  wrote "NSGlobalDomain com.apple.mouse.tapBehavior -int 1"
  wrote "com.apple.AppleMultitouchTrackpad Clicking -bool true"
  wrote "com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true"
  wrote "com.apple.desktopservices DSDontWriteUSBStores -bool true"
  [ "$(grep -c '^killall Dock' "$FAKE_LOG")" -eq 1 ]
  [ "$(grep -c '^killall Finder' "$FAKE_LOG")" -eq 1 ]
  grep -q 'set dark mode to true' "$FAKE_LOG"
  grep -q '^chflags nohidden' "$FAKE_LOG"
  grep -q '^pmset -c .*sleep 0' "$FAKE_LOG"
  grep -q '^pmset -c .*womp 1' "$FAKE_LOG"
  grep -q '^pmset -a autorestart 1' "$FAKE_LOG"
}

@test "second run changes nothing" {
  run_macos
  : > "$FAKE_LOG"
  run_macos
  [ "$status" -eq 0 ]
  [ "$(writes)" -eq 0 ]
  ! grep -q '^killall' "$FAKE_LOG"
  ! grep -q '^pmset' "$FAKE_LOG"
  ! grep -q '^chflags' "$FAKE_LOG"
  ! grep -q '^osascript' "$FAKE_LOG"
  ! grep -q '^sudo' "$FAKE_LOG"
}

@test "only Dock change restarts only Dock" {
  run_macos
  : > "$FAKE_LOG"
  grep -v '^com.apple.dock|tilesize|' "$FAKE_LOG.defaults" > "$FAKE_LOG.defaults.new"
  mv "$FAKE_LOG.defaults.new" "$FAKE_LOG.defaults"
  run_macos
  [ "$(writes)" -eq 1 ]
  grep -q '^killall Dock' "$FAKE_LOG"
  ! grep -q '^killall Finder' "$FAKE_LOG"
}

@test "bool compare" {
  run_macos
  : > "$FAKE_LOG"
  grep -q '^com.apple.dock|autohide|1$' "$FAKE_LOG.defaults"
  run_macos
  ! grep -q 'autohide' "$FAKE_LOG"
}

@test "extensions domain" {
  run_macos
  wrote "NSGlobalDomain AppleShowAllExtensions -bool true"
  ! grep -q 'com.apple.finder AppleShowAllExtensions' "$FAKE_LOG"
}

@test "a failed write is reported and the rest still run" {
  FAKE_DEFAULTS_WRITE_FAIL=autohide run_macos
  [ "$status" -eq 1 ]
  [[ "$output" == *"autohide"* ]]
  wrote "com.apple.finder ShowPathbar -bool true"
}

@test "no sudo" {
  FAKE_SUDO_FAIL=1 run_macos
  [ "$status" -eq 1 ]
  [ "$(writes)" -eq 23 ]
  ! grep -q '^pmset -' "$FAKE_LOG"
}

@test "MACSETUP_NO_SUDO skips power settings without trying sudo" {
  MACSETUP_NO_SUDO=1 run_macos
  [ "$status" -eq 2 ]
  ! grep -q '^sudo' "$FAKE_LOG"
  [[ "$output" == *"Skipped"* ]]
  [[ "$output" == *"Do by hand"* ]]
}

@test "security is report-only" {
  run_macos
  [[ "$output" == *"FileVault is Off"* ]]
  [[ "$output" == *"Firewall is enabled"* ]]
  ! grep -q '^fdesetup enable' "$FAKE_LOG"
  ! grep -q 'setglobalstate' "$FAKE_LOG"
}

@test "autorestart unsupported" {
  FAKE_PMSET_NO_AUTORESTART=1 run_macos
  [ "$status" -eq 0 ]
  ! grep -q 'autorestart 1' "$FAKE_LOG"
  [[ "$output" == *"autorestart"* ]]
}

@test "battery values are not read as the power adapter's" {
  printf 'sleep 0\nwomp 1\nautorestart 1\n' > "$FAKE_LOG.pmset"
  run_macos
  ! grep -q '^pmset -' "$FAKE_LOG"
}

@test "settings without power source headings are read" {
  printf 'sleep 0\nwomp 1\nautorestart 1\n' > "$FAKE_LOG.pmset"
  FAKE_PMSET_NO_HEADINGS=1 run_macos
  ! grep -q '^pmset -' "$FAKE_LOG"
}
