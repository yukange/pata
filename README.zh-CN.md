# 啪嗒 · Pata

**[English](README.md) | 简体中文**

**记下一点，完成一件。**

Pata 是一款为个人日常工作打造的 macOS 本地优先应用：**Today 管当下，Tasks 管进展，Notes 管沉淀，Activity 负责留痕，标签负责关联。**

不追求复杂的项目管理流程，而是把要做的事、已经做过的事和随手记下的内容自然地放在一起。

## 主要功能

- **Today**：安排当天任务，记录当天发生的事；日计划与任务到期日相互独立。
- **Tasks**：用「未完成 / 已完成」管理任务，任务下可以持续追加活动记录；不引入复杂状态或优先级。
- **Notes**：单列浏览笔记，用 Markdown 编辑内容，支持标签与 `[[笔记引用]]`。
- **Activity**：把任务评论和每日独立记录统一为活动；任务中的记录在任务详情与 Today 时间线中保持一致。
- **搜索与附件**：跨任务、笔记、活动和附件名称搜索；支持导入、引用文件并使用 macOS 原生预览。
- **音频逐字稿**：导入 MP3，使用自备 API Key 转写为带说话人和毫秒时间戳的 Markdown 笔记，可在播放器与逐字稿之间定位。
- **本机 MCP**：让外部 Agent 搜索、读取和新建任务/笔记，向任务或每日计划追加 Activity，以及完成或重新打开任务；记录和创建信息区分「我 / Agent」来源。

## 设计原则

**Less is More · Record Once · Local First**

- 只保留 **Today / Tasks / Notes** 三个主入口，不设 Projects 或 Inbox。
- 以本地 **Markdown + YAML Frontmatter** 为业务数据源，不依赖独立的业务数据库。Vault 中的 `notes/`、`tasks/`、`plans/` 保存记录，`files/` 保存原始附件。
- Activity 归属于 Task 或 DayPlan，避免一条记录在多处重复存储。
- 不内置通用 AI 聊天工作台；Agent 通过可选的本机 MCP 接入。音频转写按用户操作调用云端 ASR，API Key 保存在 macOS Keychain。
- 界面和功能优先服务顺畅的个人使用体验，不为扩展性增加不必要的复杂度。

## 运行与开发

当前主要通过源码运行或在 macOS 上本地打包。环境准备和完整开发流程见 [CONTRIBUTING.md](CONTRIBUTING.md)；需要 Go、Node.js、Xcode Command Line Tools，以及与项目依赖版本匹配的 Wails v3 CLI。

```bash
git clone https://github.com/yukange/pata.git
cd pata
go mod download
npm --prefix frontend ci
wails3 task dev
```

本地打包使用 `wails3 task package`。修改 Go 服务接口后，请按 [开发说明](CONTRIBUTING.md#create-new-files) 中的约定处理 Wails bindings，不要直接编辑生成文件。

## 连接 Agent（MCP）

在 Pata 的「设置 → MCP」中启用本机服务，复制接入说明供 Agent 使用。服务只监听本机 `127.0.0.1`，需要 Pata 保持运行；首次默认关闭，手动停止后不会在下次启动时自动开启。

目前提供搜索、列表、读取、新建任务、新建笔记、追加 Activity 和设置任务状态七项工具。更多行为与限制见 [MCP 功能说明](docs/10-settings/proposal.md#mcp)。

## 项目文档

- [设计与实施记录](docs/README.md)：阶段 01～13 的交付记录及文档入口。
- [数据格式（Schema）](docs/02-foundation/schema.md)：Markdown 数据结构的权威定义。
- [产品设计取舍](docs/01-validate/decisions.md)：已确认的交互与范围决策。
- [AGENTS.md](AGENTS.md)：面向开发 Agent 的工程约束。
- [早期交互原型](docs/01-validate/prototype/index.html)：无需构建即可在浏览器查看，**不代表当前应用的完整界面**。

Pata 的阶段 01～13 已完成代码与 macOS 实机验收；后续改进以实际使用体验为依据，不预设新的大型功能阶段。
