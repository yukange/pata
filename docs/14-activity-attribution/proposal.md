# 阶段 14 · Agent 操作来源与任务生命周期记录 — Proposal

> 状态：**代码与自动化验收已完成，macOS 界面人工验收待完成**（2026-10-23）。本文件是 014 的实施与验收主文档；产品裁决见 [idea.md](idea.md)，正式存储协议以 [02-foundation/schema.md](../02-foundation/schema.md) 为唯一来源。

## 一、实施前基线与实施边界

- 已有 `Task.CreatedAt` / `Note.CreatedAt`，任务完成、重开存于 `Task.StatusEvents`，评论与 Today 独立记录使用内嵌 `Activity`；Task / Today 已共用 `ActivityItem` 的排版原则。
- Task 详情通过 `buildTaskTimelineItems` 组合普通 Activity 与 `status_events`；Today 通过 `VaultService.GetDayTimeline` 聚合普通 Activity 与任务状态事件。014 应复用这两条链路，不建第二份事件存储。
- 实施前 MCP 仅有 `pata_search`、`pata_list`、`pata_read`、`pata_create_note`、`pata_create_task`、`pata_append_activity` 六个工具；014 已补齐第七个工具 `pata_set_task_status`，用于完成/重开既有 Task。
- 014 修改范围：Markdown 对象的来源元数据、Go Core 写入来源、MCP 状态变更入口、Today/Task/Note 展示、相关测试与权威 Schema 更新。

## 二、来源语义和数据结构

### 2.1 统一解释规则

| 数据位置 | 仅在 Agent 操作时写入 | 字段缺失时 |
| --- | --- | --- |
| Task Frontmatter | `created_by: agent` | 视为「由我创建」 |
| Note Frontmatter | `created_by: agent` | 视为「由我创建」 |
| Task `status_events[]` | `by: agent` | 本次操作视为「我」 |
| 普通内嵌 Activity 元数据 | `by: agent` | 本条记录视为「我」 |

- 来源只允许 `agent` 或**不写字段**。不引入 `app`、`human`、`unknown`、`legacy` 或第三种来源，也不改写旧 Markdown。
- `created_by` 表示实体创建时的来源，`by` 表示这**一次**事件或 Activity 创建时的来源；并非最新修改人，不能因后续编辑而覆盖。
- 来源元数据不参与标签、搜索排序、Note 引用、时间计算或业务实体 ID 的判定。
- 仅两种明确受信任的入口：Pata GUI 默认不写字段；Pata MCP 的写操作由 Go Core 标记 `agent`。不要接受 MCP 创建参数中的 `created_by` / `by` 作为身份依据。
- 当前 MCP 属于本机访问通道，UI 的「Agent」是产品层的操作来源说明，不声称能识别具体模型或认证调用方身份。

### 2.2 存储示例

Task Frontmatter：仅增加创建来源，创建事件**不生成额外的 `a-` Activity**。

```yaml
---
type: task
id: t-01...
title: 优化 Note 编辑器
status: todo
created_at: 2026-10-23T09:20:00+08:00
updated_at: 2026-10-23T11:40:00+08:00
created_by: agent
status_events:
  - action: completed
    at: 2026-10-23T10:15:00+08:00
  - action: reopened
    at: 2026-10-23T11:40:00+08:00
    by: agent
---
```

上例表示「Agent 创建 → 我完成 → Agent 重新打开」。省略其他现有业务字段只是便于展示，不代表删除现有必填字段。

普通 Activity 使用既有内嵌块的元数据：

```markdown
<!-- pata:activity
id: a-01...
at: 2026-10-23T12:05:00+08:00
by: agent
-->
已修复编辑器问题，等待验证。
<!-- /pata:activity -->
```

Note 使用 Frontmatter 的可选 `created_by: agent`，其正文、标签及自动转写结构不变。

### 2.3 原有数据处理

- **无兼容分支、无迁移任务、无历史回填**：旧 Task / Note / Activity / status_event 没有来源字段时直接按「我」呈现，读取和再次保存均保持有效。
- 已完成任务如果只有 `completed_at`、没有对应 `status_events`，延续现有时间线兜底展示，来源默认为「我」，不要为了添加来源重新生成或写入历史事件。
- 保存/重扫/编辑现有对象时不得擦除已经存在的 `created_by` 或 `by`。更新普通 Activity 时保持原始 `by`；更新任务状态只为**新产生的事件**赋来源。
- 新建 Task 时若初始 `status: done`，仍沿用已有「创建 + 完成事件」语义；通过 MCP 创建时两处均标记 Agent，即使两事件时间相同也不能漏掉一个。

## 三、Go Core 与 MCP（014-001 / 014-002）

### 来源写入路径

- 在 Go Core 内部使用明确、可测试的入口来源（GUI / MCP）；共用原来的 Task、Note、Activity、状态变更写入流程，不复制新的写文件逻辑。
- 现有对 Wails GUI 暴露的方法自然视为「我」；MCP 写工具调用带内部 Agent 来源的 Core 方法/包装，**而不是向外部可传入的 DTO 加一个任意 `by` 参数**。Agent 也不能通过内容、标签、模型名推断来源。
- 统一检查所有状态写入口：`UpdateTask` 与 `SetTaskStatus` 都可能触发完成或重开事件，须共用一致的状态变更与来源写入逻辑，避免遗漏或重复事件。
- Task、Note 和 Activity 的解析、克隆、序列化、索引及返回给前端的 JSON 均应携带可选来源字段；`status_events` 也需包含可选 `by`。Wails bindings 按项目约定重新生成，不手改生成文件。
- 保留 Vault 现有原子写入、并发冲突保护和外部修改感知；不新增第二写入引擎。

### MCP 增量

新增且仅新增一个状态工具，例如：

```text
pata_set_task_status
input: { id: "t-...", status: "done" | "todo" }
```

- `todo → done`：在 Task `status_events` 写入 `completed`、来源 Agent；`done → todo`：写入 `reopened`、来源 Agent。
- 与目标状态相同视为无变化：不要追加假的完成/重开事件；明确返回当前任务状态。
- 工具校验任务 ID、目标状态及当前 Vault，并沿用现有 MCP 的本机访问限制与写入完成后通知 GUI 刷新的机制。
- 当前 MCP `pata_create_task`、`pata_create_note`、`pata_append_activity` 改为通过内部可信来源写入；读取工具不改语义。
- 本阶段**不扩展**通用修改标题、批量编辑、删除、Agent 身份注册或操作审计工具。

## 四、UI 交互（014-003 / 014-004）

### Task 详情及 Today

- **任务标题及属性区不出现来源标签**。创建信息在 Activity 时间线里展示为系统事件，使用 `Task.created_at` 与 `Task.created_by` 虚拟生成一次；不新增可编辑的普通 Activity。
- 在 Task 详情时间线增加创建事件；在 `GetDayTimeline` 聚合对应日期的 Task 创建事件。Today 事件维持现有任务标题链接，点击仍打开全局 Task Inspector。
- 系统事件只读、紧凑、单行：`由我创建`、`由 Agent 创建`、`由我完成`、`由 Agent 完成`、`由我重新打开`、`由 Agent 重新打开`。
- 普通 Activity 在原有时间旁展示灰色 `UserRound` / `Bot`（或项目中等价 Lucide 图标）和 `我` / `Agent`；正文仍在下一行。Today 若需显示任务链接，继续按 013 的字号和布局安排在时间右侧，不能让来源标识挤掉任务上下文。
- 同一 Activity 在 Today 和 Task 详情的来源、时间、内容一致；普通 Activity 原地编辑后不改变创建来源。人工评论、Today 独立 Activity 也按默认「我」显示。
- 不调整 Task 列表、Today 的任务清单、标签视图或 Notes 列表，也不增加来源筛选项。

### Note 编辑页面

- Note 编辑页标题附近显示轻量创建元信息：灰色用户/机器人图标 + `由我创建` / `由 Agent 创建`，不干扰标题输入、标签或 Vditor。
- 不建立 Note Activity 时间线；Note 被编辑或重新转写不会使其创建来源改变。GUI 发起 MP3 导入并使用云端 ASR 时，创建来源是「我」。
- 不将来源写入 Note 正文；来源只属于 Frontmatter 元数据。

### 样式及可访问性

- 复用现有 `ActivityItem`、`taskTimeline.ts`、`activityUtils.ts`、Design Tokens 与 Lucide，不单独创建大面积带底色 Badge 或头像。
- 字号与灰度沿用阶段 13 的时间元信息层级；浅/深色及减少动态效果正常。来源标识须有可读文字，不只依赖图标区分。
- 跨日和同时间戳排序稳定；Task 的创建事件不因 Today 是否计划了该任务而消失；任务删除后的现有引用处理规则不变。

## 五、分批实施和完成标准

| 编号 | 工作包 | 验收 |
| --- | --- | --- |
| 014-001 | Go Schema 与可信来源写入 | Task / Note 的 `created_by`、Activity / 状态事件的 `by` 精确持久化；无字段即我；读写往返不丢 |
| 014-002 | MCP 增加 Task 完成/重开 | 新工具能产生正确状态事件、标为 Agent；重复设置状态不重复记录；界面刷新 |
| 014-003 | Task / Today 任务生命周期展示 | 创建 / 完成 / 重开显示来源；Today 任务链接正确；旧事件默认我；排序一致 |
| 014-004 | 普通 Activity / Note 创建来源 UI | 评论和 Today 独立记录显示来源；Note 标题附近展示；编辑不改来源 |
| 014-005 | 回归、Schema 文档和实机验收 | 同步更新 02 Schema、MCP 工具文档和 bindings；全量自动化与 macOS 实机验证 |

### 核心验收用例

1. GUI 创建 Task → Task 详情及当天 Today 都显示「由我创建」；未在文件中写入来源字段。
2. MCP 创建 Task → 两处显示「由 Agent 创建」；`created_by: agent` 保存成功。MCP 直接创建已完成任务时同时正确展示 Agent 创建和 Agent 完成。
3. GUI 完成 → Agent 重新打开 → GUI 再完成：时间线每次分别显示来源，`completed_at` 和 `status_events` 仍符合既有状态语义。
4. 同一个已完成任务重复调用 MCP 完成：不会新增重复的完成事件；不存在的任务及非法状态明确报错。
5. GUI/MCP 分别在 Task 和 Today 新增普通 Activity：正确标记来源；Today 和 Task 详情一致；编辑和文件重扫后来源不变。
6. GUI/MCP 分别创建 Note：编辑页显示正确来源；编辑正文或标题不会覆盖创建来源。用户通过 GUI 导入并转写 MP3 仍显示「由我创建」。
7. 原有未标来源的 Task、Note、Activity、status_event：全部视为「我」，无迁移步骤，无异常提示或额外字段回写；旧 `completed_at` 兜底展示正常。
8. Today 记录、任务详情、Task 列表、Notes 列表、全局搜索、笔记引用、拖拽、删除/恢复、资料库切换与草稿保护不回退；macOS 深浅色、窄窗口和键盘可用。
9. Go 测试覆盖 Schema 解析/序列化/Clone、写入来源与状态事件；前端测试覆盖时间线构建、来源文案、排序与列表不显示；构建、回归和实机验收通过后才标记本阶段完成。

## 六、不做

- 不新增独立 Activity 文件、Task 创建日志的第二份存储或通用事件审计服务。
- 不为已有数据增加 `unknown`、`legacy`、`human` 兼容类型，不运行历史迁移或回填。
- 不做多人账户、权限、Agent 名称/模型识别、真实性证明、最后编辑人追踪或完整修改历史。
- 不在任务标题、任务列表或 Notes 列表加来源徽标，不增加过滤器、头像和新的主导航。
- 不因语音转写由云模型处理就把用户创建的 Note 标记为 Agent。
- 不因为 014 扩充 MCP 的其他增删改能力、引入 Harness 或个人 Obsidian 迁移工具。

## 七、实施记录

- **014-001～004 已实现**：可选来源字段沿现有解析/序列化/Clone/索引/JSON 链路传递；GUI 公共方法默认我，MCP 只调用带 Agent 来源的私有 Core 入口，外部 DTO 不含来源参数。三个状态写入口共用 `applyTaskStatus`，沿用原子保存与 baseline 冲突保护。
- Task 创建、状态事件及 Activity 使用相同稳定键规则；同时间戳保留状态数组顺序，Task 正序、Today 倒序。`completed_at` 缺少对应完成事件时只读兜底为我，不回写历史。
- Task / Today 复用 `ActivityItem` 显示来源，Note 仅在编辑页标题附近展示；任务与笔记列表保持原样。没有新增依赖、迁移或事件存储。
- 审查修复：Task Inspector 收到当前任务变更时停止排队和后续保存，无草稿时自动刷新；有草稿、刷新失败或异步响应已过期时保留草稿与保存保护，避免旧状态覆盖 MCP 操作。搜索仅匹配可见内容，排除 Activity 内部元数据；旧资料库兼容性使用固定 Markdown 临时资料库，不依赖个人目录。
- **014-005 自动化与文档已完成**：权威 Schema、产品裁决、MCP 工具说明、中英文 README 和 Wails 生成 bindings 已同步。

### 已执行验证

- `go test ./...`：全量通过；新增 Schema 往返/Clone/JSON、非法来源拒绝、真实 MCP 内存传输调用、GUI/MCP 混合生命周期、重复状态不写盘、通知刷新、Vault 切换拒绝、来源保留及跨日/同时间戳排序测试。音频导入回归确认 GUI/ASR 不改变创建来源。
- `npm --prefix frontend test`：81 项通过，涵盖创建事件、来源文案、旧数据兜底、稳定排序、跨页面来源传递、列表不显示来源，以及 MCP 状态变更后的草稿保护、保存暂停、自动刷新和异步响应顺序。
- `npm --prefix frontend run build`：TypeScript 和生产前端构建通过。
- `wails3 task darwin:package BIN_DIR=/tmp/pata-stage14`：macOS 原生生产包构建与 ad-hoc 签名/`codesign --verify --deep --strict` 通过，产物为 `/tmp/pata-stage14/pata.app`。

### 待完成的人工验收

- 使用本次新包逐项操作核心验收用例，确认 Today 任务链接、Inspector、Note 编辑与 MP3 转写的实际显示。
- macOS 浅/深色、窄窗口、键盘焦点、减少动态效果，以及拖拽、草稿保护、删除恢复和资料库切换的界面回归。
- 上述人工验收完成前，014 不标记整个阶段已完成。
