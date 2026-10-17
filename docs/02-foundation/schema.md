# Markdown Schema — V2 目标规范（阶段 8）

> **状态：已确认的目标协议，尚未实施。** 阶段 8 落地 Activity 归属模型；阶段 9 增补 Vault 边界与文件资源引用。 现有源码和 `docs/02-foundation/examples/` 仍可能使用 V1 Memo/Task Body 布局；示例文件暂作为旧测试固件保留，待 [阶段 8](../08-activity-storage/proposal.md) 编码时同步更换。**本文件是未来存储协议的唯一规范来源**；第 8 阶段 proposal 只说明实施步骤。

## 通用约定

- UTF-8 Markdown，文件以 YAML Frontmatter 开始；`type` 用于 Task、Note、DayPlan 顶层实体。`Activity` 是内嵌子记录，**不是**独立 Markdown 文件/`type`。
- 日期 `YYYY-MM-DD` 是用户选择的工作日。事件时间戳 `at`、`created_at` 等使用带时区 RFC 3339（例如 `2026-10-15T10:30:00+08:00`）。
- Task ID `t-`、Note ID `n-`、Activity ID `a-` 后使用现有小写 ULID；各 ID 在 Vault 中稳定、全局不重复，不依赖文件路径、行号、内容或事件时间。DayPlan 以 `date` 标识。
- 标签是无层级的自由字符串列表；内部不带 `#`，大小写不敏感的查找与聚合规则不变。
- Frontmatter 与 Activity 元数据使用 YAML；解析拒绝缺失/非法必填值；合法未知 YAML 字段应保留，避免保存其他字段时破坏原内容。
- Task 和 DayPlan Markdown 是**内部存储协议**，用户通过 GUI 操作；未来 CLI 如实现也由同一个 App Core 写入。Note 是面向用户编辑的 Markdown。
- 数据源只有 Markdown 文件，索引可重建；不引入 JSON 侧车、数据库、跨文件事务/WAL。

## 目录

~~~text
vault/
  tasks/                         # 每 Task 一个 Markdown，Activity 内嵌
  notes/                         # 每 Note 一个 Markdown，可有子目录
  plans/YYYY-MM-DD.md            # 每日期一个 DayPlan，独立 Activity 内嵌
  files/                         # 原始 PDF、Office、图片等，无 Frontmatter
  .pata/                         # 内部状态，可重建；不保存唯一业务数据
~~~

`memos/YYYY/MM/*.md` 不再是新版本的业务写入路径。因目前仅为测试期，不做自动兼容迁移；现存文件不得被程序静默删除。`plans/` 是真实业务数据，不是可丢弃缓存。当前应用仍可能使用旧 `.pata/plans/`；阶段 8 尚未实施，目标直接采用根 `plans/`，不得静默删掉旧测试资料。阶段 9 实现专属目录扫描与文件资源引用。

## Task

~~~markdown
---
type: task
id: t-01m4xxx
title: 优化啪嗒编辑器
description: |-
  优化编辑器交互体验。
  方案参见 [[编辑器设计方案]]。
status: todo
completed_at: null
due: null
tags: [Pata]
note_ids: []                        # 可选，显式 Note 关联
note_refs:                          # 可选，仅绑定 description 内的 [[名称]]
  编辑器设计方案: n-001
created_at: 2026-10-15T09:00:00+08:00
updated_at: 2026-10-15T09:30:00+08:00
status_events: []                   # 可选：completed / reopened
---

<!-- pata:activity
id: a-01m4xxx
at: 2026-10-15T10:30:00+08:00
tags: [设计]
note_refs:
  技术方案: n-002
-->
完成基础设计，参考 [[技术方案]]。
<!-- /pata:activity -->
~~~

### Task 字段与行为

- `description` 位于 **Frontmatter**，是纯文本，支持换行及唯一识别的 `[[笔记引用]]`；不渲染其他 Markdown 语法。Task 的 Body **只**包含 Activity 块，不再存储描述。
- `note_refs` 属于 Task **描述自身**，名称绑定到 Note ID；不得用于代替 Activity 内部的 `note_refs`。
- `status` 仅 `todo` / `done`，无优先级、多状态流。完成时记录 `completed_at`，重新打开清空当前完成时间；`status_events` 保留完成/重开历史。
- `due` 是截止日期，与各个 DayPlan 的 `task_ids` 完全独立。
- `note_ids` 作为既有显式 Note 关联继续保留，不新增从描述直接关联的重复入口。
- Task 文件由当前实现的 slug + `t-` ID 命名；文件重命名不影响引用。

## DayPlan（Today 日期文件）

~~~markdown
---
type: day_plan
date: 2026-10-15
task_ids:
  - t-01m4xxx
---

<!-- pata:activity
id: a-01m4yyy
at: 2026-10-15T11:30:00+08:00
tags: [调研]
note_refs:
  编辑器设计方案: n-001
-->
今天研究了 [[编辑器设计方案]]。
<!-- /pata:activity -->
~~~

- Frontmatter 保存日期和**有序**任务引用；同一天不能重复同一个 Task ID，同一 Task 可以出现在多个日期。
- Body 保存**本日期拥有的独立 Activity**，与 Task Activity 格式完全一致，无 `task_id`、`entry` 或 `memo` 区分字段。
- 当 `task_ids` 变动或为空时，仍必须原样保留 Body；反过来修改日期 Activity 也不得改变任务安排。
- 在 Today 某个历史日期创建独立 Activity 时，`at` 的工作日应对应用户所选日期，而非无条件使用操作发生当天。
- Task Activity 只存 Task 文件。Today 时间线从内存索引聚合两类 Activity，按 Activity 的 `at` 本地日期显示，与 Task due、该任务在哪天被安排无关；原有完成/重开事件继续显示。
- 即使没有计划任务，只要有独立 Activity，该日期文件也必须保留。

## Activity 内嵌块协议

~~~markdown
<!-- pata:activity
id: a-01m4zzz
at: 2026-10-15T14:20:00+08:00
tags: [Pata, 设计]
note_refs:
  编辑器设计方案: n-001
-->
发现快捷键冲突，需要参考 [[编辑器设计方案]]。

继续排查焦点处理。
<!-- /pata:activity -->
~~~

### 元数据

| 字段 | 必填 | 解释 |
|---|---|---|
| `id` | 是 | 全局唯一、稳定的 `a-` + ULID |
| `at` | 是 | RFC 3339 带时区事件时间 |
| `tags` | 否 | 此 Activity 自有标签列表；省略表示无自有标签 |
| `note_refs` | 否 | **本 Activity 局部**的 `[[名称]] -> Note ID` 绑定；不得和同文件其他 Activity 或 Task 描述合并 |

正文保留纯文本多行内容与 `[[笔记]]`；不用 Markdown 标题、行号或日期推断边界。UI 的编辑体验不变。

### 解析和格式不变量

1. 开始标记 `<!-- pata:activity`、元数据结束标记 `-->`、块结束标记 `<!-- /pata:activity -->` 各占独立完整行；开始到元数据结束之间用 YAML 解析，正文一直延伸到所属结束标记。
2. 不允许块嵌套、缺少结束、重复 ID、非法 `at`、缺少 `id` 或无效 YAML；错误需要包含文件路径和具体原因。空的合法可选元数据允许省略。
3. 写入方必须避免正文里出现完整保留定界行后导致误解析；可采取可逆转义或写入前明确拒绝，但绝不静默截断文本。实现前须以单测固定方案。
4. 解析和序列化的往返必须保留正文内容、Note 绑定、标签、活动顺序及合法未知元数据；同文件更新一个块不能覆盖其他块。
5. 单个 Task/DayPlan 含损坏块时，**停止对此文件的结构化写入**，不自动删内容或“修复”原文件；隔离到单文件，其他文件继续使用。文件经外部修复并重扫后恢复。
6. 内存索引应维护从 Activity ID 到 owner（Task ID 或日期）、实际文件路径的定位关系；文件更改重索引时先失效该文件全部旧 Activity，避免悬空缓存。
7. 在 Task/DayPlan 写入过程中按文件串行化并基于最新内容修改；单文件复用原子替换与 hash/baseline 检查，不实现跨文件事务。

## 标签规则

- Task Activity：`effectiveTags = activity.tags ∪ task.tags`，Task 标签继承**只在索引/查询时动态计算**，不反写入每条 Activity。
- Today Activity：`effectiveTags = activity.tags`，可无标签。
- 同一标签查找和概览保持现有大小写不敏感逻辑；同一 Activity 在一个标签下只计一次。
- 不因存储协议调整而新增标签管理 UI。

## Note 与 `[[笔记引用]]`

- Task 的 `description`、每条 Activity 的正文中，`[[名称]]` 仅表示 Note 引用；阶段 9 的文件候选由同一个 `[[` 选择入口插入**标准 Markdown 文件链接**，不将文件编码为 `[[文件名]]`，也不为其新增 ID 绑定。其余内容保持纯文本。
- 已通过 `note_refs` 绑定的名称只解析到绑定的真实 Note ID；失效不按同名新 Note 自动接管。未绑定的 `[[名称]]` 只有在标题唯一匹配时才解析；`\[[名称]]` 是转义字面量。
- 同一作用域中如存在同名不同 Note，使用 `名称 (相对路径)` 区分；`note_refs` 仅保留实际出现的名称。
- Note 自身仍保存标准 Markdown 相对链接，Notes WYSIWYG/IR 输入、补全和点击行为不变。
- “被引用”结果按来源 Note / Task ID 去重；Task 描述与 Task 下多个 Activity 指向同一 Note 时只算一个 Task 来源；Today 独立 Activity 可跳转引用，当前阶段不引入新的独立来源类型。

## Note

~~~markdown
---
type: note
id: n-001
title: 编辑器设计方案
tags: [Pata]
audio_file: files/recording.mp3      # 可选：主录音关联（相对 Vault 根路径）
audio_transcript: true               # 可选：标记为自动生成的只读逐字稿 Note
created_at: 2026-10-15T09:00:00+08:00
updated_at: 2026-10-15T09:20:00+08:00
---

# 编辑器设计方案

正常 Markdown 正文，包括相对链接与其他格式。
~~~

### 自动生成的只读逐字稿 Note（阶段 11 规范）

- 当且仅当 Note Frontmatter 包含 `audio_transcript: true` 且设置了有效的 `audio_file`（如 `files/sample.mp3`）时，该 Note 被识别为自动生成的逐字稿 Note。
- **只读正文边界**：在 Pata 内，此类 Note 的正文只读（不可直接在编辑器中键入、粘贴或插入附件，但允许文本选择、复制、检索与时间戳跳转）；标题 `title` 与标签 `tags` 仍可自由编辑与保存。普通手写 Note（即便正文包含 MP3 附件链接）不设 `audio_transcript: true`，保持现有完整编辑能力。
- **逐字稿排版与时间戳链接**：正文不重复插入 `# 标题`，按识别句子段落组织。时间戳采用标准 Markdown 锚点链接语法 `[HH:MM:SS.mmm](#t=HH:MM:SS.mmm)`，时间为音频起点毫秒时间戳，点击可跳转播放；发言人格式为统一的「说话人 1/2…」：

~~~markdown
[00:01:05.230](#t=00:01:05.230) 说话人 1

我们先讨论一下这次技术架构的调整。

[00:01:18.760](#t=00:01:18.760) 说话人 2

我觉得可以先把现有的方案简化一下。
~~~

普通 Markdown 无 Frontmatter 仍遵循既有 Note 推断和保护规则。普通 Note 的内容与编辑器不因本阶段发生 Schema 迁移。

## 删除与异常一致性

1. 通过 GUI 正常删除 Task 时，**任务文件内全部 Activity 随任务文件删除**；删除确认需要说明这一后果。
2. 同步清理所有日期文件 `task_ids` 中的被删 Task；只改该属性，不影响 Activity、其他日期安排、Task Due、Notes。
3. 不做跨文件事务或 WAL。清理失败时，Task 文件删除本身不被伪装回滚；遗留任务引用读取时忽略、健康检查可解释，并允许后续**幂等**清理。
4. 外部删除/改写也可能造成无效引用；这类可恢复引用问题不应让整个 Vault 进入不可用的降级状态。
5. 解析错误、重复 ID 等会危及结构化读写的情况按文件隔离；绝不自动覆盖/删除不可解析的原始 Markdown。
6. 索引、搜索和页面缓存都可从有效 Markdown 重建，根 `plans/` 以及 Task/Note 文件则必须保存；阶段 9 的原始 `files/` 同样必须保存。

## Vault 与文件资源引用（阶段 9 目标，未实施）

- Vault 的业务扫描范围仅为 `notes/**`（Note）、`tasks/**`（Task）、`plans/`（DayPlan）与 `files/**`（文件资源）；Vault 根目录、`.pata/` 等位置不递归当作 Note 来源。
- `files/**` 里的 PDF、PPT、Word、图片等是普通原始文件，**没有** `type: file`、File ID、`file_refs`、包装 Note 或 JSON 侧车。一个文件可以被多个来源引用，也可以零引用。
- 阶段 9 的 `[[` 候选同时允许选择已有 Note 与已有文件，但两者保存规则**不同**：Note 遵守本文件既有 Note ID/相对链接机制；文件使用标准 Markdown 相对路径链接，如 `[晋升答辩.pptx](../files/晋升答辩.pptx)`，路径从实际宿主 Task/DayPlan/Note 文件位置计算。带空格、括号等路径字符需按 Markdown URL 规则转义。
- Task/Activity 是纯文本，仅额外识别并以可点击项展示有效**文件链接**；不因文件引用而解释其它 Markdown 语法。Note 则按原有 Markdown 编辑/渲染规则工作。
- 文件的搜索身份为 Vault 内当前路径与文件名；不承诺外部重命名自动修复。路径失效保留原文并提示，不重绑定猜测文件；解析路径必须限制在 Vault 内，禁止 `../`/符号链接逃逸。
- 删除 Note/Task/Activity/文件链接时**不级联删除** `files/` 资源；不设自动清理。文件导入复制且不覆盖同名文件，首次导入生成新链接、再次从候选选择已有文件只生成链接。
- 本节仅定义阶段 9 的未来行为，不表示当前 Go Core 已实现。

## 与 V1 的关系

旧版 `Memo` 是独立 `type: memo` Markdown 文件，`task_id` 仅表示关联；Task Body 曾是描述。本阶段改变这两条基本规则。当前处于测试期，不要求为旧 Memo 实现持续兼容、自动升级或完整迁移，但禁止静默删除旧文件；应先备份测试 Vault，再由实施过程明确清理或重建测试资料。V1 的历史实现、测试固件与阶段 2/3 文档不构成对本目标 Schema 的覆盖。

更多实施步骤与验收见 [阶段 8 Proposal](../08-activity-storage/proposal.md)。
