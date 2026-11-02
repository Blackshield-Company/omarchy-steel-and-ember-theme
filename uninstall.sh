#!/usr/bin/env bash
# Steel & Ember (Glyphsmith) theme uninstaller for Omarchy. It reverses install.sh using its manifest. No sudo.
# Usage: ./uninstall.sh [--dry-run] [--no-switch] [--fallback <theme>] [-h]
#   THEME_NAME=<name> overrides the name taken from this folder.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
DRY_RUN=0 SWITCH=1 FALLBACK=${GLYPHSMITH_FALLBACK_THEME:-tokyo-night}

usage() { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; }
while (( $# )); do
  case $1 in
    --dry-run|-n) DRY_RUN=1 ;;
    --no-switch) SWITCH=0 ;;
    --fallback) shift; FALLBACK=${1:?--fallback needs a theme name} ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log()  { printf '[uninstall] %s\n' "$*"; }
warn() { printf '[uninstall] WARNING: %s\n' "$*" >&2; }
die()  { printf '[uninstall] ERROR: %s\n' "$*" >&2; exit 1; }
run()  { if (( DRY_RUN )); then printf '[dry-run] %s\n' "$*"; else "$@"; fi; }

raw_name=${THEME_NAME:-$(basename -- "$SCRIPT_DIR")}
THEME_NAME=$(printf '%s' "$raw_name" | tr '[:upper:] ' '[:lower:]-' | sed -E 's/^omarchy-//; s/-theme$//')
if ! (LC_ALL=C; [[ $THEME_NAME =~ ^[a-z0-9_][a-z0-9._+-]*$ ]]); then
  die "'$raw_name' is not a usable Omarchy theme name"
fi
: "${HOME:?HOME must be set}"
THEME_DIR="$HOME/.config/omarchy/themes/$THEME_NAME"
MANIFEST="$THEME_DIR/.glyphsmith-install.manifest"
# True when no folder from HOME down to $1 (and not $1 itself either) is a symlink. HOME may be one.
# The resolved theme folder is not trusted as its own boundary: if ~/.config, omarchy or themes is
# a link, the files behind it live outside HOME, so stop before anything is read or removed.
no_link_below_home() {
  local h=${HOME%/} p c parts
  [[ $1 == "$h"/* ]] || return 1
  p=$h
  IFS=/ read -r -a parts <<<"${1#"$h"/}"
  for c in "${parts[@]}"; do
    [[ $c != .. ]] || return 1
    p=$p/$c
    [[ ! -L $p ]] || return 1
  done
}
[[ -L $THEME_DIR ]] && die "$THEME_DIR is a symlink, not the folder install.sh created; refusing"
no_link_below_home "$THEME_DIR" ||
  die "a folder on the way from $HOME to $THEME_DIR is a symlink; refusing (nothing removed)"
[[ -f $MANIFEST && ! -L $MANIFEST ]] || die "no manifest at $MANIFEST: '$THEME_NAME' wasn't installed by install.sh"

DEST="" PREV="" DIRS=() FILES=() SUMS=() PARENTS=() NPARENTS=""
while IFS=$'\t' read -r key a b; do
  case $key in
    dest) DEST=$a ;;
    parents) NPARENTS=$a ;;
    parent) PARENTS+=("$a") ;;
    previous_theme) PREV=$a ;;
    dir) DIRS+=("$a") ;;
    file) SUMS+=("$a"); FILES+=("$b") ;;
  esac
done < "$MANIFEST"
[[ $DEST == "$THEME_DIR" ]] || die "manifest dest '$DEST' is unexpected; refusing"

# Every path must be a plain path inside the theme folder: no "..", "." or empty components.
# A manifest naming anything else has been altered, so stop before anything is touched.
in_dest() {
  local rel c parts
  [[ $1 == "$DEST"/* ]] || return 1
  rel=${1#"$DEST"/}
  [[ -n $rel && $rel != */ ]] || return 1
  IFS=/ read -r -a parts <<<"$rel"
  for c in "${parts[@]}"; do [[ -n $c && $c != . && $c != .. ]] || return 1; done
}
for f in "${FILES[@]}"; do
  in_dest "$f" || die "manifest names '$f', which is not a plain path inside $DEST; refusing (nothing removed)"
done
SAFE_DIRS=()
for d in "${DIRS[@]}"; do
  if [[ $d == "$DEST" ]] || in_dest "$d"; then SAFE_DIRS+=("$d")
  elif [[ $DEST == "$d"/* ]]; then continue   # a folder above the theme folder: never removed
  else die "manifest names the folder '$d', which is not inside $DEST; refusing (nothing removed)"
  fi
done
(LC_ALL=C; [[ $PREV =~ ^[a-z0-9_][a-z0-9._+-]*$ ]]) || PREV=""
# Folders above the theme folder that install.sh created, relative to HOME. Each must be one of the
# folders on the way down to the themes folder (.config, .config/omarchy, .config/omarchy/themes),
# so an absolute path, "..", "." or an empty component never matches. If any entry or the count
# is off, the record was altered and none of them is removed; that is only noted, not an error.
PARENTS_NOTE="" CHAIN=/.config/omarchy/themes/
if [[ -z $NPARENTS ]]; then
  PARENTS_NOTE="the manifest has no record of folders install.sh created above $DEST (an older install), so none of them is removed"
elif [[ $NPARENTS != "${#PARENTS[@]}" ]]; then
  PARENTS_NOTE="the record of folders install.sh created above $DEST doesn't add up, so none of them is removed"
else
  for d in "${PARENTS[@]+"${PARENTS[@]}"}"; do
    case $CHAIN in
      "/$d/"*) ;;
      *) PARENTS_NOTE="the record of folders install.sh created above $DEST names '$d', which isn't one of them, so none of them is removed" ;;
    esac
  done
fi
[[ -z $PARENTS_NOTE ]] || PARENTS=()
DEST_REAL=$(realpath -e -- "$DEST")
# True when the folder holding $1 is a real folder inside the theme folder, with no symlink on the way.
parent_is_real() {
  local p; p=$(dirname -- "$1")
  [[ -d $p ]] && [[ $(realpath -e -- "$p") == "$DEST_REAL${p#"$DEST"}" ]]
}
(( DRY_RUN )) && log "DRY RUN: nothing will be changed"

# 1. Switch away if this theme is the active one.
ACTIVE=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
if [[ $ACTIVE == "$THEME_NAME" ]]; then
  target=$PREV
  [[ -z $target || $target == "$THEME_NAME" ]] && target=$FALLBACK
  if (( ! SWITCH )); then
    warn "'$THEME_NAME' is active; not switching (--no-switch)"
  elif command -v omarchy-theme-set >/dev/null 2>&1; then
    log "'$THEME_NAME' is active: switching to '$target' first"
    run omarchy-theme-set "$target" || die "omarchy-theme-set $target failed; nothing removed"
  else
    if (( DRY_RUN )); then
      warn "'$THEME_NAME' is active and omarchy-theme-set isn't available; a real run would stop here"
    else
      die "'$THEME_NAME' is active but omarchy-theme-set isn't available; nothing removed (switch themes by hand, or pass --no-switch)"
    fi
  fi
fi

# 2. Remove only the files we installed, and keep any the user edited or replaced.
kept=0
for i in "${!FILES[@]}"; do
  f=${FILES[$i]}
  if ! parent_is_real "$f"; then
    p=$(dirname -- "$f")
    if [[ -e $p || -L $p ]]; then warn "kept $f: a folder above it is now a symlink or not a folder, so it isn't followed"; kept=1; fi
    continue
  fi
  if [[ -L $f ]]; then
    warn "kept $f: it is now a symlink, not the file install.sh copied"; kept=1
  elif [[ -d $f ]]; then
    warn "kept $f: it is now a folder, not the file install.sh copied"; kept=1
  elif [[ -f $f ]]; then
    if [[ $(sha256sum < "$f" | cut -d' ' -f1) == "${SUMS[$i]}" ]]; then
      run rm -f -- "$f"
    else
      warn "kept modified file: $f"; kept=1
    fi
  elif [[ -e $f ]]; then
    warn "kept $f: it is not a regular file"; kept=1
  fi
done

# 3. Drop the manifest (it lives in the theme folder), unless something stays behind.
if (( kept )); then
  warn "manifest kept at $MANIFEST because edited or replaced files were left behind"
else
  run rm -f -- "$MANIFEST"
fi

# 4. Remove the folders install.sh created inside the theme folder, deepest first, only if they're empty.
#    "dir" entries above the theme folder are never removed; step 5 handles those folders.
mapfile -t SORTED_DIRS < <(printf '%s\n' "${SAFE_DIRS[@]+"${SAFE_DIRS[@]}"}" | awk 'NF {print length($0)"\t"$0}' | sort -rn | cut -f2-)
for d in "${SORTED_DIRS[@]+"${SORTED_DIRS[@]}"}"; do
  [[ -d $d && ! -L $d ]] || continue
  if [[ $d != "$DEST" ]] && ! parent_is_real "$d"; then warn "left $d: a folder above it is a symlink"; continue; fi
  if (( DRY_RUN )); then
    printf '[dry-run] rmdir %s (if empty)\n' "$d"
  elif ! rmdir -- "$d" 2>/dev/null; then
    warn "not empty, left: $d"
  fi
done

# 5. Remove the folders above it that install.sh created (and recorded), deepest first, only while
#    each is still a real, empty folder with no symlink on the way from HOME. Never anything else.
[[ -z $PARENTS_NOTE ]] || log "note: $PARENTS_NOTE"
mapfile -t SORTED_PARENTS < <(printf '%s\n' "${PARENTS[@]+"${PARENTS[@]}"}" | awk 'NF {print length($0)"\t"$0}' | sort -rn | cut -f2-)
for d in "${SORTED_PARENTS[@]+"${SORTED_PARENTS[@]}"}"; do
  d=${HOME%/}/$d
  [[ -e $d || -L $d ]] || continue
  if [[ ! -d $d || -L $d ]] || ! no_link_below_home "$d"; then
    log "note: left $d: it is no longer a real folder, or a folder on the way to it is a symlink"; continue
  fi
  if (( DRY_RUN )); then
    printf '[dry-run] rmdir %s (if empty)\n' "$d"
  else
    rmdir -- "$d" 2>/dev/null || true   # still holds something (another theme, your files): it stays
  fi
done
log "Done."
