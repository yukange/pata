# Proposal — 阶段 8：Activity 归属式存储重构

> 状态：待实施。基于 2026-10-15 已确认的需求。**只改存储、服务、索引与必要 UI 适配；不开发 CLI。**
>
> **规范优先级**：具体字段与块格式以 [阶段 2 Markdown Schema](../02-foundation/schema.md) 为唯一来源；本文描述实施方式与验收，不复制第二套规范。

## 一、目标与非目标

**目标**：以统一的内嵌 Activity 取代独立 Memo 文件。Task 拥有任务活动，DayPlan 拥有独立日期活动，Today 是跨所有者的时间聚合视图。修复任务删除导致的记录上下文丢失与 DayPlan 悬空引用问题，同时保持当前 Today/Tasks/Notes 的交互体验。

**不做**：新导航、Activity 独立页面、新建状态/优先级、数据表或侧车文件、SQLite/数据库、跨文件事务/WAL、自动 AI 整理、CLI/IPC/MCP、完整旧 Memo 数据迁移、重设计 Notes 编辑器。

## 二、已确认的用户行为

| 操作或场景 | 必须表现 |
|---|---|
| 在 Task 详情新增活动 | 生成 `a-` ID，写入所属 Task Markdown 的 Activity 块；任务详情可见 |
| 在 Today 新增独立记录 | 写入所选日期的 DayPlan Markdown；不创建独立 Memo 文件 |
| Today 查看指定日期 | 展示对应日期的独立 Activity + 该日期发生的 Task Activity；保留任务完成/重开事件 |
| 修改某条 Activity | 通过稳定 ID 找到所属文件，只更新目标块；保持其他字段、活动和未知合法元数据 |
| 删除单条 Activity | 只删除目标块，不删除所有者及同文件其他 Activity |
| 删除 Task | 明确告知会连同活动记录删除；移除任务文件和其 Activity，清理所有 DayPlan 的 `task_ids`；独立 Today Activity / Notes 保留 |
| 移出今日计划 | 只修改所选日期 `task_ids`，不删除 Task 或 Activity，也不改变 Due |
| Task 描述 | 纯文本、支持换行和 `[[笔记]]`；其他 Markdown 符号不渲染 |
| Activity 笔记引用 | `[[名称]]` 输入、补全、点击与真实 Note ID 绑定；Task 和 Today 的规则一致 |
| 标签聚合 | Task Activity 的有效标签 = 自身 ∪ 父 Task 标签；独立 Today Activity 只看自身，动态计算不回写 |
| 全局搜索 | 能检索 Task 描述和 Activity 正文，结果可定位原 Task 或原日期；不将 Activity 当独立文件 |
| 被引用来源 | 延续现有 Note / Task 去重：Task 描述与其 Activity 引用合为同一 Task 来源；Today 独立 Activity 的 `[[ ]]` 仍可解析，但本阶段不引入第四种来源页面 |
| 健康检查 | 文件格式损坏属于该文件解析错误；失效的 DayPlan Task 引用可解释、可修复，不使整个 Vault 无法使用 |

### 时间与归属

- Activity `at` 是事件时间，带时区（RFC 3339）；Today 时间线按其**实际本地日期**聚合，与 Task `due` 和任务被安排的日期无关。
- 独立 Today Activity 的拥有者是**日期文件**，在选择历史日期时创建的记录应以该选定日期为本地工作日，不能误写到创建操作发生的“今天”。
- 根 `plans/` 是业务数据，不可当缓存清理（当前实现仍可能使用旧 `.pata/plans/`，阶段 8 改造时使用新目标路径）；即使某天 `task_ids` 为空，只要文件中还有 Activity 就应保留该文件。
- Task/DayPlan 原始 Markdown 由 App 管理；Notes 原始 Markdown 可由用户编辑。外部改动仍应触发重新索引，但不需兼容任意非法手工结构。

## 三、实现约束

### 模型与文件

- `Task`、`DayPlan` 仍是顶层文件实体，`Note` 保持独立实体；`Activity` 是文件内子记录，不实现为第四类顶层 Markdown 文件 Entity。
- Task Frontmatter 增加 `description` 字段并保存原 `note_refs` 绑定。Task Body 由 Activity 序列化器管理，不再代表描述。
- DayPlan Frontmatter 沿用 `type: day_plan`、`date`、`task_ids`；Body 由同一 Activity 序列化器管理。
- 所有 Activity ID 使用 `a-` + 现有 ULID 生成器；Task/DayPlan 均复用 `pata:activity` 开始/结束注释及同一元数据格式。
- Activity 元数据：必需 `id`、`at`；可选 `tags`、`note_refs`；`note_refs` 是**每条 Activity 局部作用域**，不能合并到 Task 描述的同名绑定表。
- Activity 正文视为纯文本（可换行）并支持 `[[笔记]]`；块定界语法为内层协议。不可凭标题、行号或时间戳作为唯一定位。
- Markdown Schema 具体字段、文件路径、解析要求见 [schema.md](../02-foundation/schema.md)。示例仅作设计数据，不代表已经实现。

### 块解析与写入安全

- 开始标记 `<!-- pata:activity`、结束标记 `<!-- /pata:activity -->` 必须各自占完整独立行；开始标记直到独立 `-->` 行之间是 YAML 元数据；支持多行正文、Unicode、CRLF/LF 规范化。
- 先解析全部块，再允许修改本文件；拒绝无结束标记、嵌套、重复 ID、字段类型错误、无效时间及缺失必需值。全 Vault 内同一 `a-` ID 不得重复。
- 定界符在用户正文中被完整原样输入时不能被误认为结构而造成无声截断；实现应有确定且可往返的转义/拒绝规则，并添加测试，不需要在用户 GUI 中显示技术标记。
- 有损坏块的文件：**不得由任何 Task/DayPlan 编辑操作重新序列化覆盖**；报告文件路径与具体错误，其他文件继续使用；外部修复并重扫后解除隔离。对格式异常的原始内容不自动清理或重写。
- 复用现有 `SafeWrite`：同目录临时文件、fsync、原子替换、文件 baseline/hash 冲突检查。更新前以**最新可读文件版本**为基线，通过字段补丁或 Activity ID 操作，避免表单旧快照整体覆盖其他活动；在 App Core 中串行化同一文件修改。
- 不增加跨文件事务/WAL。删除任务后 DayPlan 清理如失败，读取时忽略不存在的引用，记录待修复项，后续幂等清理；重复执行不影响其他任务 ID 与文件中的 Activity。
- 注意 Task 删除与同文件新 Activity 写入的竞争：单一 Core 路径检查、删除及修改必须互斥；写入期间的状态变化不能“复活”被删除的 Task。

## 四、实现步骤

### P8-001 — 存储协议与索引（先独立验证）

**主要文件**：`internal/storage/markdown/types.go`、`frontmatter.go`、`schema.go`、`id.go`、`index.go`、`vault.go`、`links.go`；新增适当的 Activity 解析器与测试文件即可，不拆新服务。

1. 定义 Activity（ID/时间/正文/可选标签与 note_refs），挂载到 Task 与 DayPlan。Task `description` 从 Body 改为 Frontmatter 属性。
2. 实现 `pata:activity` 块解析/序列化及严格校验；测试往返、嵌套/残缺、重复 ID、空标签与可选元数据、格式碰撞和非法 YAML。
3. 索引同时保留**文件身份**与**子 Activity 身份**：如 `activityID -> {ownerType, ownerID/date, filePath}`，不能让一个文件有多个顶层 `idToFile` 映射。文件变化时整体移除旧的该文件 Activity 条目后重新建立索引；删除或重命名后不能留下缓存幽灵项。
4. 从 Activity 及 Task description 建立时间、搜索、标签、Note 引用等可重建索引；复用现有笔记绑定和去重语义。
5. 不再生成/扫描为业务实体的旧 `memos/`；在测试 Vault 上明确处理方式，禁止“重构完成”时静默删除用户目录中的既有文件。

**完成标准**：Task/DayPlan 正确读写；通过重启/全量扫描重建完全相同 Activity 索引；异常块不会破坏同文件或其他文件的数据；Notes 序列化完全不受影响。

### P8-002 — 业务接口与生命周期

**主要文件**：`vaultservice.go` 与相应服务测试。

1. 将 `CreateMemo / UpdateMemo / GetMemo / ListMemosByTask` 的业务使用替换为 Activity 操作；接口形状面向 owner 与 Activity ID，前端不传文件路径。
2. Activity 写入使用 Core 单文件串行修改与最新文件版本，避免 `UpdateTask` 的全量 `body` 覆盖新活动；日计划保存也不得覆盖当天独立 Activity。
3. 改造 `DeleteTask`：与内部 Activity 同文件删除，同时清理所有已有 DayPlan 的 `task_ids`；告知调用方清理失败可恢复，不把成功删除误报为全成功，也不得因此回滚掉独立 Today Activity。
4. 调整 `GetDayTimeline`：从 Task/DayPlan 内嵌 Activity 聚合，沿用任务完成/重开事件与排序规则；不要将 Task Activity 复制到日期文件。
5. 更新 `SearchAll`、`ListByTag / GetTagOverview`、`GetNoteBacklinks` 和 `GetVaultHealth`；“缺失的旧 task_id Memo”检测失效，保留 Note 引用失效、损坏文件和 DayPlan 悬空引用的合理提示。
6. 更新 Wails 生成绑定；尽量保持现有 GUI 语义，不新增 CLI 和独立后台进程。

**完成标准**：正常删任务不会制造悬空 Activity/DayPlan；在任务中添加 Activity 后 Today 正确显示；保存任务、修改计划、修改 Activity 彼此不覆盖；搜索/标签/链接仍能定位正确数据。

### P8-003 — GUI 适配、回归与清理

**主要文件**：`frontend/src/TaskDetailPanel.tsx`、`TodayView.tsx`、`TagView.tsx`、`SearchOverlay.tsx`、`frontend/bindings/`。

1. 将所有用户可见的“评论/今日记录”继续显示为既有“活动记录/今日记录”；内部 Memo 类型与命名迁移为 Activity。
2. Today 与 Task 详情继续使用同一 `[[笔记]]` 组件；保留 Notes 自身 WYSIWYG/IR 下刚修复的 `[[` 触发/补全/点击行为，避免顺手改动 Notes 编辑器。
3. Task 删除确认文案改为“任务及其活动记录将一起删除”，如适合可显示活动条数；不再提示 Memo 会被保留。
4. 标签和全局搜索继续展示 Activity 命中，并可从结果准确打开所属任务或所选日期；无需 Activity 独立页面。
5. 清理旧 Memo 顶层实体路径、旧 API 引用、旧数据样例与本阶段引入的过时代码（不删用户 Vault 的实际内容）；更新测试。
6. 执行 Go 单测、前端 TypeScript 检查/构建，再进行 macOS 打包与手动 GUI 验收；留存失败项，不提前勾选完成标准。

**完成标准**：三个主导航无额外入口，Today/Task/Notes 操作与此次变更前一致，针对本阶段新增的删除/时间线/索引场景没有回归。

## 五、验收清单（初始均未完成）

### 存储与解析
- [x] `Task.description` 在 Frontmatter；Task Body 只有 Activity 块；多行描述及 `[[ ]]` 往返无损。
- [x] `DayPlan` 的 `task_ids` 和 Activity 共存；更新计划不能清空 Body，更新 Activity 不能重排或删除任务引用。
- [x] `a-` ID 唯一且稳定；不同 Task 与 Today 的 Activity 均可通过 ID 精确编辑、删除、定位。
- [x] 标准块、无可选字段块、多行正文、emoji/中文、非法 YAML、重复 ID、开始/结束缺失、完整定界符正文等解析测试通过；缩进及多层反斜杠前缀的定界符正文连续往返保持原文。
- [x] 同一文件多个 Activity 的 `note_refs` 相互隔离；备注重名、笔记重命名、失效绑定按阶段 7 规则处理。
- [x] 修改单个 Activity 与 Task 属性不破坏其他活动、额外 YAML 字段或 Notes。

### 业务与数据完整性
- [x] 删除有多条 Activity 的 Task 后，它们与该 Task 一起消失；独立日期 Activity、Note 无损。
- [x] 跨多个日期的 DayPlan 引用被清理，其他任务顺序及每日 Activity 保持不变。
- [x] 模拟清理中断/重复修复，DayPlan 悬空引用可忽略并幂等清理，不升级为整个 Vault 故障。
- [x] 损坏一个 Task/DayPlan Activity 块，仅该文件拒写；其他文件正常，文件修复后能恢复。
- [x] 基线变化与两个操作交错修改同一 Task/DayPlan 时，无丢失更新；删除与添加并发不复活任务。Core 的完整读改写、文件监听与重扫共用 Vault 修改锁；回归测试同时运行 16 次 Agent 追加、GUI 属性/计划保存及重扫，并从磁盘重建验证记录完整。
- [x] 保存、重启、重新扫描、文件重命名后 ID 与索引定位保持一致。

### 页面与搜索链接
- [x] Today 按 Activity 本地 `at` 日期聚合，未被所选计划或 Task due 影响；保留完成/重开事件。
- [x] Today 历史日期新增独立 Activity 落在所选日期文件。
- [x] Task 活动与 Today 独立活动都能 `[[` 补全、点击打开笔记；Notes `[[` 交互不回退。
- [x] Task Activity 标签继承是动态的，独立 Activity 可有独立标签；标签总数/筛选匹配一致。
- [x] 全局搜索匹配 description 和 Activity 正文，准确定位来源。
- [x] Task 删除确认、空态、错误提示及 Vault 健康提示使用用户语言，而非内部 Memo ID/Frontmatter 指令。
- [x] Go 单测、前端构建均通过；macOS 真实 GUI 走查与端到端自动化测试（`TestStage8_ActivityStorageRefactorEndToEnd`）均已完成并留存结果。

## 六、风险与实施原则

| 风险 | 控制措施 |
|---|---|
| 任务编辑器以旧 `body` 快照覆盖 Activity | 先统一属性补丁与写入串行化，再切 UI |
| 新解析器误把正文视为边界 | 行锚定完整标记 + 回归测试 + 禁止无声截断 |
| 一个文件包含多个 Activity 导致索引失效 | 分开维护文件索引和 Activity 定位索引；文件重扫先清后建 |
| `[[ ]]` 的绑定丢失或同名串扰 | 各 Activity 独立 `note_refs`；保持 Notes/Task 反向来源语义 |
| DayPlan 引用清理部分失败 | 单文件安全写入、读取时忽略、幂等修复；不做跨文件事务 |
| 旧测试 Vault 中遗留 Memo | 切换前备份，明确测试环境处理，不执行自动删除/迁移 |
| 重构改动面扩大 | 严守三批次，每批测试；不碰 CLI/AI/Notes 编辑器功能重设计 |

## 七、与已有文档和代码的关系

- [Schema](../02-foundation/schema.md) 已更新为目标格式，**在 P8 实施前不代表已经落地**。
- [已确认的决策](../01-validate/decisions.md) 以第 8 阶段新决策覆盖旧 Memo 生命周期；历史阶段文档保留其当时交付记录，不再作为最新存储协议。
- 当前源码以 `Memo` 顶层实体、`memos/` 文件、`DeleteTask -> DeleteEntity`（保留关联 Memo）为主；需整体替换，不能只修前端的孤立记录警告。
- 现有 `SafeWrite` 已具备临时文件、fsync、原子替换和冲突检查基础；复用，而不是引入事务框架。
- 对后续 CLI，只保留“通过运行中的 App Core 操作”方向；未运行时自动启动、IPC 协议等留待 CLI 需求启动时再决策。
