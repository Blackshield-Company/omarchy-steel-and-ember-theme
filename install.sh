#!/usr/bin/env bash
# Steel & Ember (Glyphsmith) theme installer for Omarchy (Hyprland). No sudo, user files only.
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
# Everything install.sh writes stays inside the theme folder, including its manifest.
# It never backs up or replaces a folder it didn't install, so it needs no state outside $DEST.
MANIFEST="$DEST/.glyphsmith-install.manifest"
STAMP=$(date +%Y%m%d-%H%M%S)

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

# True when no folder from HOME down to $1 (and not $1 itself either) is a symlink. HOME may be one.
# A linked ~/.config, omarchy or themes folder would carry the install, and later uninstall's
# removals, somewhere outside HOME, so each component is checked rather than the resolved path.
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
no_link_below_home "$DEST" ||
  die "a folder on the way from $HOME to $DEST is a symlink; install.sh only writes to real folders under HOME. Nothing was changed."

# Files to install: everything except packaging and VCS cruft (sorted, relative).
mapfile -t FILES < <(cd "$SCRIPT_DIR" && find . \
  \( -name .git -o -name releases -o -name .github \) -prune -o \
  -type f ! -name install.sh ! -name uninstall.sh ! -name build-release.sh \
  ! -name '*.manifest' ! -name '.DS_Store' -print | sed 's|^\./||' | LC_ALL=C sort)
(( ${#FILES[@]} > 0 )) || die "no theme files found in $SCRIPT_DIR"
[[ -f $SCRIPT_DIR/colors.toml || -f $SCRIPT_DIR/alacritty.toml ]] || warn "no colors.toml: Omarchy 4 renders nothing without it"

valid_name() { (LC_ALL=C; [[ $1 =~ ^[a-z0-9_][a-z0-9._+-]*$ ]]); }
ACTIVE=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
PREV_THEME=$ACTIVE REACTIVATE=0

# Reinstall
if [[ -f $MANIFEST ]]; then
  if (( FORCE )); then
    # Keep the theme recorded before the first install, so uninstall can still go back to it.
    PREV_THEME=$(awk -F'\t' '$1 == "previous_theme" { print $2; exit }' "$MANIFEST")
    [[ -n $PREV_THEME ]] || PREV_THEME=$ACTIVE
    if [[ $ACTIVE == "$THEME_NAME" ]]; then
      # uninstall.sh switches away first, as a plain uninstall does, so the active theme is never a
      # half-removed folder. Without omarchy-theme-set it can't, so stop before anything is touched.
      if ! command -v omarchy-theme-set >/dev/null 2>&1; then
        if (( DRY_RUN )); then
          warn "'$THEME_NAME' is active and omarchy-theme-set isn't available; a real run would stop here"
        else
          die "'$THEME_NAME' is active but omarchy-theme-set isn't available to switch away while it is reinstalled; nothing changed (switch themes by hand, then install again)"
        fi
      fi
      REACTIVATE=1
    fi
    log "Existing Glyphsmith install of '$THEME_NAME' found: uninstalling it first (--force)"
    ua=(); (( DRY_RUN )) && ua+=(--dry-run)
    THEME_NAME=$THEME_NAME bash "$SCRIPT_DIR/uninstall.sh" "${ua[@]}" || die "uninstall failed; nothing changed"
    if (( DRY_RUN )); then
      log "(dry-run: the steps below assume that uninstall ran)"
    elif [[ -e $DEST || -L $DEST ]]; then
      (( REACTIVATE )) && warn "'$THEME_NAME' was switched away from; switch back with: omarchy-theme-set $THEME_NAME"
      die "$DEST still holds edited or extra files after uninstall (see the warnings above). Move them out, then install again."
    fi
  else
    die "'$THEME_NAME' is already installed by this script ($MANIFEST). Run uninstall.sh first, or pass --force."
  fi
elif [[ -e $DEST || -L $DEST ]]; then
  die "$DEST already exists and wasn't installed by this script. Move it somewhere else first; nothing was changed."
fi
# Never record this theme (or anything that isn't a theme name) as the one to go back to.
if [[ $PREV_THEME == "$THEME_NAME" ]] || ! valid_name "$PREV_THEME"; then PREV_THEME=""; fi

# If the copy below fails after a forced reinstall switched away, say how to get back.
on_exit() {
  local rc=$?
  (( rc == 0 || ! REACTIVATE || DRY_RUN )) ||
    warn "'$THEME_NAME' was switched away from for the reinstall and is not active again. Fix the error above, run install.sh --force again, then omarchy-theme-set $THEME_NAME"
}
trap on_exit EXIT

# Track the folders we create inside the theme folder so uninstall can remove exactly those.
CREATED_DIRS=()
# The folders above it (~/.config, omarchy, themes) that this run creates are recorded too, relative
# to HOME and outermost first, so uninstall can remove exactly those again once they are empty.
# A folder that was already there is never recorded, so it is never removed.
CREATED_PARENTS=()
ensure_parents() {
  local h=${HOME%/} p=$THEMES_DIR missing=()
  while [[ $p == "$h"/* && ! -d $p ]]; do missing=("${p#"$h"/}" "${missing[@]}"); p=$(dirname -- "$p"); done
  for p in "${missing[@]}"; do run mkdir -- "$h/$p"; CREATED_PARENTS+=("$p"); done
}
ensure_dir() {
  local d=$1 missing=() p
  p=$d
  while [[ ($p == "$DEST" || $p == "$DEST"/*) && ! -d $p ]]; do missing=("$p" "${missing[@]}"); p=$(dirname -- "$p"); done
  for p in "${missing[@]}"; do
    [[ " ${CREATED_DIRS[*]-} " == *" $p "* ]] && continue   # dry-run: already "created"
    run mkdir "$p"; CREATED_DIRS+=("$p")
  done
}

log "Theme:   $THEME_NAME"
log "Source:  $SCRIPT_DIR"
log "Target:  $DEST"
(( DRY_RUN )) && log "DRY RUN: nothing will be changed"

ensure_parents
ensure_dir "$DEST"
for f in "${FILES[@]}"; do ensure_dir "$(dirname -- "$DEST/$f")"; done

write_manifest() {
  printf '# glyphsmith install manifest v1\n'
  printf 'name\t%s\n' "$THEME_NAME"
  printf 'dest\t%s\n' "$DEST"
  printf 'installed_at\t%s\n' "$STAMP"
  printf 'previous_theme\t%s\n' "$PREV_THEME"
  printf 'applied\t%s\n' "$APPLY"
  local d f
  printf 'parents\t%s\n' "${#CREATED_PARENTS[@]}"
  for d in "${CREATED_PARENTS[@]+"${CREATED_PARENTS[@]}"}"; do printf 'parent\t%s\n' "$d"; done
  for d in "${CREATED_DIRS[@]}"; do printf 'dir\t%s\n' "$d"; done
  for f in "${FILES[@]}"; do
    printf 'file\t%s\t%s\n' "$(sha256sum < "$SCRIPT_DIR/$f" | cut -d' ' -f1)" "$DEST/$f"
  done
}
# The manifest goes in before the files, so uninstall.sh can clean up even if a copy fails halfway.
if (( DRY_RUN )); then
  log "Would write the manifest $MANIFEST:"; write_manifest | sed 's/^/    /'
else
  write_manifest > "$MANIFEST.tmp" && mv -- "$MANIFEST.tmp" "$MANIFEST"
  log "Manifest: $MANIFEST"
fi

for f in "${FILES[@]}"; do
  run cp -p -- "$SCRIPT_DIR/$f" "$DEST/$f"
done
log "Copied ${#FILES[@]} file(s)"

if (( REACTIVATE )); then
  log "Switching back to the reinstalled '$THEME_NAME'"
  run omarchy-theme-set "$THEME_NAME"; REACTIVATE=0
elif (( APPLY )); then
  log "Applying with: omarchy-theme-set $THEME_NAME"
  run omarchy-theme-set "$THEME_NAME"
else
  log "Done. To switch to it: omarchy-theme-set $THEME_NAME   (or re-run with --apply)"
fi
