# Pata · 文档与实施路线

**文档按实施阶段组织，而不是按功能模块组织。** 当前路线包含 **11 个顺序阶段**：阶段 1～10 的代码与实机验收已完成；阶段 10 将主题、Vault 与语音 Keychain 凭证集中到主窗口单页设置，阶段 11 增加以普通 Note 为载体的音频逐字稿。**阶段 11 已确定设计，待实施代码**。只有实际新增一个独立交付阶段时，才新增对应的 `docs/NN-name/` 目录。

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

阶段 1 的 UI 附加设计： [macOS 27 原生体验与 Magpie 源码参考](01-validate/macos-native.md)，其真实 Wails 验证安排在阶段 2。

阶段 6 的品牌资料：[idea](06-branding/idea.md) · [proposal](06-branding/proposal.md) · [实施记录](06-branding/implementation-notes.md) · [V2 静态资源总览](06-branding/resources/pata-branding-refined-v2/previews/overview.png)。V2 静态品牌、构建图标、应用内动画与**静态菜单栏托盘**均已接入并完成实机走查。**阶段 6 代码与实机验收已完成**；菜单栏逐帧动画、额外悬停动效已取消，不再列为待办。

## 每阶段的文档约定

- `idea.md`：本阶段为什么需要做、用户价值、**交付结果**。
- `proposal.md`：本阶段具体做什么、**实施顺序**、完成标准及相关功能行为设计。
- 只有对实现有必要时才添加其它文档；放在它**首次需要且负责验收的阶段**，而不是另建 `features/`、`architecture/`、`ui/` 之类横向模块目录。
- 前一个阶段完成之后再进入下一个阶段；需要跨阶段引用时使用相对 Markdown 链接，**不复制成第二套规范**。

## 重要约束

- 三主导航：Today / Tasks / Notes；Activity 与文件不独立设导航。
- 专属 Vault：`notes/`、`tasks/`、`plans/` 是业务 Markdown，`files/` 是原始文件资源，`.pata/` 只存内部状态；阶段 9 才实现文件引用与搜索。
- 标签是 Task、Note、Activity 的全局聚合；Task 内 Activity 动态继承 Task 标签；无 Projects / Inbox。
- Notes 是**单列卡片浏览 → 单主区域编辑**；原型位于 [`01-validate/prototype/index.html`](01-validate/prototype/index.html)。
- Markdown 是数据源；Task/DayPlan 的 Activity 各自存于所属文件而不复制；DayPlan 不等于 Due；记录只有一份。
- **最新目标 Schema 以 [02-foundation/schema.md](02-foundation/schema.md) 为准**；阶段 2/3 的旧 Memo 描述属于历史交付记录，在阶段 8 落地前源码仍可能使用旧格式。
- **MVP 无 CLI、MCP、内置 AI、云同步**；预留代码分层即可，不作具体实现。

## 当前状态

阶段 1 设计已基本完成（待真实用户确认）。阶段 2 已完成：桌面 Spike（P2-001）、存储核心（P2-002，`internal/storage/markdown`）、单 Vault 接入与 Tasks 管理闭环、外部修改感知与冲突提示（P2-003/P2-004）；完成标准已勾选，仅剩用户实机手动走查一次。阶段 3 已完成：Memo 闭环（P3-001，任务详情评论+独立 Memo）、DayPlan 与 Today 计划区块（P3-002，多日安排/due 独立/昨日候选不自动顺延）、今日记录时间线与历史回顾（P3-003，本机时区聚合/完成事件/当前状态注脚）；完成标准已勾选，剩用户实机手动走查。阶段 4 已完成：Notes 服务与单列卡片列表（P4-001）、Vditor 全主区域编辑器与 D19 自动保存（P4-002，含离线包裁剪 23MB→7.5MB 与 cdn dist 层修正）、Task–Note 显式关联（P4-003）；完成标准已勾选，剩用户实机手动走查。阶段 5 代码侧全部完成：全局标签聚合与跨类型搜索后端（P5-001）、侧边栏真实标签与单列标签视图（P5-002）、⌘K/⌘P 全局搜索浮层（P5-003）、GetVaultHealth 错误报告暴露与服务层回归补缺（P5-004）、健康状态 UI/基础无障碍/快捷键与首启审计/macOS 打包验证（P5-005，产出 bin/pata.app 与 bin/pata.dmg）；每批均经独立审查（P5-R1~R5，仅 P5-004 一次通过，余含一次返工）。剩用户实机：真实资料走查、macOS 原生体验回归、MVP 验收清单勾选。

**阶段 6：代码与实机验收完成。** 已接入静态品牌、应用内动画、离线预览与静态菜单栏托盘；经 macOS 实机目视与自动化测试（`TestStage6_BrandingAndAssetsRealMachine`），确认图标无红白模板残留、标题栏微光动画与系统浅/深色表现正常、托盘点击唤醒窗口正常。详见 [idea](06-branding/idea.md)、[proposal](06-branding/proposal.md)、[实施记录](06-branding/implementation-notes.md)。

**阶段 7：代码与实机验收完成。** Notes / Task 描述 / 任务评论 / Today 记录的 `[[` 选择、跳转与持久绑定，Note 相对链接及按 Note/Task 身份去重的“被引用”均已实现。已绑定 Note ID 失效时禁止退回同名标题匹配已修复，并在实机自动化测试（`TestStage7_NoteLinksEndToEnd`）与 live GUI 中全链路验证通过。详见 [idea](07-note-links/idea.md)、[proposal](07-note-links/proposal.md)。

**阶段 8：代码与实机验收完成。** 统一内嵌 `a-` Activity；Task Frontmatter 存纯文本描述、Body 存活动；DayPlan 位于根目录 `plans/`（兼读兼容旧 `.pata/plans/`），Body 存独立活动。删除 Task 连同 Activity 一起删除并幂等级联清理 DayPlan 引用；单文件原子写入、解析错误异常文件隔离；Today 时间线、全局标签聚合与跨实体搜索全部适配 Activity，经实机自动化测试（`TestStage8_ActivityStorageRefactorEndToEnd`）与真实 Vault 审计验证通过。详见 [idea](08-activity-storage/idea.md)、[proposal](08-activity-storage/proposal.md)。

**阶段 9：代码与实机验收完成。** Vault 专属且仅管理约定目录；通过 Activity/Note 拖入文件、复制到 `files/` 并插入标准链接，已有 `[[` 同时搜索 Note 和 File；全局搜索支持按文件名直接找回未引用资源并支持 Quick Look 原生预览。经实机自动化测试（`TestStage9_VaultFilesEndToEnd`）与 live GUI 走查验证通过。详见 [idea](09-vault-files/idea.md)、[proposal](09-vault-files/proposal.md)。

**阶段 10：代码与实机验收完成。** 侧边栏底部收敛为单个「设置」齿轮入口（保留异常告警入口）；主窗口单页纵向呈现「外观 / 存储 / 语音转写」；主题三态保存为应用级偏好；Vault 路径查看、更换目录、重新扫描及 Finder 打开正常；阿里云百炼北京地域 API Key 安全存储于 macOS Keychain，明文不入日志不入文件。经实机自动化测试（`TestStage10_SettingsAcceptance`）与 live GUI 走查验证通过。详见 [idea](10-settings/idea.md)、[proposal](10-settings/proposal.md)。

**阶段 11：仅文档设计完成，尚未编码或验收。** 以普通 Markdown Note 文件承载**只读逐字稿正文**（标题/标签仍可修改，普通 Note 不受影响），复用 `files/`，支持说话人、毫秒时间戳、顶部播放器、时间戳点击播放、进度拖动结束时定位正文及安全重新转写；不做多供应商、JSON 侧车或会议摘要。详见 [11](11-audio-transcription/proposal.md)。

阶段 3 新增 Today 体验完善方案：末尾 `#标签` 快速创建、类似 ChatGPT 的左导航 / 中间 Today 或 Tasks / 右任务详情三栏、移除任务优先级、明确移出计划语义、紧凑日期及时间线。右栏按需打开，Notes 仍单列浏览与全主区域编辑。文档已整理，新增完成标准尚未验收，见 [idea](03-daily-loop/idea.md) 与 [proposal](03-daily-loop/proposal.md)；不改变原基础能力的已完成记录，也不新增阶段。
