<p align="center">
  <a href="https://github.com/yukange/pata">
    <img src="assets/branding/logo.svg" width="96" alt="Pata logo">
  </a>
</p>
<h1 align="center">Pata · 啪嗒</h1>
<p align="center">A local-first macOS workspace for tasks, daily records, and notes.</p>
<p align="center">
  <a href="https://github.com/yukange/pata/releases/latest"><img src="https://img.shields.io/github/v/release/yukange/pata?style=flat-square&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-macOS-181717?style=flat-square" alt="macOS">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-181717?style=flat-square" alt="MIT License"></a>
  <a href="#your-files-stay-yours"><img src="https://img.shields.io/badge/storage-Markdown-181717?style=flat-square" alt="Local Markdown files"></a>
</p>
<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a>
</p>

[![Pata on macOS: today's plan and activity timeline with sample data](docs/05-release/screenshots/workspace.png)](https://github.com/yukange/pata/releases/latest)

---

### Installation

Download the latest app from [**GitHub Releases**](https://github.com/yukange/pata/releases/latest).

| Platform | Download |
| --- | --- |
| macOS · Apple Silicon | [pata.dmg](https://github.com/yukange/pata/releases/latest/download/pata.dmg) |

Open the disk image, drag Pata into Applications, and launch it. Choose a folder for your Vault when prompted. Current release packages target Apple Silicon Macs.

### One workspace. Three places to start.

- **Today** — Pick the tasks you want to work on and jot down what happens. A daily plan is separate from a task's due date.
- **Tasks** — Keep the task and its progress together. Add activity as you work; the same record also appears in your daily timeline.
- **Notes** — Start with an untitled draft. Give it a name when it is ready. Browse notes and write Markdown side by side, with tags and `[[note references]]` to connect ideas.

Search across tasks, notes, and activity. Drop in attachments and preview them with macOS. Import an MP3 to create a transcript with speakers, timestamps, and audio playback.

**Less is More · Record Once · Local First**

### Connect your agent

Enable **Settings → MCP** in Pata and copy the connection instructions into your MCP-compatible client.

Your agent can find and create tasks and notes, append activity, and complete or reopen tasks. Pata marks agent-created records so you can see who did what.

From a task's details menu, choose **Copy for Agent** and paste the short reference (`pata://task/{id}`) into an agent already connected to Pata MCP. Agents can fetch a referenced Note by its stable ID from an Activity's `note_refs` via `pata_read`.

The service is off by default, listens only on `127.0.0.1`, and runs while Pata is open. See the [MCP reference](docs/10-settings/proposal.md#mcp) for details.

### Your files stay yours

Your Vault is a local folder. Tasks, day plans, and notes are Markdown files; original attachments stay alongside them.

```text
vault/
├── tasks/    Tasks and their activity
├── plans/    Daily plans and daily records
├── notes/    Notes, drafts, and transcripts
└── files/    Original attachments
```

Back up the whole folder, including `plans/` and `files/`. Notes remain readable in other Markdown tools; use Pata to manage the structured task and day-plan files.

Tasks and notes work offline. Optional audio transcription sends the selected recording to Alibaba Cloud Bailian and requires your own API key, stored in macOS Keychain. An external agent's data handling depends on the client and model you connect.

### Run from source

Requires macOS 14.0+ and Xcode / Swift 6.

```bash
git clone https://github.com/yukange/pata.git
cd pata
./scripts/build_swift_app.sh
```

Run tests:
```bash
swift test
```

### Documentation

[Product decisions](docs/01-validate/decisions.md) · [Data format](docs/02-foundation/schema.md) · [Design and implementation](docs/README.md)

### Contributing

Found a bug or have an idea? [Open an issue](https://github.com/yukange/pata/issues). Before sending a pull request, read the [contribution guide](CONTRIBUTING.md).

### License

[MIT](LICENSE) · Copyright © 2026 Pata contributors.
