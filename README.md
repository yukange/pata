# Pata · 啪嗒

**English | [简体中文](README.zh-CN.md)**

**Capture a thought. Finish a task.**

Pata is a local-first macOS app for personal work. **Today keeps you focused, Tasks tracks what needs doing, Notes holds what you learn, Activity preserves what happened, and tags connect it all.**

Instead of adding layers of project management, Pata brings your tasks, daily records, and notes into one lightweight workspace.

## Features

- **Today**: Plan your day and capture what happened. A task's due date is independent of the days you plan to work on it.
- **Tasks**: Keep tasks either open or completed, with a running activity history. No complex workflow states or priorities.
- **Notes**: Browse a single-column note list, write in Markdown, and connect ideas with tags and `[[note references]]`.
- **Activity**: Record comments on tasks or standalone daily entries. Task activity appears consistently in both the task details and the Today timeline.
- **Search and attachments**: Search tasks, notes, activity, and attachment filenames. Import and reference files, with native macOS preview support.
- **Audio transcripts**: Turn an imported MP3 into a Markdown transcript with speakers and millisecond timestamps using your own API key. Jump between the transcript and its audio player.
- **Local MCP**: Let an external agent search, read, and create tasks and notes, append activity to a task or day plan, and complete or reopen tasks. Activity and creation details show whether an action came from you or an agent.

## Principles

**Less is More · Record Once · Local First**

- Just **Today / Tasks / Notes** as the three main destinations. No Projects or Inbox.
- **Markdown + YAML frontmatter** is the source of truth. No separate application database is required. The Vault stores records in `notes/`, `tasks/`, and `plans/`, and original attachments in `files/`.
- Activity belongs to a Task or DayPlan, so the same record does not need to be stored twice.
- There is no built-in general-purpose AI chat workspace. Agents connect through the optional local MCP server. Audio transcription is explicitly initiated by the user and uses a cloud ASR service; the API key is stored in macOS Keychain.
- Keep the experience pleasant and practical for individual use without adding complexity just for future extensibility.

## Run and develop

Pata is currently run from source or packaged locally on macOS. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and the full development workflow. You will need Go, Node.js, Xcode Command Line Tools, and the Wails v3 CLI version matching this repository.

```bash
git clone https://github.com/yukange/pata.git
cd pata
go mod download
npm --prefix frontend ci
wails3 task dev
```

Run `wails3 task package` to build a local app package. When changing Go service interfaces, follow the [development instructions](CONTRIBUTING.md#create-new-files) for generating Wails bindings; do not hand-edit generated files.

## Connect an agent (MCP)

In Pata, open **Settings → MCP**, enable the local service, and copy its connection instructions into your agent. The service listens only on `127.0.0.1` and requires Pata to stay running. It is disabled by default and stays disabled after you manually stop it.

The seven tools cover search, list, read, create task, create note, append activity, and set task status. See the [MCP reference](docs/10-settings/proposal.md#mcp) for their behavior and limitations.

## Documentation

- [Design and implementation history](docs/README.md): Delivery stages 01–13 and their documents (Chinese).
- [Data schema](docs/02-foundation/schema.md): Authoritative Markdown data model (Chinese).
- [Product decisions](docs/01-validate/decisions.md): Agreed design choices and boundaries (Chinese).
- [AGENTS.md](AGENTS.md): Project instructions for development agents (Chinese).
- [Early interaction prototype](docs/01-validate/prototype/index.html): A browser-viewable historical prototype, **not a representation of the complete current macOS app**.

Stages 01–13 have been implemented and validated on macOS. Future changes will follow actual usage needs rather than a predetermined series of feature stages.
