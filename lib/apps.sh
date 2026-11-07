# Brewfile parsing, classification of what is already installed, and the picker.

MACSETUP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prints kind<TAB>token<TAB>tier for each entry. A trailing "# optional" sets the tier.
brewfile_items() {
  awk '
    match($0, /^(brew|cask) "[^"]+"/) {
      split(substr($0, RSTART, RLENGTH), parts, /[ "]+/)
      print parts[1] "\t" parts[2] "\t" ($0 ~ /#[ ]*optional/ ? "optional" : "default")
    }
  ' "$1"
}

_items_of_kind() {
  awk -F'\t' -v kind="$1" '$1 == kind { print $2 }'
}

# Prints the item_info.py rows for one kind. Quiet on stdout if brew info fails.
_brew_info_rows() {
  local kind="$1" json
  shift
  [ $# -gt 0 ] || return 0
  if [ "$kind" = "brew" ]; then
    json="$(HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 --formula "$@")" || return 1
  else
    json="$(HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 --cask "$@")" || return 1
  fi
  printf '%s' "$json" | /usr/bin/python3 "$MACSETUP_LIB_DIR/item_info.py"
}

_any_app_present() {
  local paths="$1" app old_ifs="$IFS"
  IFS=:
  for app in $paths; do
    if [ -e "${MACSETUP_APPS_DIR:-/Applications}/$app" ]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

# Prints kind<TAB>token<TAB>tier<TAB>state<TAB>desc, with state one of brew, outside, missing.
# Prints nothing and returns non-zero if any item can't be classified, because reading a failed
# lookup as "missing" would offer to reinstall what is already there.
classify_items() {
  local file="$1" items rows out sep=$'\x1f' kind token tier found installed apps desc state
  items="$(brewfile_items "$file")" || return 1

  local formulae casks
  # shellcheck disable=SC2046  # tokens contain no spaces
  formulae="$(_brew_info_rows brew $(printf '%s\n' "$items" | _items_of_kind brew))" || return 1
  # shellcheck disable=SC2046
  casks="$(_brew_info_rows cask $(printf '%s\n' "$items" | _items_of_kind cask))" || return 1
  rows="$formulae"$'\n'"$casks"

  out=""
  while IFS=$'\t' read -r kind token tier; do
    found="$(printf '%s\n' "$rows" | awk -F'\t' -v OFS="$sep" -v kind="$kind" -v token="$token" '
      $1 == kind {
        n = split($3, others, ",")
        hit = ($2 == token)
        for (i = 1; i <= n; i++) if (others[i] == token) hit = 1
        if (hit) { print "row", $4, $5, $6; exit }
      }')"
    if [ -z "$found" ]; then
      printf 'Homebrew did not report on %s %s\n' "$kind" "$token" >&2
      return 1
    fi
    IFS="$sep" read -r _ installed apps desc <<< "$found"
    if [ "$installed" = "1" ]; then
      state=brew
    elif _any_app_present "$apps"; then
      state=outside
    else
      state=missing
    fi
    out+="$kind"$'\t'"$token"$'\t'"$tier"$'\t'"$state"$'\t'"$desc"$'\n'
  done <<< "$items"
  printf '%s' "$out"
}

# gum 2.0.2, checked on a real terminal:
#   choose --no-limit --label-delimiter=<tab> shows label<tab>value lines and returns values.
#   --selected is comma-split and matches labels, so a label must never contain a comma. A label
#   that fails to match is silently left unchecked, which would read as declining that item.
#   Esc exits 1 and Ctrl-C exits 130. Enter with nothing checked exits 0 with no output.

_declined_file() {
  printf '%s/.config/macsetup/declined\n' "$HOME"
}

declined_list() {
  cat "$(_declined_file)" 2>/dev/null
  return 0
}

declined_add() {
  local file
  file="$(_declined_file)"
  declined_list | grep -qxF -- "$1" && return 0
  mkdir -p "$(dirname "$file")" && printf '%s\n' "$1" >> "$file"
}

declined_remove() {
  local file tmp
  file="$(_declined_file)"
  [ -f "$file" ] || return 0
  tmp="$(mktemp "$file.tmp.XXXXXX")" || return 1
  grep -vxF -- "$1" "$file" > "$tmp"
  mv -f "$tmp" "$file"
}

# Rows of the given state from classify_items output on stdin.
_rows_in_state() {
  awk -F'\t' -v state="$1" '$4 == state'
}

_print_installed() {
  local rows="$1"
  [ -n "$rows" ] || return 0
  printf 'Already installed:\n'
  printf '%s\n' "$rows" | awk -F'\t' '
    $4 == "brew" { print "  " $2 }
    $4 == "outside" { print "  " $2 " (outside brew)" }'
}

_picker_label() {
  # kind, token, desc. Commas are removed because of how gum reads --selected.
  local kind="app"
  [ "$1" = "brew" ] && kind="cli"
  printf '%s  %s: %s' "$kind" "$2" "${3//,/;}"
}

# Prints the chosen tokens. Returns non-zero if the owner cancelled.
_pick_with_gum() {
  local missing="$1" declined="$2" input="" selected="" kind token tier state desc label
  while IFS=$'\t' read -r kind token tier state desc; do
    label="$(_picker_label "$kind" "$token" "$desc")"
    input+="$label"$'\t'"$token"$'\n'
    if [ "$tier" = "default" ] && ! printf '%s\n' "$declined" | grep -qxF -- "$token"; then
      selected+="${selected:+,}$label"
    fi
  done < <(printf '%s\n' "$missing" | awk -F'\t' -v OFS='\t' '{ if ($5 == "") $5 = "-"; print }')

  local args=(choose --no-limit --height=20 --label-delimiter=$'\t'
    --header="Choose what to install (space toggles, enter confirms, esc cancels)")
  [ -n "$selected" ] && args+=(--selected="$selected")
  printf '%s' "$input" | gum "${args[@]}"
}

_record_declined_from_pick() {
  local missing="$1" chosen="$2" token
  while IFS=$'\t' read -r token; do
    if printf '%s\n' "$chosen" | grep -qxF -- "$token"; then
      declined_remove "$token"
    else
      declined_add "$token"
    fi
  done < <(printf '%s\n' "$missing" | awk -F'\t' '$3 == "default" { print $2 }')
}

# Prints the tokens selected by an unattended mode: all, or defaults.
_unattended_choice() {
  local missing="$1" mode="$2" declined="$3"
  printf '%s\n' "$missing" | awk -F'\t' -v mode="$2" '
    mode == "all" || $3 == "default" { print $2 }' | while IFS= read -r token; do
    printf '%s\n' "$declined" | grep -qxF -- "$token" || printf '%s\n' "$token"
  done
}

_brewfile_lines_for() {
  local file="$1" chosen="$2" token
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    grep -E "^(brew|cask) \"$token\"" "$file"
  done <<< "$chosen"
}

# Reports which chosen tokens are still not installed after a failed brew bundle.
_report_install_failure() {
  local file="$1" lines="$2" tmp rows names
  tmp="$(mktemp)" || { record_failure "Install apps"; return; }
  printf '%s\n' "$lines" > "$tmp"
  rows="$(classify_items "$tmp" 2>/dev/null)"
  rm -f "$tmp"
  names="$(printf '%s\n' "$rows" | _rows_in_state missing | cut -f2 | tr '\n' ' ')"
  record_failure "Install apps: ${names:-see the brew output above}"
}

# apps_step <brewfile> <mode>, where mode is pick, all or defaults.
apps_step() {
  local file="$1" mode="$2" rows installed missing declined chosen lines
  if ! rows="$(classify_items "$file")"; then
    record_failure "Read the app list from Homebrew"
    return 1
  fi
  installed="$(printf '%s\n' "$rows" | awk -F'\t' '$4 == "brew" || $4 == "outside"')"
  missing="$(printf '%s\n' "$rows" | _rows_in_state missing)"
  _print_installed "$installed"
  if [ -z "$missing" ]; then
    printf 'Nothing left to install.\n'
    return 0
  fi
  declined="$(declined_list)"

  if [ "$mode" = "pick" ] && ! command -v gum >/dev/null 2>&1; then
    warn "gum is not available, so the picker was skipped and only defaults were considered"
    mode="defaults"
  fi
  if [ "$mode" = "pick" ]; then
    if ! chosen="$(_pick_with_gum "$missing" "$declined")"; then
      skip_step "Apps" "picker cancelled"
      return 0
    fi
    _record_declined_from_pick "$missing" "$chosen"
  else
    chosen="$(_unattended_choice "$missing" "$mode" "$declined")"
  fi
  if [ -z "$chosen" ]; then
    printf 'Nothing selected to install.\n'
    return 0
  fi

  lines="$(_brewfile_lines_for "$file" "$chosen")"
  if printf '%s\n' "$lines" | brew bundle install --no-upgrade --file=-; then
    step "Install apps" true
    return 0
  fi
  _report_install_failure "$file" "$lines"
  return 1
}
