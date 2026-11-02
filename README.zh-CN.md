<p align="center">
  <a href="https://github.com/yukange/pata">
    <img src="assets/branding/logo.svg" width="96" alt="Pata 标识">
  </a>
</p>
<h1 align="center">啪嗒 · Pata</h1>
<p align="center">把待办、日常记录和笔记，放进一个本地优先的 macOS 工作区。</p>
<p align="center">
  <a href="https://github.com/yukange/pata/releases/latest"><img src="https://img.shields.io/github/v/release/yukange/pata?style=flat-square&label=release" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/platform-macOS-181717?style=flat-square" alt="macOS">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-181717?style=flat-square" alt="MIT License"></a>
  <a href="#文件留在自己手里"><img src="https://img.shields.io/badge/storage-Markdown-181717?style=flat-square" alt="本地 Markdown 文件"></a>
</p>
<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

[![Pata macOS 实际界面：今日计划与活动时间线，使用示例数据](docs/05-release/screenshots/workspace.png)](https://github.com/yukange/pata/releases/latest)

---

### 安装

从 [**GitHub Releases**](https://github.com/yukange/pata/releases/latest) 下载最新版本。

| 平台 | 下载 |
| --- | --- |
| macOS · Apple Silicon | [pata.dmg](https://github.com/yukange/pata/releases/latest/download/pata.dmg) |

打开安装镜像，将 Pata 拖入「应用程序」并启动。首次打开时，选择一个文件夹作为 Vault。当前发布的安装包面向 Apple Silicon Mac。

### 一个工作区，三个入口

- **Today** — 安排今天要做的事，随手记下当天的进展。日计划与任务截止日期相互独立。
- **Tasks** — 把任务和过程放在一起。随时追加活动记录，同一条记录也会出现在当天的时间线中。
- **Notes** — 从无标题草稿开始，想好后再命名为笔记。左边浏览，右边编辑 Markdown，用标签和 `[[笔记引用]]` 连接想法。

统一搜索任务、笔记和活动。拖入附件，用 macOS 原生预览打开。导入 MP3，生成带说话人、时间戳和音频播放的逐字稿。

**少即是多 · 只记录一次 · 本地优先**

### 连接你的 Agent

在 Pata 的「**设置 → MCP**」中启用服务，将接入说明复制到支持 MCP 的客户端。

Agent 可以查找和新建任务、笔记，追加活动记录，完成或重新打开任务。由 Agent 创建的记录会标明来源，方便区分是谁做了什么。

打开任务详情「··· → 复制给 Agent」，粘贴 `处理这个 Pata 任务：pata://task/{id}` 即可让已接入 Pata MCP 的 Agent 定位任务。活动记录保留关联笔记的稳定 ID，Agent 可通过 `pata_read` 按需读取正文。

服务默认关闭，只监听本机 `127.0.0.1`，使用时需要 Pata 保持运行。详细行为见 [MCP 功能说明](docs/10-settings/proposal.md#mcp)。

### 文件留在自己手里

Vault 就是一个本地文件夹。任务、日计划和笔记保存为 Markdown，原始附件也保存在其中。

```text
vault/
├── tasks/    任务及其活动记录
├── plans/    日计划和每日记录
├── notes/    笔记、草稿和逐字稿
└── files/    原始附件
```

备份时保留整个文件夹，包括 `plans/` 和 `files/`。笔记可在其他 Markdown 工具中阅读；任务和日计划包含结构化数据，日常操作通过 Pata 完成。

任务和笔记可离线使用。可选的音频转写会将所选录音发送到阿里云百炼，需要自备 API Key，密钥保存在 macOS Keychain。外部 Agent 如何处理数据，取决于你接入的客户端和模型。

### 从源码运行

需要 macOS 14.0+ 与 Xcode / Swift 6。

```bash
git clone https://github.com/yukange/pata.git
cd pata
./scripts/build_swift_app.sh
```

运行单元测试：

```bash
swift test
```

### 文档

[产品取舍](docs/01-validate/decisions.md) · [数据格式](docs/02-foundation/schema.md) · [设计与实施记录](docs/README.md)

### 参与贡献

发现问题或有新想法，可以 [提交 Issue](https://github.com/yukange/pata/issues)。提交 PR 前，请先阅读 [贡献指南](CONTRIBUTING.md)。

### 许可证

采用 [MIT 许可证](LICENSE)。版权所有 © 2026 Pata 贡献者。
