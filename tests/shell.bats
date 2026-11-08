#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  source "$REPO_ROOT/lib/common.sh"
  source "$REPO_ROOT/lib/shell.sh"
  export MACSETUP_FONTS_DIR="$BATS_TEST_TMPDIR/Fonts"
  mkdir -p "$MACSETUP_FONTS_DIR"
  local bare="$BATS_TEST_TMPDIR/addon.git" work="$BATS_TEST_TMPDIR/addon-work"
  git init -q --bare -b main "$bare"
  git clone -q "$bare" "$work" 2>/dev/null
  git -C "$work" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
  git -C "$work" push -q origin HEAD:main
  export MACSETUP_P10K_URL="$bare" MACSETUP_AUTOSUGGEST_URL="$bare" MACSETUP_SYNTAX_URL="$bare"
  CUSTOM="$HOME/.oh-my-zsh/custom"
  BAD_URL="$BATS_TEST_TMPDIR/no-such-repo.git"
}

valid_omz() {
  "$FAKES_DIR/omz-installer"
  : > "$FAKE_LOG"
}

backups_of() {
  ls -d "$HOME/$1".macsetup-bak-* 2>/dev/null | wc -l | tr -d ' '
}

@test "stub written when absent" {
  shell_write_stub
  [ "$(cat "$HOME/.zshrc")" = "source ~/.macsetup/zsh/zshrc.zsh
# Machine-specific settings and secrets go below this line" ]
}

@test "stub replaces template with backup" {
  echo 'old template' > "$HOME/.zshrc"
  shell_write_stub
  grep -qx 'source ~/.macsetup/zsh/zshrc.zsh' "$HOME/.zshrc"
  [ "$(cat "$HOME"/.zshrc.macsetup-bak-*)" = "old template" ]
}

@test "stub present is left alone" {
  printf 'source ~/.macsetup/zsh/zshrc.zsh\n# Machine-specific settings and secrets go below this line\nexport MINE=1\n' > "$HOME/.zshrc"
  cp "$HOME/.zshrc" "$BATS_TEST_TMPDIR/before"
  shell_write_stub
  cmp "$HOME/.zshrc" "$BATS_TEST_TMPDIR/before"
  [ "$(backups_of .zshrc)" -eq 0 ]
}

@test "commented-out stub line does not count" {
  echo '# source ~/.macsetup/zsh/zshrc.zsh' > "$HOME/.zshrc"
  shell_write_stub
  grep -qx 'source ~/.macsetup/zsh/zshrc.zsh' "$HOME/.zshrc"
  [ "$(backups_of .zshrc)" -eq 1 ]
}

@test "stub survives a dangling symlink" {
  ln -s "$HOME/nowhere" "$HOME/.zshrc"
  shell_write_stub
  [ ! -L "$HOME/.zshrc" ]
  [ -f "$HOME/.zshrc" ]
  [ ! -e "$HOME/nowhere" ]
  [ -L "$(ls -d "$HOME"/.zshrc.macsetup-bak-*)" ]
}

@test "stub does not write through a link to another file" {
  echo 'theirs' > "$HOME/other"
  ln -s "$HOME/other" "$HOME/.zshrc"
  shell_write_stub
  [ ! -L "$HOME/.zshrc" ]
  [ "$(cat "$HOME/other")" = "theirs" ]
}

@test "p10k link created" {
  shell_link_p10k
  [ "$(readlink "$HOME/.p10k.zsh")" = "$HOME/.macsetup/p10k.zsh" ]
}

@test "p10k link idempotent" {
  shell_link_p10k
  shell_link_p10k
  [ "$(backups_of .p10k.zsh)" -eq 0 ]
}

@test "p10k other file backed up" {
  echo mine > "$HOME/.p10k.zsh"
  shell_link_p10k
  [ "$(readlink "$HOME/.p10k.zsh")" = "$HOME/.macsetup/p10k.zsh" ]
  [ "$(cat "$HOME"/.p10k.zsh.macsetup-bak-*)" = "mine" ]
}

@test "p10k dangling or foreign link backed up" {
  ln -s "$HOME/nowhere" "$HOME/.p10k.zsh"
  shell_link_p10k
  [ "$(readlink "$HOME/.p10k.zsh")" = "$HOME/.macsetup/p10k.zsh" ]
  [ "$(backups_of .p10k.zsh)" -eq 1 ]
  ln -sf "$HOME/elsewhere" "$HOME/.p10k.zsh"
  shell_link_p10k
  [ "$(readlink "$HOME/.p10k.zsh")" = "$HOME/.macsetup/p10k.zsh" ]
  [ "$(backups_of .p10k.zsh)" -eq 2 ]
}

@test "omz valid skipped" {
  valid_omz
  shell_install_omz
  ! grep -q '^omz-installer' "$FAKE_LOG" || false
}

@test "omz partial moved aside" {
  mkdir "$HOME/.oh-my-zsh"
  echo leftover > "$HOME/.oh-my-zsh/file"
  shell_install_omz
  grep -q '^omz-installer .*--unattended' "$FAKE_LOG"
  grep -q '^omz-installer .*--keep-zshrc' "$FAKE_LOG"
  [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]
  [ "$(cat "$HOME"/.oh-my-zsh.macsetup-bak-*/file)" = "leftover" ]
}

@test "omz folder with the file but no git clone is moved aside" {
  mkdir "$HOME/.oh-my-zsh"
  touch "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  shell_install_omz
  grep -q '^omz-installer' "$FAKE_LOG"
  [ "$(backups_of .oh-my-zsh)" -eq 1 ]
}

@test "stub written before omz" {
  shell_step > /dev/null 2>&1
  grep -q '^omz-installer saw .zshrc' "$FAKE_LOG"
  [ "$(backups_of .zshrc)" -eq 0 ]
}

@test "theme interrupted" {
  valid_omz
  MACSETUP_P10K_URL="$BAD_URL" run shell_install_theme
  [ "$status" -ne 0 ]
  [ -z "$(ls "$CUSTOM/themes" 2>/dev/null)" ]
  run shell_install_theme
  [ "$status" -eq 0 ]
  [ -d "$CUSTOM/themes/powerlevel10k/.git" ]
  [ "$(ls "$CUSTOM/themes")" = "powerlevel10k" ]
}

@test "theme already there is left alone" {
  valid_omz
  mkdir -p "$CUSTOM/themes/powerlevel10k"
  touch "$CUSTOM/themes/powerlevel10k/kept"
  MACSETUP_P10K_URL="$BAD_URL" run shell_install_theme
  [ "$status" -eq 0 ]
  [ -f "$CUSTOM/themes/powerlevel10k/kept" ]
}

@test "each plugin checked alone" {
  valid_omz
  mkdir -p "$CUSTOM/plugins/zsh-autosuggestions"
  touch "$CUSTOM/plugins/zsh-autosuggestions/kept"
  run shell_install_plugins
  [ "$status" -eq 0 ]
  [ -f "$CUSTOM/plugins/zsh-autosuggestions/kept" ]
  [ -d "$CUSTOM/plugins/zsh-syntax-highlighting/.git" ]
}

@test "one plugin failing still tries the other" {
  valid_omz
  MACSETUP_AUTOSUGGEST_URL="$BAD_URL" run shell_install_plugins
  [ "$status" -ne 0 ]
  [ ! -e "$CUSTOM/plugins/zsh-autosuggestions" ]
  [ -d "$CUSTOM/plugins/zsh-syntax-highlighting/.git" ]
}

@test "font names and curl -f" {
  run shell_install_fonts
  [ "$status" -eq 0 ]
  [ -f "$MACSETUP_FONTS_DIR/MesloLGS NF Regular.ttf" ]
  [ -f "$MACSETUP_FONTS_DIR/MesloLGS NF Bold.ttf" ]
  [ -f "$MACSETUP_FONTS_DIR/MesloLGS NF Italic.ttf" ]
  [ -f "$MACSETUP_FONTS_DIR/MesloLGS NF Bold Italic.ttf" ]
  [ "$(ls "$MACSETUP_FONTS_DIR" | wc -l | tr -d ' ')" -eq 4 ]
  [ "$(grep -c '^curl -fsSL .*MesloLGS%20NF%20' "$FAKE_LOG")" -eq 4 ]
}

@test "fonts already present are not fetched again" {
  shell_install_fonts
  : > "$FAKE_LOG"
  shell_install_fonts
  ! grep -q '^curl' "$FAKE_LOG" || false
}

@test "font failure leaves no file" {
  FAKE_CURL_FAIL=1 run shell_install_fonts
  [ "$status" -ne 0 ]
  [ -z "$(ls "$MACSETUP_FONTS_DIR")" ]
  [ "$(grep -c '^curl' "$FAKE_LOG")" -eq 4 ]
}

@test "omz failure is reported" {
  FAKE_OMZ_FAIL=1 shell_step > /dev/null 2>&1 || true
  run print_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"Oh My Zsh"* ]]
  [ -f "$HOME/.zshrc" ]
  [ -L "$HOME/.p10k.zsh" ]
  [ -f "$MACSETUP_FONTS_DIR/MesloLGS NF Regular.ttf" ]
  [ ! -e "$CUSTOM/themes/powerlevel10k" ]
}

@test "shell_step succeeds on a clean run and is quiet the second time" {
  shell_step > /dev/null
  [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]
  [ -d "$CUSTOM/themes/powerlevel10k" ]
  [ -d "$CUSTOM/plugins/zsh-syntax-highlighting" ]
  : > "$FAKE_LOG"
  shell_step > /dev/null
  [ ! -s "$FAKE_LOG" ]
  [ "$(backups_of .zshrc)" -eq 0 ]
}
