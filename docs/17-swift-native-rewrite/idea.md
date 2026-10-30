# 阶段 17 · Pata 纯 Swift 原生重构 — Idea

> **状态：需求已确认，尚未实施。** 本阶段是有独立交付价值的技术栈替换，目标为 Pata 2.0；当前 Go + Wails + React 版本继续可用。具体范围、实施包与验收见 [proposal.md](proposal.md)。

## 为什么重构

Pata 是 **macOS-only、Local First、Less is More** 的 Markdown 任务与笔记工作台，不以跨平台为目标。现有 Go + Wails v3 + React + Vditor 方案已交付完整产品，但 macOS 触控板「轻点来点按」在部分第三方输入法（实测豆包输入法中英文模式）下可能丢失首次点击；系统 ABC 正常。此问题在同为 WKWebView 的其他应用中也可复现，不应简单归咎于 React 或 Vditor。

另一方面，Vditor 的 Markdown IR 边界、编辑器状态与前端集成成本持续影响主要工作流。重构目标是**从根本上减少运行时与技术层级，获得原生编辑与交互体验**，而不是因为 Swift 流行而改语言。

## 已确认的方向

1. **最终产品纯 Swift**：SwiftUI + 必要的 AppKit 原生控件；核心业务、存储、搜索、MCP、音频、设置及更新均迁移到 Swift。最终分发包不含 Go 服务、Wails、React/Vite 或 Vditor 的运行时。
2. **Markdown IR 是核心验收条件**：优先验证开源 [SwiftMarkdownEngine](https://github.com/nodes-app/swift-markdown-engine)（TextKit 2 / AppKit），基于接口隔离编辑器。其默认 Wiki Link 存储规则不等于 Pata 的 Schema，严禁未经适配直接落盘。
3. **业务模型与数据协议不变**：Today / Tasks / Notes 三入口、唯一全局 Task Inspector、Notes 左列表右编辑器、Task / Note / DayPlan / Activity、草稿、标签、搜索、附件、音频逐字稿、来源归属等均按现有实现和权威 [Schema](../02-foundation/schema.md) 迁移。
4. **仍是单一 App Core**：GUI 和现有本地 MCP 从同一 Swift Core 读写当前 Vault；未来若新增 CLI，也只是转发给运行中的 App，不做第二套写入引擎。
5. **保留现有使用习惯**：不顺带重新设计 UI、不引入数据库/云同步/多工作区/新业务概念。Pata 2.0 不要求数据导入迁移；旧 Vault 应能直接打开。
6. **AI 可负责大量代码迁移，但验收必须依赖事实**：跨实现行为契约、测试样本、自动化测试及真实 macOS 验证，而非只以编译通过为完成。

## 关键取舍

- **不采用长期 SwiftUI + Go 的双栈架构**。可在实施期间保留旧版本作回归参照；目标产物只有 Swift。
- 编辑器先做可运行的原生验证：Markdown IR、中文 IME 组合输入、焦点/轻点、Undo/Redo、选区和保存往返；若 SwiftMarkdownEngine 不满足要求，可在独立编辑器模块内替换，不推倒 App Core。
- **Note 正文**继续存标准 Markdown 相对链接（链接到 Note/File），**Task 描述与 Activity 正文**仍为纯文本 `[[名称]]`，通过各自 `note_refs` 绑定真实 Note ID；不改成 `[[Name|ID]]` 协议。
- 没有 Apple Developer Program 也可本机构建/测试；官方签名、公证及应用内更新发布链另按真实分发条件验收。
- 优先完整继承已有功能，**禁止以“重构顺便精简”为由静默删除 MCP、自动更新、音频转写或草稿保护**。

## 交付

阶段 17 完成时，Pata 能直接读取原 Vault，作为独立 Swift 原生 macOS App 正常使用；核心行为与旧版一致，编辑/输入交互达到原生验收标准；Go/Wails/React/Vditor 依赖可从最终构建移除。详见 [实施与验收方案](proposal.md)。
