# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.1] - 2026-11-09

### Fixed

- Build failure with Swift 6.0/6.1 (Xcode 16), which broke the 1.0.0 CI and release builds.

## [1.0.0] - 2026-11-09

First public release.

### Added

- **Smart Assistant:** one-click full analysis (junk → folder scan → duplicates → storage → apps) with prioritized suggestions.
- **Smart Cleanup:** a Safe / Balanced / Thorough cleanup plan built around the areas, browsers, apps and developer folders you choose to protect. Protections also apply to Auto Cleanup and quick clean.
- **Folder Explorer:** list, donut chart and squarified treemap views.
- **Scan scope:** Home Folder, Entire Mac (virtual and external paths excluded) or any folder; a job-queue scanner that uses every core.
- **Large Files:** filters, Quick Look, and archiving to an external disk with SHA-256 verification.
- **Duplicate Files:** size → partial digest → SHA-256; hard link and iCloud aware; last-copy protection.
- **Similar Photos:** on-device grouping with Apple Vision feature prints.
- **Junk Files:** caches, logs, Xcode data, package manager caches, installers, old downloads, iPhone backups, the Trash, project dependencies.
- **Storage Breakdown:** APFS volumes, purgeable space, deleting local Time Machine snapshots.
- **What Grew?:** scan summaries and comparison with earlier scans.
- **Apps:** uninstall with Library leftovers, last-opened dates.
- **Developer:** Homebrew cleanup, unused simulators, dependencies of untouched projects.
- **Docker:** analysis of images, containers, volumes and build cache, selective deletion, virtual disk shrinking.
- **Auto Cleanup:** scheduled rules with preview and approval.
- **Menu bar:** free space indicator and low-space notifications.
- **Cleanup History** with restore, and **Exclusions**.
- Welcome screen and Settings window.
- English interface with a Turkish translation, selectable in Settings.
- Documentation (`docs/`), a screenshot generation script and universal (arm64 + x86_64) release packaging.

[Unreleased]: https://github.com/kadirmertabatay/clean-mac/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/kadirmertabatay/clean-mac/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/kadirmertabatay/clean-mac/releases/tag/v1.0.0
