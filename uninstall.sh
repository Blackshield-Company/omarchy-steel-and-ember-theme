#!/usr/bin/env bash
# Glyphsmith theme uninstaller for Omarchy. It reverses install.sh using its manifest. No sudo.
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
MANIFEST="$HOME/.local/state/glyphsmith/manifests/$THEME_NAME.manifest"
[[ -f $MANIFEST ]] || die "no manifest at $MANIFEST: '$THEME_NAME' wasn't installed by install.sh"

DEST="" BACKUP="" PREV="" DIRS=() FILES=() SUMS=()
while IFS=$'\t' read -r key a b; do
  case $key in
    dest) DEST=$a ;;
    backup) BACKUP=$a ;;
    previous_theme) PREV=$a ;;
    dir) DIRS+=("$a") ;;
    file) SUMS+=("$a"); FILES+=("$b") ;;
  esac
done < "$MANIFEST"
[[ $DEST == "$HOME/.config/omarchy/themes/$THEME_NAME" ]] || die "manifest dest '$DEST' is unexpected; refusing"
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
    warn "'$THEME_NAME' is active but omarchy-theme-set isn't available; switch themes by hand"
  fi
fi

# 2. Remove only the files we installed, and keep any the user edited.
kept=0
for i in "${!FILES[@]}"; do
  f=${FILES[$i]}
  case $f in "$DEST"/*) ;; *) warn "skipping out-of-tree path $f"; continue ;; esac
  [[ -f $f && ! -L $f ]] || continue
  if [[ $(sha256sum < "$f" | cut -d' ' -f1) == "${SUMS[$i]}" ]]; then
    run rm -f -- "$f"
  else
    warn "kept modified file: $f"; kept=1
  fi
done

# 3. Remove the theme directories we created, deepest first, only if they're empty.
mapfile -t SORTED_DIRS < <(printf '%s\n' "${DIRS[@]}" | awk '{print length($0)"\t"$0}' | sort -rn | cut -f2-)
for d in "${SORTED_DIRS[@]}"; do
  case $d in "$DEST"|"$DEST"/*) ;; *) continue ;; esac
  if [[ -d $d ]]; then
    if (( DRY_RUN )); then printf '[dry-run] rmdir %s (if empty)\n' "$d"; else rmdir -- "$d" 2>/dev/null || warn "not empty, left: $d"; fi
  fi
done

# 4. Restore the backup.
if [[ -n $BACKUP ]]; then
  if [[ -e $DEST ]]; then
    warn "$DEST still exists (it has modified or extra files), so the backup stays at $BACKUP"
  elif [[ -e $BACKUP ]]; then
    log "Restoring backup $BACKUP -> $DEST"
    run mv -- "$BACKUP" "$DEST"
  else
    warn "backup $BACKUP is missing; nothing to restore"
  fi
fi

# 5. Drop the manifest and the state dirs the installer created (if they're empty).
if (( kept )) || { [[ -n $BACKUP && -e $BACKUP ]] && (( ! DRY_RUN )); }; then
  warn "manifest kept at $MANIFEST because something was left behind"
else
  run rm -f -- "$MANIFEST"
  for d in "${SORTED_DIRS[@]}"; do
    case $d in "$DEST"|"$DEST"/*) continue ;; esac
    [[ -d $d ]] || (( DRY_RUN )) || continue
    if (( DRY_RUN )); then printf '[dry-run] rmdir %s (if empty)\n' "$d"; else rmdir -- "$d" 2>/dev/null || true; fi
  done
fi
log "Done."
