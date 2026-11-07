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
