# Changelog

All notable changes to Steel & Ember are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.2] - 2026-11-02
### Fixed
- `uninstall.sh` no longer has a race when it removes the empty parent folders `install.sh` created. It now enters each folder and checks its real path before removing it, so a folder swapped for a symlink mid-uninstall can't send the removal outside your home folder.

### Changed
- `install.sh` no longer copies the repo's dev-only `tests/` folder into the installed theme.

## [0.1.1] - 2026-11-02
### Fixed
- `uninstall.sh` now removes only the files `install.sh` installed, inside the theme folder. It refuses symlinked or altered paths, never deletes a folder it didn't create, and does nothing when the theme isn't installed.
- `install.sh` keeps its manifest inside the theme folder and refuses to overwrite a same-name folder it didn't install, instead of moving it aside.

## [0.1.0] - 2026-10-16
### Added
- First release: colors.toml palette (16 ANSI colours, ember border gradient), 1 background (`1-forged-steel.png`, 2560x1440), btop theme, preview and screenshots.

<!-- Sections to use: Added, Changed, Deprecated, Removed, Fixed, Security -->

[Unreleased]: https://github.com/Blackshield-Company/omarchy-steel-and-ember-theme/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/Blackshield-Company/omarchy-steel-and-ember-theme/releases/tag/v0.1.2
[0.1.1]: https://github.com/Blackshield-Company/omarchy-steel-and-ember-theme/releases/tag/v0.1.1
[0.1.0]: https://github.com/Blackshield-Company/omarchy-steel-and-ember-theme/releases/tag/v0.1.0
