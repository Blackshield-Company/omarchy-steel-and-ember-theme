#!/usr/bin/env bash
# Regression test: uninstall.sh step 5 must not follow a symlink swapped in on the way to a
# recorded parent folder after its checks ran (TOCTOU). Also checks the normal case still
# leaves HOME exactly as it was. Usage: tests/uninstall-parents-race.sh  (from the repo root)
set -euo pipefail
repo=$(cd -P "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# 1. Clean install + uninstall into an empty HOME leaves HOME empty.
mkdir "$tmp/h1"
HOME=$tmp/h1 THEME_NAME=steel-and-ember PATH=/usr/bin:/bin bash "$repo/install.sh" >/dev/null 2>&1 || true
[[ -e $tmp/h1/.config/omarchy/themes/steel-and-ember ]] || fail "install did not create theme dir"
for dev in tests .github; do
  [[ ! -e $tmp/h1/.config/omarchy/themes/steel-and-ember/$dev ]] || fail "dev-only $dev/ was installed"
done
HOME=$tmp/h1 THEME_NAME=steel-and-ember PATH=/usr/bin:/bin bash "$repo/uninstall.sh" --no-switch </dev/null >/dev/null 2>&1 || true
[[ -z $(ls -A "$tmp/h1") ]] || fail "HOME not empty after uninstall: $(cd "$tmp/h1" && find .)"

# 2. Swap .config/omarchy for a symlink to an outside tree between the checks and the rmdir.
mkdir -p "$tmp/h2" "$tmp/outside/themes"
HOME=$tmp/h2 THEME_NAME=steel-and-ember PATH=/usr/bin:/bin bash "$repo/install.sh" >/dev/null 2>&1 || true
[[ -e $tmp/h2/.config/omarchy/themes/steel-and-ember ]] || fail "install (2) did not create theme dir"
export RACE_FROM=$tmp/h2/.config/omarchy RACE_TO=$tmp/outside RACE_FLAG=$tmp/raced
rmdir() {  # fires once, just before the rmdir of the deepest parent (.config/omarchy/themes)
  if [[ ! -e $RACE_FLAG && ${!#} == *themes ]]; then
    : >"$RACE_FLAG"; mv "$RACE_FROM" "$RACE_FROM.moved"; ln -s "$RACE_TO" "$RACE_FROM"
  fi
  command rmdir "$@"
}
export -f rmdir
HOME=$tmp/h2 THEME_NAME=steel-and-ember PATH=/usr/bin:/bin bash "$repo/uninstall.sh" --no-switch </dev/null >/dev/null 2>&1 || true
unset -f rmdir
[[ -e $RACE_FLAG ]] || fail "race hook never fired"
[[ -d $tmp/outside/themes ]] || fail "outside folder was removed through a swapped-in symlink"
echo "PASS"
