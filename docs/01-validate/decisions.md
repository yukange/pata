# Decisions — 已确认的选择与变更边界

| ID | 决策 | 理由 / 后果 |
|---|---|---|
| D01 | 只有 Today / Tasks / Notes 三个主入口 | 入口围绕使用目的，而不是数据实体数量 |
| D02 | Activity 不独立设导航 | Task 活动和 Today 独立记录统一称 Activity；各自按拥有者存储，只有 Today / Tasks / Notes 三主入口；旧 Memo 独立存储由 D30 覆盖 |
| D03 | Log 是按时间查看信息的方式，不是第四种内容 | 避免额外维护与 Activity 重复的日志实体 |
| D04 | Today 的 DayPlan 与 Task 的 Due 严格分离 | 计划推进 ≠ 必须完成；同任务可多日安排 |
| D05 | 历史 DayPlan 保留；昨日未完不自动搬到今日 | 复盘真实，今日列表不膨胀 |
| D06 | 无 Inbox、Projects、Areas | 一个全量任务池 + 可选全局标签已经足够 |
| D07 | 标签是全局聚合视图 | 同一主题查 Task、Note、Activity；不因进入点改变语义 |
| D08 | Task 内 Activity 按其 Task 标签动态参与过滤 | 不重复保存父 Task 标签；自身标签与父 Task 标签取并集，Task 标签变化后自动更新聚合；Today 独立 Activity 仅用自身标签 |
| D09 | Notes 借鉴 Flomo 单列卡片浏览；打开后独占主内容区 | 不采用文件树 + 列表 + 编辑器三列 |
| D10 | 编辑器首选 Vditor；Frontmatter 由 Go Core 管理 | 编辑正文与结构化元数据隔离 |
| D11 | 数据源为本地 Markdown；初期无 SQLite | Note 仍可直接编辑 Markdown；Task/Today 的 Markdown 是内部持久化协议，推荐通过 App GUI（未来可经 CLI）操作；不需要引入数据库 |
| D12 | MVP 不实现 CLI/内置 AI；本机 MCP 见 D47，未来 CLI 与 GUI 共用 App Core | 不以 Pi Agent 直接手改 Task/DayPlan Markdown 为官方编辑方式；CLI 可以依赖运行中的 App；IPC、自动启动、命令细节都留到未来阶段，不纳入阶段 8 |
| D13 | 周/月复盘是 Note，不是功能模块 | 利用已有记录、由人或外部 Agent 生成 |
| D14 | macOS MVP；Go + Wails v3 + React/TS | 小型本地应用，工程兼容性仍需 Spike |
| D15 | 「啪嗒 / Pata」为正式产品名称 | 同名冲突和商标尚未核查 |
| D16 | `docs/` 仅以实现阶段划分目录 | 每个阶段固定 `idea.md` 和 `proposal.md`，必要资料就近维护 |
| D17 | Pata 以 macOS 27 HIG 为视觉目标，借鉴 Magpie 原生窗口实现 | 保留 Wails/Go/React；原生交通灯与标题栏优先，Liquid Glass 是可回退增强，禁止整页玻璃化 |
| D18 | 单 Vault，不支持多 Vault | 一个用户一个本地目录；无切换/工作区概念，应用状态与索引绑定唯一根路径 |
| D19 | Notes 编辑器自动保存（防抖落盘），冲突时停止并提示；Tasks/Activity 沿用已验收的既有保存交互 | Notes 与业务文件编辑职责分离；不静默合并、不覆盖竞争写入；统一 Go Core 的最新文件补丁写入、单文件原子替换 |
| D20 | 标签匹配与聚合分组均大小写不敏感（EqualFold / ToLower 分组），聚合显示保留首次出现的原始形式，存储不改写 | 对齐既有 `FindByTag` 语义，保证标签概览计数与点击筛选结果一致；schema 未规定大小写策略，此处定夺（阶段 5 P5-R1 审查项） |
| D21 | 品牌以白色翻折顶层 + 橙黄色中层 + 粉紫色底层 + 三道黄色光芒的 V2 资源为基线；阶段 6 已实现代码，待实机验收 | [资源与动画方案](../06-branding/proposal.md)；静态品牌、启动/成功动画、静态菜单栏已接入；菜单栏逐帧动画与额外悬停动效取消，不新增导航、不改变关窗退出行为 |
| D22 | Today / Tasks 快速创建仅提取末尾连续的 `#标签`，标题在前、标签在后；共用解析与全局标签建议 | 用户在 [Today 讨论](chatgpt-conversation://6acde6d4-264c-83e9-95ef-86aca343d135) 中明确确认；中间标签保留原文，新名称随 Task.tags 落盘，无独立 Label 实体；[阶段 3 规则与验收](../03-daily-loop/proposal.md#共用快速创建与末尾标签) |
| D23 | 用户明确采用类似 ChatGPT 的三栏：左导航 / 中间 Today 或 Tasks / 右任务详情；右栏按需打开，共用详情组件，中间内容保持可见、可操作 | 中间与右栏独立滚动，关闭右栏恢复中间宽度与上下文；窄窗口允许收起导航或覆盖主区域并返回；Notes 仍单列浏览、全主区域编辑；布局须实机验收，见 [阶段 3 方案](../03-daily-loop/proposal.md#共用任务详情与行内操作) |
| D24 | 移除任务优先级，以当日计划顺序表达推进次序；移出计划只取消对应日期安排 | 不删除 Task、Task 的 Activity、其他日期计划或历史状态事件；状态操作保留即时提交体验 |
| D25 | Task 描述纯文本，允许换行及 `[[笔记]]`，不解析其他 Markdown；Notes 仍是 Markdown 编辑器 | 阶段 8 将 Task `description` 放入 Frontmatter，Body 专用于 Activity；此前正文描述方案由 D31 覆盖 |
| D26 | Notes、Task 描述、Task/Today 的 Activity 使用已有 `[[` 选择、点击与笔记绑定 | 保持现有 Note 编辑器已修复的 `[[` 补全与跳转；引用已存在的笔记，不自动创建或新增关联管理页面 |
| D27 | 被引用来源动态计算，按 Note/Task 身份去重 | Task 描述及其 Activity 归为同一 Task 来源；Today 独立 Activity 能引用和跳转 Note，但阶段 8 不增加独立来源类型或第四入口 |
| D28 | Note 正文使用标准相对 Markdown 链接；Task 描述/Activity 用 `[[名称]]` + 真实 Note ID 绑定 | Task 的描述 `note_refs` 与每条 Activity 局部 `note_refs` 不能混用；**已绑定 ID 失效时必须直接提示，不能按同名标题回退**；相关唯一规范见 [Schema](../02-foundation/schema.md) |
| D29 | 极简任务模型（方案 A）：任务仅有未完成 (`todo`) 和已完成 (`done`) 两态，通过勾选直接切换；标签完全自由，不赋予系统级状态语义；通过 `completed_at` 记录完成时间用于 Today 统计与历史回顾；不再提供 `doing`（进行中）、等待中、已阻塞等内置状态 | 践行 Less is More / Record Once；中间推进状态由当日计划顺序与时间线自然呈现，无须繁琐的状态流转维护；存量 `doing` 状态平滑兼容规整为未完成 |
| D30 | Task Activity / Today Activity 使用同一 Activity 模型而非独立 Memo 文件 | Task Activity 存所属 Task Body；独立 Today Activity 存 `.pata/plans/YYYY-MM-DD.md` Body，Today 时间线聚合展示，避免失去上下文的幽灵记录 |
| D31 | Task 的属性和纯文本 `description` 均保存于 Frontmatter，Body 仅存内嵌 Activity | 任务删除自然携带内部 Activity；Notes Markdown 不受影响，`[[笔记引用]]` 继续工作 |
| D32 | 每条 Activity 采用 `a-` + ULID，HTML Comment 成对边界和 YAML 元数据 | `id`、带时区 `at` 必填；`tags`、局部 `note_refs` 可选；通过 ID 精确增删改，不依赖标题/时间/行号 |
| D33 | 删除 Task 连同 Activity 删除、清理 DayPlan 中任务 ID；轻量最终一致性 | 单文件原子写入、文件级串行写与最新内容补丁；DayPlan 清理失败可幂等修复，普通悬空引用不令 Vault 整体不可用；不引入 WAL/跨文件事务 |
| D34 | Task/Today Activity 可选独立标签且延续 `[[Note]]` 引用；异常块严格解析、保守写入 | Task Activity 动态继承 Task 标签；Today Activity 仅用自身标签；损坏文件禁止回写，其他文件继续使用；不自动清除用户原始数据 |
| D35 | 阶段 8 是存储/业务改造而非新 CLI 功能 | 初期无需要迁移的正式旧数据；允许直接转新模型但不能静默清理旧文件；未来 GUI/CLI 共用运行中的 App Core，CLI 细节延后 |
| D36 | 阶段 6/7 按 Less is more 收敛后续开发范围 | 06 代码完成、只待 macOS 验收；取消菜单栏逐帧动画及额外悬停动效。07 主体完成，唯一必修项是已绑定 Note ID 失效后不得按标题猜目标；轻量恢复来源页面/日期仅可选且不阻塞阶段 8。**不做**外部移动后的跨文件自动重写、批量更新/重试、精确滚动/光标还原和旧 Memo 全量迁移；Note 相对路径失效时保留原文并提示修复，见 [阶段 7](../07-note-links/proposal.md)。 |

| D37 | 单一 Vault 是啪嗒专属数据空间，仅管理约定业务目录；DayPlan 目标位置为根 `plans/` | `notes/`、`tasks/`、`plans/` 为 Markdown 用户数据，`files/` 为原始资源；`.pata/` 只承载内部状态；不递归接管任意 Markdown。阶段 8 尚未编码，直接用目标路径避免二次迁移 |
| D38 | 文件在存储上独立，在交互上通过 Activity/Note 引用；不设 File 业务实体、Files 页面或包装 Note | 允许一份 PPT/PDF 被多处引用，也允许暂时零引用；文件本身保持原格式 |
| D39 | 拖入/粘贴文件时复制到 `files/`，自动插入标准 Markdown 相对链接；再次选已有文件只插入引用 | 不移动外部源文件、不覆盖同名已有文件、不引入 File ID 或 file_refs；链接相对真实宿主文件计算 |
| D40 | 现有 `[[` 补全扩展为 Note 与 File 的统一选择入口 | Note 仍用稳定 ID 绑定（Task/Activity）和现有 Note Markdown 链接；File 使用路径引用，Task/Activity 仍是纯文本、仅文件链接可点击，不引入通用 Resource ID |
| D41 | 全局搜索可以通过文件名直接命中 `files/` 中的资源，即使没有任何引用 | 文件结果点击原生预览；既有记录仍按正文可检索；不做 PDF/Office 内容全文索引或额外文件页 |
| D42 | 不实施文件自动清理、引用计数、inode/Bookmark 追踪或跨文件自动修复 | 删除 Activity/Note/链接不会删除资源；文件真正整理和删除交给 Finder；外部移动路径可能失效，保守提示 |

| D43 | 阶段 10 在主窗口以单页设置统一外观、存储和语音转写：主题三态切换、Vault 路径/更换/重扫/Finder 打开、阿里云百炼北京地域 API Key（Keychain） | 侧边栏底部原主题按钮与 Vault 配置菜单统一为一个设置齿轮；不新增第四主导航或独立窗口；首启无 Vault 仍直接选择，Vault 健康异常仍在主界面可见；不提供模型/地域/供应商选择；详见 [阶段 10](../10-settings/proposal.md) |
| D44 | 阶段 11 从 MP3 生成**只读逐字稿 Note**：文件仍是普通 Markdown Note，导入原始 MP3 后立即创建 Note，再异步写入识别结果 | 仅**自动生成的转写正文**在 Pata 内只读，不能编辑发言/说话人/时间戳，但可选择、复制、搜索和点击时间戳播放；标题/标签仍可编辑，普通手写 Note（包括附带 MP3）不受影响。支持毫秒定位、失败重试，重新转写经确认替换整篇只读正文并保留 Note 属性与音频关联。无独立 Transcript 类型/JSON 侧车/多供应商/AI 摘要；主音频关联及时间戳链接的唯一协议待阶段 2 Schema 定稿，详见 [阶段 11](../11-audio-transcription/proposal.md) |
| D45 | 阶段 12 保留 Pata 现有视觉和布局，仅局部优化基础组件、排版与交互一致性；shadcn/ui Nova 是工程参考，不整体换肤 | 避免为了统一技术栈让用户重新学习界面；坚持 Less is More、按需引入、不做全量重构。详见 [阶段 12](../12-frontend-foundation/proposal.md) |
| D46 | UI 交互强调色优先跟随 macOS 系统设置，Pata 品牌绿主要用于品牌识别；成功/警告/错误使用独立语义色 | 在 Wails/WKWebView 实机验证 Accent 来源与更新；无法可靠读取时明确降级，不把固定绿/蓝冒充系统色，不为此增加新用户配置项。详见 [阶段 12](../12-frontend-foundation/proposal.md) |

| D47 | 通过运行中的 Pata 提供本机 MCP 服务 | 功能与使用方式见 [阶段 10](../10-settings/proposal.md#mcp) |
| D48 | 来源仅区分 GUI 的「我」与 MCP 的「Agent」，缺省即我；仅追踪实体/记录创建及每次任务状态变化 | 创建事件由 Task 元数据派生；来源在 Activity 时间线及 Note 编辑页展示，列表不加徽标。来源由 Core 受信任入口确定，不认证具体调用方；协议见 [Schema](../02-foundation/schema.md#操作来源阶段-14)，实施与验收见 [阶段 14](../14-activity-attribution/proposal.md) |

## 不轻易改变的设计约束

- 不做强制每日整理动作。
- 不把“没有标签”解释为“未整理”。
- 不把所有技术文档都强制关联 Task。
- 不把标签关系误解成明确的 Task–Note 关联。
- 不制造一份额外的工作日志来重复 Activity 和任务状态事件。
