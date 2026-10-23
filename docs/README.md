# Pata · 设计与实施记录

这里保存 Pata 的设计决策、实施过程和验收依据；面向日常使用的功能介绍请先看 [中文项目介绍](../README.zh-CN.md)（[English](../README.md)）。

**阶段 01～13 已完成代码与 macOS 实机验收。** 下表按历史交付顺序排列，而非当前功能模块。早期文档中的 Memo、旧布局或待实施表述，是当时的设计记录；**当前数据结构以 [Schema](02-foundation/schema.md) 和已实现的后续阶段为准**。

## 阶段索引

| 顺序 | 目录 / 阶段 | 阶段结束应交付什么 | 核心文档 |
|---|---|---|---|
| 1 | [`01-validate`](01-validate/) · 确认产品与交互 | 范围冻结、端到端流程、可离线运行的 UI 原型 | [idea](01-validate/idea.md) · [proposal](01-validate/proposal.md) · [UI](01-validate/ui.md) |
| 2 | [`02-foundation`](02-foundation/) · 数据底座 | 可启动的 Wails 桌面壳、Markdown Go Core、基本任务管理 | [idea](02-foundation/idea.md) · [proposal](02-foundation/proposal.md) · [schema](02-foundation/schema.md) |
| 3 | [`03-daily-loop`](03-daily-loop/) · 每日工作闭环 | Today 计划 + Memo 评论和独立记录 + 历史时间线 | [idea](03-daily-loop/idea.md) · [proposal](03-daily-loop/proposal.md) |
| 4 | [`04-knowledge-loop`](04-knowledge-loop/) · 文档沉淀 | 单列 Notes、长篇 Markdown 编辑、明确的 Task–Note 关联 | [idea](04-knowledge-loop/idea.md) · [proposal](04-knowledge-loop/proposal.md) |
| 5 | [`05-release`](05-release/) · 整合交付 | 全局标签/搜索、安全性回归、macOS MVP 打包验收 | [idea](05-release/idea.md) · [proposal](05-release/proposal.md) · [验收](05-release/acceptance.md) |
| 6 | [`06-branding`](06-branding/) · 品牌接入与 Logo 动画 | 三层卡片 V2 静态品牌接入、启动与记录成功动画、菜单栏增强验证 | [idea](06-branding/idea.md) · [proposal](06-branding/proposal.md) |
| 7 | [`07-note-links`](07-note-links/) · 笔记引用闭环 | 笔记正文 / 任务描述 / 活动记录统一 `[[` 引用、点击跳转、自动被引用来源 | [idea](07-note-links/idea.md) · [proposal](07-note-links/proposal.md) |
| 8 | [`08-activity-storage`](08-activity-storage/) · Activity 归属式存储重构 | 统一内嵌 Activity，Task/DayPlan 新格式、删除生命周期、搜索/时间线/链接回归 | [idea](08-activity-storage/idea.md) · [proposal](08-activity-storage/proposal.md) · [Schema](02-foundation/schema.md) |
| 9 | [`09-vault-files`](09-vault-files/) · 专属 Vault 与统一资源引用 | Vault 目录边界、拖入文件与 `[[` 复用、文件名搜索和系统预览 | [idea](09-vault-files/idea.md) · [proposal](09-vault-files/proposal.md) |
| 10 | [`10-settings`](10-settings/) · 统一应用设置 | 主窗口单页「外观 / 存储 / 语音转写」，迁移主题与 Vault 管理，Keychain 保存北京地域 API Key | [idea](10-settings/idea.md) · [proposal](10-settings/proposal.md) |
| 11 | [`11-audio-transcription`](11-audio-transcription/) · 本地音频转写为 Note | MP3 导入后创建只读逐字稿 Note、句级毫秒时间戳、音频双向定位、确认后重新转写 | [idea](11-audio-transcription/idea.md) · [proposal](11-audio-transcription/proposal.md) |
| 12 | [`12-frontend-foundation`](12-frontend-foundation/) · 前端基础设施与设计系统整理 | 保留 Pata 现有视觉，按需统一 Design Tokens/基础组件/键盘交互与拖拽体验，系统强调色优先（**已验收**） | [idea](12-frontend-foundation/idea.md) · [proposal](12-frontend-foundation/proposal.md) |
| 13 | [`13-app-shell-activity`](13-app-shell-activity/) · App Shell 与 Activity 体验统一 | 应用级三栏与可调任务详情、Today/Task 统一 Activity 展示/输入/编辑（**已验收**） | [idea](13-app-shell-activity/idea.md) · [proposal](13-app-shell-activity/proposal.md) · [三栏设计](13-app-shell-activity/app-shell-inspector.md) |

## 阅读与维护约定

- `idea.md` 记录该阶段的目标、价值与取舍；`proposal.md` 记录具体实现、交付范围和验收。
- [阶段 2 Schema](02-foundation/schema.md) 是 Task、Note、DayPlan 和 Activity 格式的单一权威来源；历史阶段中的旧数据示例不代表当前格式。
- 产品边界以 [阶段 1 决策](01-validate/decisions.md) 为准；开发约束见 [AGENTS.md](../AGENTS.md)。不要在各处复制另一份规范。
- 有必要新增独立交付目标时，才创建新的 `docs/NN-name/` 阶段；普通修复与小幅优化优先归入已有文档。
- 原型见 [阶段 1 浏览器原型](01-validate/prototype/index.html)，它是历史交互参考，不代表目前 macOS 应用的全部界面。

## 当前产品约束

- 仅 **Today / Tasks / Notes** 三个主导航；Activity 不是第四个入口，也不单独建立 Files 页面。
- Vault 使用 `notes/`、`tasks/`、`plans/` 和 `files/`。Markdown 是业务数据源；原始附件在 `files/` 中长期保留，不因引用删除自动清理。
- Task 和 DayPlan 分别拥有自身的 Activity；Today 计划与任务到期日独立，标签跨 Task、Note、Activity 聚合。
- 音频转写使用自备 API Key 调用阿里云百炼，并将逐字稿保存在普通 Markdown Note 中。
- 可选的**本机 MCP 已交付**，不是未实现的未来规划；通过 Pata Core 操作当前 Vault。具体工具和安全限制见 [MCP 说明](10-settings/proposal.md#mcp)。
- 当前不提供独立 CLI、内置通用 Agent 或云同步。

## 阶段之后的维护

- Today 任务拖拽排序和移出计划入口优化：[PR #5](https://github.com/yukange/pata/pull/5)。
- 阶段 12 前端规范与拖拽体验已实施：[PR #7](https://github.com/yukange/pata/pull/7)。
- 阶段 13 App Shell 级三栏、统一 Activity 展示与编辑已实施：[PR #9](https://github.com/yukange/pata/pull/9)。
- Notes 列表编号、代码块和撤销体验修复：[PR #8](https://github.com/yukange/pata/pull/8)、[PR #10](https://github.com/yukange/pata/pull/10)。
- 本机 MCP 服务已合并：[PR #12](https://github.com/yukange/pata/pull/12)。

具体实现、测试与验收仍以对应阶段的 `proposal.md`、测试源码和 PR 为准；这里不重复维护逐项完成日志。
