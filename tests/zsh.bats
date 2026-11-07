#!/usr/bin/env bats

# Real zsh startup checks. Needs Oh My Zsh with the theme and plugins, so it skips on a Mac without.

load helper

setup() {
  [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ] || skip "Oh My Zsh is not installed"
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ] || skip "Powerlevel10k is not installed"
}

@test "full config starts clean with the theme, alias and plugins" {
  run "$REPO_ROOT/tests/zsh_startup.py" "$REPO_ROOT" full
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "instant prompt shows before a slow config finishes" {
  run "$REPO_ROOT/tests/zsh_startup.py" "$REPO_ROOT" delay
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "missing tools cause no errors and leave ls working" {
  run "$REPO_ROOT/tests/zsh_startup.py" "$REPO_ROOT" no-tools
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "missing Oh My Zsh gives a clear message and no errors" {
  run "$REPO_ROOT/tests/zsh_startup.py" "$REPO_ROOT" no-omz
  echo "$output"
  [ "$status" -eq 0 ]
}
