#!/usr/bin/env bash
# Glyphsmith theme installer for Omarchy (Hyprland). No sudo, user files only.
# Usage: ./install.sh [--dry-run] [--apply] [--force] [-h]
#   THEME_NAME=<name> overrides the name taken from this folder.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
DRY_RUN=0 APPLY=0 FORCE=0

usage() { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; }
for arg in "$@"; do
  case $arg in
    --dry-run|-n) DRY_RUN=1 ;;
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install] WARNING: %s\n' "$*" >&2; }
die()  { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }
run()  { if (( DRY_RUN )); then printf '[dry-run] %s\n' "$*"; else "$@"; fi; }

# Theme name: $THEME_NAME, otherwise the folder name, normalised the same way omarchy-theme-install does it.
raw_name=${THEME_NAME:-$(basename -- "$SCRIPT_DIR")}
THEME_NAME=$(printf '%s' "$raw_name" | tr '[:upper:] ' '[:lower:]-' | sed -E 's/^omarchy-//; s/-theme$//')
if ! (LC_ALL=C; [[ $THEME_NAME =~ ^[a-z0-9_][a-z0-9._+-]*$ ]]); then
  die "'$raw_name' is not a usable Omarchy theme name"
fi

: "${HOME:?HOME must be set}"
THEMES_DIR="$HOME/.config/omarchy/themes"
DEST="$THEMES_DIR/$THEME_NAME"
STATE_DIR="$HOME/.local/state/glyphsmith"
MANIFEST="$STATE_DIR/manifests/$THEME_NAME.manifest"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$STATE_DIR/backups/$THEME_NAME-$STAMP"

# Omarchy check
is_omarchy() {
  command -v omarchy-theme-set >/dev/null 2>&1 && return 0
  [[ -n ${OMARCHY_PATH:-} && -d $OMARCHY_PATH ]] && return 0
  [[ -d /usr/share/omarchy || -d $HOME/.local/share/omarchy ]]
}
if ! is_omarchy; then
  warn "This doesn't look like Omarchy (no omarchy-theme-set on PATH and no Omarchy install dir)."
  warn "The files will still be copied to $DEST, but nothing will apply them."
  if (( APPLY )); then warn "--apply ignored: omarchy-theme-set not found."; APPLY=0; fi
fi

[[ $SCRIPT_DIR == "$DEST" ]] && die "Run install.sh from the theme's source folder, not from $DEST"

# Files to install: everything except packaging and VCS cruft (sorted, relative).
mapfile -t FILES < <(cd "$SCRIPT_DIR" && find . \
  \( -name .git -o -name releases -o -name .github \) -prune -o \
  -type f ! -name install.sh ! -name uninstall.sh ! -name build-release.sh \
  ! -name '*.manifest' ! -name '.DS_Store' -print | sed 's|^\./||' | LC_ALL=C sort)
(( ${#FILES[@]} > 0 )) || die "no theme files found in $SCRIPT_DIR"
[[ -f $SCRIPT_DIR/colors.toml || -f $SCRIPT_DIR/alacritty.toml ]] || warn "no colors.toml: Omarchy 4 renders nothing without it"

# Reinstall
if [[ -f $MANIFEST ]]; then
  if (( FORCE )); then
    log "Existing Glyphsmith install of '$THEME_NAME' found: uninstalling it first (--force)"
    ua=(--no-switch); (( DRY_RUN )) && ua+=(--dry-run)
    THEME_NAME=$THEME_NAME bash "$SCRIPT_DIR/uninstall.sh" "${ua[@]}"
    (( DRY_RUN )) && log "(dry-run: the steps below assume that uninstall ran)"
  else
    die "'$THEME_NAME' is already installed by this script ($MANIFEST). Run uninstall.sh first, or pass --force."
  fi
fi

# Track the directories we create so uninstall can remove exactly those.
CREATED_DIRS=()
ensure_dir() {
  local d=$1 missing=() p
  p=$d
  while [[ ! -d $p ]]; do missing=("$p" "${missing[@]}"); p=$(dirname -- "$p"); done
  for p in "${missing[@]}"; do
    [[ " ${CREATED_DIRS[*]-} " == *" $p "* ]] && continue   # dry-run: already "created"
    run mkdir "$p"; CREATED_DIRS+=("$p")
  done
}

log "Theme:   $THEME_NAME"
log "Source:  $SCRIPT_DIR"
log "Target:  $DEST"
(( DRY_RUN )) && log "DRY RUN: nothing will be changed"

ensure_dir "$STATE_DIR/manifests"
BACKUP_USED=""
if [[ -e $DEST || -L $DEST ]]; then
  ensure_dir "$STATE_DIR/backups"
  log "Backing up the existing $DEST to $BACKUP"
  run mv -- "$DEST" "$BACKUP"
  BACKUP_USED=$BACKUP
fi
ensure_dir "$DEST"

for f in "${FILES[@]}"; do
  ensure_dir "$(dirname -- "$DEST/$f")"
  run cp -p -- "$SCRIPT_DIR/$f" "$DEST/$f"
done
log "Copied ${#FILES[@]} file(s)"

PREV_THEME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)

write_manifest() {
  printf '# glyphsmith install manifest v1\n'
  printf 'name\t%s\n' "$THEME_NAME"
  printf 'dest\t%s\n' "$DEST"
  printf 'installed_at\t%s\n' "$STAMP"
  printf 'backup\t%s\n' "$BACKUP_USED"
  printf 'previous_theme\t%s\n' "$PREV_THEME"
  printf 'applied\t%s\n' "$APPLY"
  local d f
  for d in "${CREATED_DIRS[@]}"; do printf 'dir\t%s\n' "$d"; done
  for f in "${FILES[@]}"; do
    printf 'file\t%s\t%s\n' "$(sha256sum < "$SCRIPT_DIR/$f" | cut -d' ' -f1)" "$DEST/$f"
  done
}
if (( DRY_RUN )); then
  log "Would write the manifest $MANIFEST:"; write_manifest | sed 's/^/    /'
else
  write_manifest > "$MANIFEST.tmp" && mv -- "$MANIFEST.tmp" "$MANIFEST"
  log "Manifest: $MANIFEST"
fi

if (( APPLY )); then
  log "Applying with: omarchy-theme-set $THEME_NAME"
  run omarchy-theme-set "$THEME_NAME"
else
  log "Done. To switch to it: omarchy-theme-set $THEME_NAME   (or re-run with --apply)"
fi
