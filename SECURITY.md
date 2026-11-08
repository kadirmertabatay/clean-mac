# Security Policy

CleanMac deletes files, so we take security bugs seriously. The most important bugs in this area are the ones that lead to something being deleted that the user didn't approve or had protected.

## Supported versions

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Older releases | ❌ Please update to the latest release |

## Reporting a vulnerability

**Please don't report security vulnerabilities as public issues.**

Use GitHub's private reporting instead: **Security › Report a vulnerability** on the repository page ([direct link](https://github.com/kadirmertabatay/clean-mac/security/advisories/new)).

It helps a lot if your report includes:

- the affected version and macOS version,
- steps to reproduce (ideally in a temporary folder with fake files),
- the expected and actual behavior,
- the possible impact (e.g. "an excluded folder ends up in the Smart Cleanup plan").

## Process

- You'll get a reply within 7 days.
- If the issue is confirmed, the fix is prioritized and shipped in a new release.
- If you like, you'll be credited in the release notes.

## Scope

These count as security issues:

- something being deleted without a confirmation dialog,
- an excluded path or a path protected by Smart Cleanup being deleted or ending up in a plan,
- the last copy of a file being deleted from a duplicate group,
- a way around the last-moment checks (changed or moved files),
- outside input being injected into commands run with administrator privileges,
- anything that makes the app send data over the network.

These are usually out of scope:

- macOS warnings about ad-hoc signed, non-notarized releases (a known limitation),
- permanent deletions the user explicitly chose,
- issues in macOS's own tools (`tmutil`, `diskutil`) or in `brew` and `docker`.
