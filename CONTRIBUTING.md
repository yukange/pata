# How to contribute

Fork Pata, make a focused change, and open a pull request against `yukange/pata:main`.
Use the issue templates for bug reports and feature requests, and the pull request template to explain your changes.

## Prerequisites

For local macOS development, install:

- Go 1.25.0 or later, as specified in `go.mod`.
- Node.js 22.12.0 or later in the 22.x release line, with npm.
- Xcode Command Line Tools.
- Wails CLI `v3.0.0-beta.28`, matching the version in `go.mod`.

Install the Wails CLI and make it available in your shell:

```bash
go install github.com/wailsapp/wails/v3/cmd/wails3@v3.0.0-beta.28
export PATH="$(go env GOPATH)/bin:$PATH"
```

### Set up the project

After creating your fork, replace `YOUR_GITHUB_ID` with its owner:

```bash
git clone https://github.com/YOUR_GITHUB_ID/pata.git
cd pata
go mod download
npm --prefix frontend ci
```

Run the desktop app in development mode:

```bash
wails3 task dev
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
npm --prefix frontend run build
npm --prefix frontend test
go test ./...
wails3 task package
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

Format changed Go files with `gofmt`. Follow the existing React and TypeScript patterns and reuse the project's components, hooks, and design tokens.

Keep comments focused on behavior and non-obvious constraints. Review the project rules in [AGENTS.md](AGENTS.md) before changing product behavior or data storage.

## Create new files

Place new files in the module that owns the behavior. Desktop setup, application services, and their unit and business acceptance tests live in `internal/app/`. The root `main.go` embeds resources and passes build metadata to the application; packaging and version consistency tests stay beside it. Run `go test ./...` to include the internal packages.

Keep implementation documents in the relevant stage under `docs/`, following [docs/README.md](docs/README.md).

Do not edit generated files in `frontend/bindings/` by hand. When Go service bindings change, regenerate them with the matching Wails CLI:

```bash
wails3 generate bindings -clean=true -ts -i
```

## Update dependencies

Go dependencies are tracked in `go.mod` and `go.sum`. Use `go get` for the intended version and `go mod tidy` to update the module files.

Frontend dependencies are tracked in `frontend/package.json` and `frontend/package-lock.json`. Use npm in `frontend/` and include both files when they change.

Limit dependency changes to the needs of the PR. Check peer dependencies, bundle size, offline use, and macOS compatibility before adding a dependency.
