# Writes the stub ~/.zshrc, links the prompt config, and installs Oh My Zsh, the theme, the plugins
# and the fonts. Each has its own check, and anything fetched is moved into place once complete,
# so an interrupted run blocks nothing.

MACSETUP_STUB_LINE='source ~/.macsetup/zsh/zshrc.zsh'
MACSETUP_OMZ_INSTALLER_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
MACSETUP_FONT_BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"

shell_write_stub() {
  local rc="$HOME/.zshrc"
  grep -qxF "$MACSETUP_STUB_LINE" "$rc" 2>/dev/null && return 0
  timestamped_backup "$rc" || return 1
  printf '%s\n# Machine-specific settings and secrets go below this line\n' "$MACSETUP_STUB_LINE" > "$rc"
}

shell_link_p10k() {
  local link="$HOME/.p10k.zsh" target="$HOME/.macsetup/p10k.zsh"
  [ "$(readlink "$link" 2>/dev/null)" = "$target" ] && return 0
  timestamped_backup "$link" || return 1
  ln -s "$target" "$link"
}

_omz_is_valid() {
  local dir="$HOME/.oh-my-zsh"
  [ -f "$dir/oh-my-zsh.sh" ] && [ -e "$dir/.git" ] && git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1
}

shell_install_omz() {
  local dir="$HOME/.oh-my-zsh" installer status
  _omz_is_valid && return 0
  timestamped_backup "$dir" || return 1
  installer="$(mktemp)" || return 1
  if ! curl -fsSL "$MACSETUP_OMZ_INSTALLER_URL" -o "$installer"; then
    rm -f "$installer"
    return 1
  fi
  sh "$installer" --unattended --keep-zshrc
  status=$?
  rm -f "$installer"
  return "$status"
}

# Clones beside the target and moves into place, so "it exists" means "it finished".
_clone_once() {
  local url="$1" target="$2" tmp
  [ -e "$target" ] && return 0
  mkdir -p "$(dirname "$target")" || return 1
  tmp="$(mktemp -d "$target.tmp.XXXXXX")" || return 1
  if ! git clone -q --depth=1 "$url" "$tmp/repo" || ! mv "$tmp/repo" "$target"; then
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
}

shell_install_theme() {
  _clone_once "${MACSETUP_P10K_URL:-https://github.com/romkatv/powerlevel10k.git}" \
    "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
}

shell_install_plugins() {
  local failed=0 plugins="$HOME/.oh-my-zsh/custom/plugins"
  _clone_once "${MACSETUP_AUTOSUGGEST_URL:-https://github.com/zsh-users/zsh-autosuggestions.git}" \
    "$plugins/zsh-autosuggestions" || failed=1
  _clone_once "${MACSETUP_SYNTAX_URL:-https://github.com/zsh-users/zsh-syntax-highlighting.git}" \
    "$plugins/zsh-syntax-highlighting" || failed=1
  return "$failed"
}

shell_install_fonts() {
  local dir="${MACSETUP_FONTS_DIR:-/Library/Fonts}" style failed=0
  for style in Regular Bold Italic "Bold Italic"; do
    [ -s "$dir/MesloLGS NF $style.ttf" ] && continue
    download_atomic "$MACSETUP_FONT_BASE_URL/MesloLGS%20NF%20${style// /%20}.ttf" \
      "$dir/MesloLGS NF $style.ttf" || failed=1
  done
  return "$failed"
}

_step_if_needed() {
  # Stays out of the summary and output when the check shows there is nothing to do.
  local check="$1" label="$2"
  shift 2
  "$check" && return 0
  step "$label" "$@"
}

_stub_done() { grep -qxF "$MACSETUP_STUB_LINE" "$HOME/.zshrc" 2>/dev/null; }
_p10k_done() { [ "$(readlink "$HOME/.p10k.zsh" 2>/dev/null)" = "$HOME/.macsetup/p10k.zsh" ]; }
_theme_done() { [ -e "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; }
_plugins_done() {
  [ -e "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ] &&
    [ -e "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]
}
_fonts_done() {
  local dir="${MACSETUP_FONTS_DIR:-/Library/Fonts}" style
  for style in Regular Bold Italic "Bold Italic"; do
    [ -s "$dir/MesloLGS NF $style.ttf" ] || return 1
  done
}

shell_step() {
  local failed=0
  _step_if_needed _stub_done "Write the ~/.zshrc stub" shell_write_stub || failed=1
  _step_if_needed _p10k_done "Link ~/.p10k.zsh" shell_link_p10k || failed=1
  if _step_if_needed _omz_is_valid "Install Oh My Zsh" shell_install_omz; then
    _step_if_needed _theme_done "Install Powerlevel10k" shell_install_theme || failed=1
    _step_if_needed _plugins_done "Install zsh plugins" shell_install_plugins || failed=1
  else
    failed=1
    skip_step "Theme and plugins" "Oh My Zsh is not installed"
  fi
  _step_if_needed _fonts_done "Install fonts" shell_install_fonts || failed=1
  return "$failed"
}
