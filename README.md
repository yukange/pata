# 啪嗒 · Pata

**记下一点，完成一件。**

一款极简、本地优先、以 Markdown 为唯一业务数据源的 macOS 个人工作工具。

**Today 管当下，Tasks 管进展，Notes 管沉淀，Activity 负责留痕，标签负责关联。**

> **当前状态（2026-10）**：阶段 1～11 的桌面代码与 macOS 实机验收已完成；阶段 12「前端基础设施与设计系统整理」设计已定稿，尚未实施。实际进度以 [docs/README.md](docs/README.md) 为准。

## 项目推进方式

`docs/` **按交付顺序划分实施阶段，不按功能模块划分**。每阶段以 `idea.md` 和 `proposal.md` 记录目标、实现与验收。阶段 1～11 已完成；第 12 阶段为 [前端基础设施与设计系统整理](docs/12-frontend-foundation/proposal.md)，保留现有视觉，按需统一组件、Tokens 与交互体验。

**完整阶段清单：[docs/README.md](docs/README.md)**

> 开发注意：`frontend/bindings/` 由 wails3 CLI 生成，须用与 `go.mod` 一致的 **v3.0.0-beta.28**（`wails3 generate bindings -clean=true -ts -i`），其他版本会触发全量风格迁移。

## 体验 UI 原型

直接用浏览器打开 [`docs/01-validate/prototype/index.html`](docs/01-validate/prototype/index.html)，无需安装依赖或构建；刷新即恢复演示数据。

## MVP 边界

- 三个一级入口：**Today / Tasks / Notes**；Memo 是记录数据，不是第四个入口。
- 标签是跨 Task / Note / Memo 的全局聚合；没有 Projects / Inbox。
- Notes 采用 Flomo 启发的单列卡片列表，打开后占用整块主内容区编辑。
- 本地 Markdown + YAML Frontmatter；初期无需独立业务数据库。
- **CLI、MCP、内置 AI、插件、云同步均不进入 MVP**；阶段 11 的云端 ASR 仅用于 BYOK 音频转写，不提供内置 AI 整理。

当前技术基础为 Go + Wails v3 + React/TypeScript + Vditor，既有 Notes、Vault、Files、Activity 功能在阶段 1～9 已陆续实现。

原生体验目标遵循 macOS 27 HIG；[Magpie 源码实现参考与 macOS 验收约束](docs/01-validate/macos-native.md) 已加入阶段 1，真正的标题栏和系统材质在阶段 2 Wails 实机验证。
