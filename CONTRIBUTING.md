# Contributing

Thanks for your interest in CleanMac! Bug reports, ideas, translations, documentation and code contributions are all welcome.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## How can I help?

- **Report a bug.** Use the "Bug report" template on the [Issues](https://github.com/kadirmertabatay/clean-mac/issues) page. Include your macOS version, CleanMac version and the steps to reproduce.
- **Suggest a feature.** Use the "Feature request" template to explain what you want and why.
- **Translate.** The interface is available in English and Turkish. New languages and better wording are very welcome; see [Translations](docs/development.md#translations).
- **Improve the docs.** Everything under `docs/` can be edited.
- **Write code.** Issues labeled "good first issue" are a good place to start.

> **Please don't report security vulnerabilities as public issues.** Follow the steps in [SECURITY.md](SECURITY.md) instead.

## Development setup

```bash
git clone https://github.com/kadirmertabatay/clean-mac.git
cd clean-mac
swift build
swift test
./build-app.sh && open build/CleanMac.app
```

See [docs/development.md](docs/development.md) for details (environment variables, running isolated with a demo folder, screenshots, translations), and [docs/architecture.md](docs/architecture.md) for how the code is organized.

## Branching model

CleanMac uses [git flow](https://nvie.com/posts/a-successful-git-branching-model/):

| Branch | Purpose | Created from | Merged into |
|---|---|---|---|
| `main` | Released versions only. Every commit is a tagged release (`v1.0.0`). | | |
| `develop` | Integration branch for the next release. Pull requests target this branch. | `main` | |
| `feature/<name>` | A new feature or improvement, e.g. `feature/spanish-translation` | `develop` | `develop` |
| `fix/<name>` | A bug fix for the next release | `develop` | `develop` |
| `release/<version>` | Release preparation: version bump, changelog, screenshots | `develop` | `main` and `develop` |
| `hotfix/<version>` | An urgent fix for the current release | `main` | `main` and `develop` |

Both `main` and `develop` are protected: changes arrive through pull requests with a passing CI run.

```bash
git switch develop && git pull
git switch -c feature/short-description
# …commit…
git push -u origin feature/short-description   # then open a pull request against develop
```

## Pull request process

1. Before a large change, open an issue so we can agree on the approach first.
2. Create a branch from `develop` (see [Branching model](#branching-model)) and open your pull request against `develop`.
3. Make the change in small, focused commits. Write commit messages in English, in the imperative mood: `Add …`, `Fix …`.
4. Add or update tests for anything that changes behavior. `swift test` must pass.
5. If you add or change user-facing strings, run `./scripts/update-strings.sh` and add the Turkish translation (or mention in the PR that it's missing so someone can help).
6. If you changed the UI, add a screenshot to the PR description. Regenerate `docs/images` with `./scripts/screenshots.sh` if needed.
7. Add user-facing changes to the "Unreleased" section of `CHANGELOG.md`.
8. Fill in the checklist in the PR template.

## Rules

CleanMac deletes files, so these rules are not negotiable:

- **A single removal path.** Any code that removes files must go through `AppState.remove(_:permanently:)`. Don't call `FileManager.removeItem` / `trashItem` directly.
- **Trash by default.** A new feature may not make permanent deletion the default.
- **Confirmation.** Every deletion triggered from the UI must go through a confirmation that shows how many items and how much space are affected.
- **No network.** Don't add network requests, analytics or third-party dependencies to the app. If you think one is needed, let's discuss it in an issue first.
- **Tests never touch the user's files.** Tests must only work with files they create in temporary folders. Tests that talk to the real system must be enabled with an environment variable (`CLEANMAC_…_TEST=1`).

## Code style

- Follow the Swift API Design Guidelines and match the existing formatting (4-space indentation).
- Identifiers, comments and source strings are in English; user-facing strings go through `L("…")` or a SwiftUI string literal.
- Interface text addresses the user directly, is short and avoids jargon. Any text about deletion must state the outcome clearly ("moved to the Trash", "can't be undone").
- Don't do heavy work on the main actor. Use `Task.detached` and support cancellation.

## License

Your contributions are released under the same [MIT License](LICENSE) as the project.
