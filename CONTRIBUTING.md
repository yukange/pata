# How to contribute

Fork Pata, make a focused change, and open a pull request against `yukange/pata:main`.
Use the issue templates for bug reports and feature requests, and the pull request template to explain your changes.

## Prerequisites

For local macOS development, install:

- macOS 14.0 (Sonoma) or later.
- Xcode 16 / Swift 6 or Xcode Command Line Tools.

### Set up the project

After creating your fork, replace `YOUR_GITHUB_ID` with its owner:

```bash
git clone https://github.com/YOUR_GITHUB_ID/pata.git
cd pata
```

Build the native macOS application:

```bash
./scripts/build_swift_app.sh
```

Run the unit tests:

```bash
swift test
```

Use a temporary Vault for development and verification.

## Fork

Create a fork of [yukange/pata](https://github.com/yukange/pata) on GitHub. Your clone uses `origin` for your fork; add the main repository as `upstream` once:

```bash
git remote add upstream https://github.com/yukange/pata.git
```

## Contribution flow

Start from the latest upstream `main`:

```bash
git switch main
git fetch upstream
git rebase upstream/main
git switch -c your-branch
```

Make your change and run the checks relevant to it. For application changes, the available checks include:

```bash
swift test
./scripts/build_swift_app.sh
```

For UI changes, also verify the affected flow in the macOS app. Record the checks and results in the PR. For documentation-only changes, check formatting, links, and commands.

Commit only the intended files and push your branch:

```bash
git add path/to/changed-file
git commit -m "[component] Describe the change"
git push -u origin your-branch
```

Open a pull request against `yukange/pata:main`. Use `[Issue XYZ][component] Title` when an issue and component apply. Omit either prefix when it does not apply. Keep each PR focused on one issue.

## Code style

Format Swift files according to standard Swift conventions. Follow Swift 6 concurrency and actor-isolation rules.
Keep comments focused on behavior and non-obvious constraints. Review the project rules in [AGENTS.md](AGENTS.md) before changing product behavior or data storage.

## Create new files

Place new files in the relevant SwiftPM target under `Sources/`:
- `PataCore`: Business models, schema, vault file storage, links, indexing, search.
- `PataEditor`: AppKit/TextKit note editor.
- `PataAudio`: Qwen ASR client, audio player, transcript models.
- `PataKeychain`: macOS Keychain integration.
- `PataMCP`: Local JSON-RPC 2.0 MCP server.
- `PataUI`: SwiftUI views and view models.
- `PataApp`: App entry point and system commands.

Add corresponding tests under `Tests/PataTests/`.

## Update dependencies

Dependencies are managed using Swift Package Manager in `Package.swift`.
Limit dependency changes to the needs of the PR. Check bundle size, offline use, and macOS compatibility before adding a dependency.
