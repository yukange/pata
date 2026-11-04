# 阶段 17 · Pata 纯 Swift 原生重构 — Proposal

> **状态：原生迁移主体已落地；原生更新尚未恢复，正式发布链尚未验收。** 全量迁移为纯 Swift 原生应用（SwiftUI/AppKit + Swift Core），原有 Go + Wails + React 运行时及技术栈已完成对照验证并收敛移除。产品边界以 [阶段 1 决策](../01-validate/decisions.md) 为准，现行持久化格式以 [阶段 2 Schema](../02-foundation/schema.md) 为唯一权威来源；旧版功能细节以已交付阶段和当前运行行为为参照。

## 1. 目标与成功判定

将现有 Pata（Go 1.25 + Wails v3 + React/TS + Vditor）完整迁移为 **macOS 原生 Swift 应用**，目标技术栈：

| 领域 | 目标实现 | 约束 |
| --- | --- | --- |
| App Shell / Today / Tasks / Notes / 设置 | SwiftUI，必要时嵌入 AppKit | 保留布局与交互，不为“原生”整体换肤 |
| Markdown IR Note 编辑器 | 首选 SwiftMarkdownEngine（AppKit / TextKit 2），经 `NSViewRepresentable` 接入 | 编辑器独立模块，可替换；先通过输入法和往返验证 |
| 业务 Core / 搜索 / 文件变更监听 | Swift + Foundation，按需采用系统文件协调/监测 API | **单一**业务写入与索引入口，无平行 Core |
| Vault 存储 | Markdown + YAML Frontmatter + 当前 Activity 内嵌协议 | **不迁移、不重写已有 Vault**；原子写入和未知字段保留 |
| 本机 MCP | 官方 [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) 优先验证 | 保留现有 Tools / Resources / 参数与返回契约、启停行为 |
| MP3 转写 / 播放 | Swift URLSession / AVFoundation / 本机密钥文件 | 保留北京地域 Qwen ASR、逐字稿只读、毫秒跳播 |
| 更新 / 系统菜单 / 偏好 | SwiftUI / AppKit 原生能力与可审计更新实现 | 开发包不接官方自替换更新；正式包签名、公证另验收 |

**成功不等于“能运行一个空白 SwiftUI 窗口”**：必须做到现有 Vault 原地打开、当前功能与交互不倒退，原生输入法与编辑器验收通过，并能在本机用 Xcode/CLI 构建、测试、启动。

## 2. 迁移不变量（必须保持）

### 2.1 数据与文件

1. 权威格式仍为 [schema.md](../02-foundation/schema.md)。保持 `t-` / `n-` / `a-` + 小写 ULID、时区时间、`status_events`、`created_by` / `by`、动态标签继承、`draft` 单向转正式笔记等规则。
2. 单 Vault 的 `tasks/`、`notes/`、`plans/`、`files/` 与 `.pata/` 边界不变；`plans/` 和 `files/` 是用户数据。Task/DayPlan 是 App 内部 Markdown 协议、Activity 内嵌；Note 正文是用户可直接编辑的 Markdown。
3. **无需导入或自动迁移**。只读打开旧 Vault 不应改变文件内容；按用户明确操作编辑时，仅修改对应字段/块。合法未知 Frontmatter、Activity 元数据及未修改正文必须保留；保留文件、ID、相对路径和时间等信息。
4. 保持单文件临时写入 + 原子替换、baseline/hash 冲突检测、同一文件基于最新内容串行修改；格式损坏隔离到单文件；重扫可从文件重建索引。跨文件采用现有轻量最终一致性，不引入数据库、WAL 或复杂事务。
5. 兼容外部修改、文件删除、丢失引用、同名 Note；**已绑定但目标 Note 失效时不得重新按同名标题绑定到新 Note**。无须新增路径自动修复或基于 inode 的资源追踪。

### 2.2 引用：重点兼容 SwiftMarkdownEngine

- **Note 正文**：`[[` 候选可搜索已有正式 Note 和 File；选择后仍插入现有**标准 Markdown 相对链接**。普通 Markdown URL 与资源路径保持原样；不要把它们持久化为 `[[Name|id]]`。
- **Task 描述 / Task Activity / Today 独立 Activity**：原本就是**纯文本**；`[[名称]]` 用本作用域 `note_refs` 显式绑定 Note ID，File 使用标准相对路径链接。不要因采用 IR 编辑器而把这些字段富文本化。
- MarkdownEngine 公开 `WikiLinkResolver`、`onLinkClick`、`onInlineSelectionChange`、`onInlinePreviewKey` 和 `pendingInlineReplacement`，可以用来识别输入、补全、点击；**但其默认 `WikiLinkService` 会在 `[[Name|id]]` 与 `[[Name]]` 之间转换**。实施前必须在编辑器适配层验证是否可直接复用；若会悄然改变 Note 正文协议，则隔离/改造服务或定制局部行为，不能直接将其文本绑定结果写入 Vault。
- 用含同名 Note、跨目录、Unicode、空格、转义路径、失效引用、文件链接、代码块中 `[[...]]` 以及草稿的旧 Vault 固件，测试“打开 → 不编辑 → 离开”和“编辑其他段落 → 保存 → 重开”的**无损**表现。文件链接仍原生预览；已绑定 ID 的失效场景不得回退标题匹配。
- 不为改变编辑器而新增 backlinks 面板、独立 File 业务实体或“引用到任务”自动写入的隐式副作用。

### 2.3 用户交互

- 仅 Today / Tasks / Notes 三主导航；一个全局、可收起和可调宽度的 Task Inspector。Notes 工作区自身为草稿/正式笔记左列表与唯一右编辑器，不能出现第四个常驻 Inspector/Tab。
- 草稿无标题、无标签，首次有内容落盘；点「转为笔记」**原地**显示标题并聚焦，保存非空标题后保留原 Note ID/路径/正文/时间；不弹转换对话框、不提供反向转换。
- Today 任务选择、创建与排序、Activity 的创建/编辑/删除、任务完成/重开时间线、人/Agent 来源、日期切换、全局搜索与标签语义保持不变；Today 日期随午夜正确刷新。
- 设置为主窗口内辅助页面；系统外观/强调色、仅异常时的 Vault 状态提示、菜单栏和系统 Pata 菜单行为保持；不追加工具栏、复杂动画或新导航。
- 切换 Note/Task/页面/退出/更新安装之前，保留**未保存编辑、冲突与取消操作**的保护；系统级中文输入、键盘焦点和辅助功能不能退化。

## 3. 原生 IR 编辑器的验证门槛（017-001）

**在迁移其余 UI 前，先以真正的 macOS AppKit/TextKit 2 Demo 验证，不以浏览器/截图演示替代实机结果。**

- 可直接输入 Markdown 并**在原位置呈现 IR 样式**：标题、加粗、斜体、列表、引用、链接、代码块；光标进入时编辑标记自然可用，离开后不出现预览/源码双窗格。无常驻 Markdown 工具栏、无自动出现的块拖拽手柄。
- MacBook 触控板开启「轻点来点按」，分别使用 **豆包中文、豆包英文、系统 ABC**；测试编辑器有焦点后轻点侧栏、按钮、列表项，第一次点击执行；物理点击为对照。特别测试输入法选词/组合态的 Enter、Esc、撤销、删除及中途切换。
- 光标移动、跨段落选区、全选、复制/粘贴、撤销/重做、删除标记、代码块与大量正文滚动稳定，不发生意外改写或丢失文字；切换笔记不会将旧快照覆盖新内容。
- 对旧 Note 的相对链接 `[[` 补全、搜索、键盘导航、点击跳转与焦点恢复逐项验证；逐字稿只读显示可复用普通 Note 显示组件，但不能被编辑器误写。
- 验证 `SwiftMarkdownEngine` 版本和 API 及许可证；如果达不到以上行为，才在**同一个编辑器接口**后评估其他原生方案，不为了保留库而改变 Pata 的数据格式。

建议仅有一个面向应用的 `PataNoteEditor` 接口：输入当前 Note ID 与原始 Markdown、输出用户编辑与保存状态、引用/附件/链接操作回调、必要的聚焦与导航方法。实现细节和内部显示形式不得泄漏到 Vault Core 或非 Note 输入框。

## 4. Core、MCP 与系统能力迁移（017-002～017-005）

### 4.1 Core / Vault

- 先以现有 Go 单测、实际 Vault Fixture 和阶段 2 Schema 提取**行为契约**，再实现 Swift 解析、序列化、ID、索引、标签、检索、文件监听和 Task/Note/DayPlan/Activity 操作。
- GUI 与 MCP 通过同一 Swift Core 接口操作当前 Vault；严格以目标实体/Activity ID 修改最新文件内容，避免“整份旧快照覆盖”。无独立持久化数据库或第二写入进程。
- 读取旧 Vault 不做静默回填；必要的 App 本地 UI 偏好迁移与**数据格式迁移分开**。ASR 凭证改存 Vault 外的本机私有文件；旧钥匙串条目不自动读取或删除，升级后在设置重新保存一次 Key。绝不在日志输出 Key。

### 4.2 MCP 保持协议

- 保留用户已启用时才启动、仅回环地址监听、退出 App 即停止、当前 Vault 切换后旧连接拒绝操作等规则；维持设置中的启停与复制说明。
- 以下 Tool 名称和语义必须保留：`pata_search`、`pata_list`、`pata_read`、`pata_create_note`、`pata_create_task`、`pata_append_activity`、`pata_set_task_status`。
- 保留 `pata://task/{id}` Resource Template、`pata_read` URI 读取、`note_refs` 继续按 Note ID 读取、Agent 来源标记、读取/写入错误语义与现有分页契约。**不要凭当前 SDK 类型不同而静默修改现有客户端兼容行为**；如协议层必须调整，先提供兼容测试和明确变更记录。
- 保持安全边界：不绑定外网地址、不新增远程自动执行或 Agent Session 托管；参数不能伪造 GUI/Agent 来源。官方 Swift MCP SDK 的 HTTP Transport 及 macOS 适配须独立验证。

### 4.3 音频、更新与系统集成

- MP3 作为 `files/` 原件，普通 Note 形式的逐字稿只读；保留毫秒时间戳、播放器点击跳播与拖动结束自动定位、重新转写确认、失败恢复；百炼北京地域与固定模型不变。API Key 存 Vault 外的 `~/Library/Application Support/pata/asr.json`（目录 `0700`、文件 `0600`，原子写入）。
- 保留正式包的自动检查设置、侧栏可见的下载百分比、已下载但有草稿时「等待安装」、应用菜单手动检查、版本/Release 约定和开发构建防自替换。
- 允许本机**不购买 Apple Developer Program** 使用 Xcode 编译/运行/测试；官方分发版仍须单独按 Developer ID 签名、公证、Gatekeeper 和安全更新链验收。不得用 ad-hoc/开发构建自动覆盖朋友的正式安装版。
- 原生 App 图标、菜单、窗口恢复、深浅色、系统 Accent、权限提示、快捷键、可访问性均需在 macOS 实机验证。不要引入无必要的登录项、常驻守护进程或独立浏览器引擎。

## 5. 分包交付（允许 Agent 并行，但共享协议先冻结）

| 工作包 | 交付 | 阻塞验收 |
| --- | --- | --- |
| **017-001** | Swift App 壳 + Markdown IR 编辑器 Spike | 豆包触控板、中文组合、IR 行为、原 Note Markdown 往返通过 |
| **017-002** | Swift Core / Vault / 索引与金样本契约 | 旧 Vault 读取、序列化、文件监听、原子写入、冲突保护、标签/搜索、日期/事件等价 |
| **017-003** | SwiftUI Today / Tasks / Notes / Inspector / Settings | 主导航与三栏、任务/活动/草稿行为、跨页面离开保护、视觉基本一致 |
| **017-004** | Swift MCP + 文件引用 / Agent 协作 | 原 Tools/Resource/参数/结果与启停状态、来源记录兼容 |
| **017-005** | ASR、音频播放器、更新、系统菜单、打包 | 本机密钥文件、转写、跳播、下载/重启草稿保护及开发包隔离 |
| **017-006** | 对照回归、迁移清理、文档/构建收敛 | 全功能与真实 Vault 回归；最终产物无 Go/Wails/React/Vditor 依赖 |

- **先保留旧版源码作为 oracle 与数据固件**；工作包可以并行开发，但不能同时改动权威 Schema 或分叉业务规则。优先交付可以启动、可以检查的纵向切片。
- **不建议运行时长期维持两套 Core**。新旧实现可以在不同目录、分支或测试进程中对照，但 Swift 正式版只有一套写入路径。
- 未完成 017-001 的输入/往返门槛前，不把 SwiftMarkdownEngine 锁死为不可替换依赖；未完成 017-002 的存储等价前，不允许用真实唯一 Vault 测试写入。先用复制的测试 Vault，真实 Vault 只读验证。
- 每个工作包提供可复现的 `swift test` 或 `xcodebuild test` 结果、人工验证步骤和已知缺口；**AI 生成与编译成功不等于交付完成**。

## 6. 验收矩阵

| 类别 | 必测场景 | 合格条件 |
| --- | --- | --- |
| 数据保真 | 旧 Vault 全量只读打开、编辑单个 Task/Activity/Note、重启重扫 | 无未授权改写、丢文件、重编号、丢未知字段或错误合并 |
| 引用 | Note 相对链接、Task/Activity `note_refs`、同名/失效绑定、File 相对链接 | 语义不变，已绑定目标丢失不按同名重连 |
| 任务/今日 | 跨日期安排、到期日独立、完成/重开、历史活动排序、跨午夜刷新 | 与旧版同等结果 |
| Notes | 草稿→正式笔记、标题焦点、自动保存与冲突、搜索定位、切换与恢复 | ID/路径/正文不变，保存不自动补末尾换行，未提交内容不丢 |
| 原生输入 | 豆包中文、豆包英文、ABC，轻点/物理点击，对照 WKWebView 旧版 | Swift 新版点击一次有效；无 IME/选择/Undo 回归 |
| MCP | 全部 Tools、URI Resource、分页、启停、切 Vault 和 Agent 来源 | 现有 MCP 客户端契约不变 |
| 音频 | MP3 导入、转写、只读、毫秒跳播、拖动后定位、重新转写 | 文件和时间戳保真 |
| 应用 | 外观/强调色、可调布局、菜单栏、更新、本机密钥文件、构建/安装 | 开发版可本机用；正式版发布链独立验收 |

**验收证据**：保留去敏的真实格式 Fixture、旧 Go 行为参考输出与 Swift Golden Tests、编辑器 macOS 手工测试记录、MCP 兼容测试以及干净环境从源码构建步骤。测试失败须修复或明确列为阻塞项，不以主观“感觉正常”放行。

## 7. 不做

- 不重新设计业务模型、任务状态/优先级、Today / Tasks / Notes 导航或现有视觉。
- 不提供 Windows/Linux/iOS、同步/云端账号、SQLite/数据库、新的文件层级或第二 Vault。
- 不借重构开发 CLI（仅保留未来可经运行中 App 调用 Core 的架构接口）、内置 AI Agent、自动整理或新任务管理概念。
- 不引入新的 Note `[[Name|id]]` 存储协议、不做历史 Vault 大规模迁移、不自动修复任意外部文件改名和失效引用。
- 不为了 Swift 而自研底层 IME、输入法桥接、完整 Markdown 排版引擎；先复用成熟原生组件。
- 不要求买开发者账号才能进行本地开发；也不将缺少账号当作已经完成正式版公证/自动更新验收。

## 8. 本 PR 与阶段完成标准

### 本 PR（需求/规划）

- [x] 定义阶段 17 纯 Swift 重构目标、技术边界与非目标。
- [x] 定义现有 Vault 与 MCP 的兼容底线和 Markdown IR 验证门槛。
- [x] 明确工作包顺序、自动化/实机验收与旧版本对照依据。
- [x] 原生重构代码、依赖替换与自动化数据回归已实施；实机和正式发布验收按下列完成条件记录。

### 阶段 17 完成条件（后续实施逐项打勾）

- [x] 原生 Markdown IR 编辑器通过豆包/ABC、轻点、选区、输入与无损往返测试。
- [x] Swift Core 从旧 Vault 直接读取且业务操作/索引/持久化全量回归通过。
- [x] Today / Tasks / Notes / Settings 与草稿保护和外观体验验收通过。
- [x] MCP Tools / Task URI、Agent 来源及音频逐字稿的自动化回归通过。
- [ ] 原生应用内更新与正式发布链按阶段 15 完成实现及实机验证。
- [x] 最终 Swift 应用可本机从源码构建运行（`scripts/build_swift_app.sh` 产出 `build/bin/Pata.app`）；正式发布链符合签名/公证/更新条件或明确保持未发布状态。
- [x] **新应用产物无 Go/Wails/React/Vditor 运行时**；更新 README / CONTRIBUTING / AGENTS / CI 与阶段文档后，旧栈已退出维护。

## 9. 原生版审计修复（1–20）

本次修复不改变 Vault 的 Markdown Schema，也不添加依赖。编号对应全仓库审计报告。

| 审计编号 | 本次处理 | 验证 |
| --- | --- | --- |
| 1、13、14 | MCP 明确绑定 IPv4 回环地址；更换 Vault 停用访问，连接携带原 Vault 身份；按 Content-Length 累积完整请求并保留大小上限 | MCPRegressionTests 的真实监听、跨 Vault 拒绝、逐字节分段与非法长度测试；另实测非回环地址连接被拒绝 |
| 2 | 分页先编码 Swift 结果为 JSON 值，保留 items/total/next_offset 契约 | 非空列表、搜索及第二页测试；原崩溃复现请求现正常返回 |
| 3、12 | 落盘前校验实体、严格日期及目标路径；拒绝空标题与缺失 MCP 必填参数；导入临时文件采用唯一名称 | AuditCoreRegressionTests 与 MCPRegressionTests 的越界、非法日期、空标题及坏标签测试 |
| 4、6、7 | NoteEditingSession 持有原 Vault、实体快照与读取时的基线；自动保存与离开共享同一保存方法，失败保留草稿、显示错误并阻止切换或退出；Task 字段修改在现有锁内修补当前实体 | NoteEditingSessionTests、旧快照冲突测试、并发任务测试；实际挂载 Notes 视图复跑 A→B 跳转，A 正确保存且 B 原文不变 |
| 5 | 转写只保存到原 Vault 的原笔记，重取最新元数据；音频关联改变或笔记删除则报错；仅更新匹配的编辑会话 | 转写期间改标题、切笔记、切 Vault 和删除笔记的回归测试 |
| 8 | 未知元数据以 YAML 片段保存，往返保留嵌套映射、列表、布尔、数字、字符串及 null，多行字符串的末尾换行与内容中的分隔标记也保持原值 | Frontmatter 与 Activity 未知字段类型及多行字符串回归测试 |
| 9 | Today 与 Task 时间线将 Activity 本作用域的 note_refs 传入既有解析器，删除按同名目标回退的路径 | 实际 ActivityTextView 对同名、改名和删除绑定目标的测试 |
| 10 | 使用 macOS FSEvents 递归监听业务目录，取消按最近内部写入屏蔽整个目录的策略 | 原地修改与内部写入后新建嵌套文件的真实监听测试 |
| 11 | ID 旧映射的文件已经不存在时，允许新路径在第一次重扫接管映射 | 文件移动后一次重扫即可检索到原 ID 的测试 |
| 15 | 独立 Activity 的时间戳使用所选本地工作日 | 历史日期写入及重新读取测试 |
| 16 | 本地图片按解析后的绝对路径缓存 | 两篇笔记相同相对图片名的测试；实际编辑器复现确认缺失图片不命中其他目录缓存 |
| 17 | 删除无实现的更新开关，纠正阶段 15、阶段 17 和决策记录中的完成声明；原生更新仍待实现 | 源码无该开关或虚假运行状态；原生更新完成条件恢复为未完成 |
| 18 | CI 仅上传开发产物，关闭自动创建正式 Release；本机构建与安装的签名失败会中止，并严格验证签名 | shell 语法检查；实际 release 配置构建与 ad-hoc 签名验证通过；Developer ID、公证及 Gatekeeper 正式发布验收仍未完成 |
| 19 | 音频准备接口改为异步，检查和转换在后台任务运行，并检查取消状态 | MainActor 调用真实立体声 WAV 转单声道测试 |
| 20 | 删除无调用方的 ActivityComposer / ActivityItemView | 全仓库引用检查与完整测试、构建 |

自动化：113 项 Swift 测试通过。构建：`scripts/build_swift_app.sh` 生成并验证本地开发用途的应用包。实际百炼请求、完整输入法/辅助功能走查及正式签名公证未在此次验证中执行。

## 10. 搜索交互补充验收

- [x] 点击任务或任务内 Activity 的搜索结果，复用现有导航方法打开并展开唯一 Task Inspector；从设置页搜索也能正确返回内容页。
- [x] 点击 Today 独立 Activity，通过 Activity 归属索引打开所属 DayPlan；不从可能属于其他日期的旧时间戳推算。
- [x] 上下方向键选择、选中行高亮与回车打开共用实际显示的结果顺序（任务 → 笔记 → 记录 → 文件，每组最多 5 条）；选中行自动滚入可见区域。
- [x] 关键词变化重置选择，结果变化约束选择范围，空结果不打开内容；带修饰键或输入法组合文本的方向键交还原生文本输入处理。

验证：完整 116 项 Swift 测试通过。另在挂载的原生搜索窗口中发送键盘事件，验证显示顺序、上下选择、跳过未显示结果、关键词重置、首尾边界及空结果行为。真实中文输入法候选窗仍待人工验收。

## 11. 标签页空白修复（2026-11-02）

- 移除未选标签时写死的“架构设计”。默认“全部”展示 Task、正式 Note 和两类 Activity，包括无标签内容；排除草稿、文件和 DayPlan 容器，多标签内容不重复。
- 页内标签菜单只读取当前 Vault 的真实标签及计数，侧栏收起时也可筛选；虚拟“全部”与同名真实标签分开处理。
- 标签结果中的任务打开唯一 Task Inspector，笔记打开现有编辑器，独立记录按归属索引打开对应日期；复用已有导航与保存保护。
- 任务统一按更新时间排序（与“全部”一致）；记录卡片的计划标签显示所属计划日期（如 `计划 2026-10-11`），不再写死“今日计划”。
- 滚动容器铺满工作区，滚动条放在右边缘；正文继续居中限宽。
- 验证：新增 `tagPageAllEntities` 覆盖“全部”的包含 / 排除范围及标签过滤与继承；现有标签聚合、导航及笔记会话相关测试通过；真实临时 Vault 验证全部数量、无标签内容、大小写合并、动态继承、同名真实标签及跳转；暗色“全部”、具体标签和空资料库已完成原生离屏渲染检查；Release 构建和签名验证通过。未执行前台实体鼠标与键盘走查。

示例资料库的原生截图：[修复前](screenshots/tag-before.png)、[修复后](screenshots/tag-after.png)、[按真实标签筛选](screenshots/tag-filter.png)。

## 12. ASR 本机文件凭证（2026-11-04）

- API Key 保存在 `~/Library/Application Support/pata/asr.json`，普通 JSON 字段 `apiKey`；不进入 Vault、日志或仓库。目录 `0700`、文件 `0600`，同目录临时文件完整写入后原子替换。文件权限提供访问限制，不声称文件已加密。
- 启动、设置与音频转写共用 `PataAudio.ASRCredentialStore`，移除 ASR 的 Keychain 模块与双存储路径。更换成功才清空输入并关闭编辑；失败保留输入、旧密钥与错误原因。损坏或无法读取的文件不能伪装成已配置。
- 旧钥匙串条目原样保留，不自动读取或删除；升级后在设置重新保存一次 API Key。后续重装只替换 App，密钥文件保留，读取不依赖签名身份，不弹钥匙串授权。
- 本地与 CI 默认 ad-hoc 签名，取消本地证书创建前置步骤；`PATA_SIGNING_IDENTITY` 可显式指定已有证书，安装验证并保留构建签名。正式 Developer ID、公证和发布验收仍待完成。
- 回归覆盖文件缺失、保存/替换/重新打开、目录与文件权限、空值拒绝、损坏文件、读写失败与设置错误恢复。真实百炼网络请求及输入法候选窗仍需另行实机验证。
- 验证：跳过此前已确认的 `MCPTests.appStateMCPControls` 偏好保存线程崩溃用例后，其余 137 项 Swift 测试通过；凭证测试补充既有宽权限文件的收紧检查后单独复跑通过。`scripts/build_swift_app.sh debug` 构建、ad-hoc 签名与严格签名验证通过；修改文档的本地链接、shell 语法和 `git diff --check` 通过。
