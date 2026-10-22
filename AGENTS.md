# Pata · Agent 项目指引

**项目名称：啪嗒 / Pata。** 阶段 1～13 的代码与 macOS 实机验收已完成。实际进度以 [docs/README.md](docs/README.md) 为准。

## 开始阅读

1. 阅读 [docs/README.md](docs/README.md)，按 01 → 13 了解已完成阶段。
2. 阅读 [阶段 1 产品提案](docs/01-validate/proposal.md)、[已确认的取舍](docs/01-validate/decisions.md)、[UI 规范](docs/01-validate/ui.md)。
   - macOS 原生窗口细节和 Magpie 源码参考见 [macos-native.md](docs/01-validate/macos-native.md)；浏览器原型不等于真实 Liquid Glass 验证。
3. 数据 Schema 的**单一来源**为 [阶段 2 schema.md](docs/02-foundation/schema.md)；旧 `docs/02-foundation/examples/` 为历史测试固件，不是生产数据。
4. 直接打开 `docs/01-validate/prototype/index.html` 查看静态 UI 原型，无服务依赖。

## 修改文档/执行计划

- `docs/` **仅以实施阶段分目录**，每个阶段有 `idea.md`、`proposal.md`，其他设计资料留在负责它的阶段内。
- 需要修改某个交付目标时，修改该阶段的 proposal 并更新对应完成标准；涉及产品边界的决定同步更新 `docs/01-validate/decisions.md`。
- 不要把功能当做新阶段单独建目录，除非整个交付计划确实新增一个顺序实施步骤。
- 保持 Markdown 数据源唯一、文件可恢复读取、不重复建模；Task/Today 源文件是 App 内部协议，用户主要通过 GUI 操作，未来 CLI 调用同一 Core；Notes Markdown 保持面向用户编辑。
- **本阶段不实现 CLI/MCP/AI 集成**；未来 CLI 依赖运行中的 App Core，IPC/自动启动等在 CLI 需求阶段讨论，禁止私自扩大范围。
- 阶段 8 的 DayPlan **目标路径**为根 `plans/`（须备份）；阶段 9 的 `files/` 亦为用户数据、不可当缓存清理。
- 阶段 9 仅在 Today/Task Activity 与 Note 中导入、引用文件，`[[` 候选同时支持 Note 与 File；原生预览、按文件名搜索，不做 Files 导航、File 实体或自动清理。
- **阶段 10（已完成）**：主窗口单页设置包含「外观 / 存储 / 语音转写」；侧边栏底部主题三按钮与 Vault 配置菜单收敛为单个设置齿轮。主题三态迁入设置并持久化；Vault 更换/重扫/Finder 打开迁入设置，但首次缺 Vault 仍直接引导、健康异常仍在主界面可见。API Key 存 macOS Keychain，地域固定北京、模型固定 `qwen-audio-3.1-asr-flash-filetrans`；不做地域/供应商/模型选择。文档见 [10 proposal](docs/10-settings/proposal.md)。
- **阶段 11（已完成）**：在 Notes 从 MP3 创建存储格式为普通 Markdown Note、**正文在 Pata 内只读**的逐字稿；原 MP3 存 `files/`，导入后立即建 Note，标题/标签可编辑，逐字稿可选择/复制/搜索。支持毫秒时间戳、说话人、顶部播放器、时间戳点击跳播、拖动结束定位逐字稿、确认后替换旧逐字稿；普通 Note 即便含 MP3 也保持可编辑。不做专用 Transcript 类型、JSON 侧车、会议摘要或多供应商。文档见 [11 proposal](docs/11-audio-transcription/proposal.md)。

## 产品不可破坏的规则

- 仅 Today / Tasks / Notes 三个主导航。Activity 不独立设入口。
- 目标模型：Task + Note + DayPlan 为顶层 Markdown；Activity 归属于 Task 或 DayPlan 的文件内部。
- 全局标签聚合 Task、Note、Activity；Task 内 Activity 的标签由自身 + Task 动态继承，Today 独立 Activity 仅看自身标签。
- Today 计划与 Task due 相互独立；不强制下班复盘。
- Notes 无嵌套三列结构：单列浏览、全主区域编辑。
- 参照 macOS 27 HIG + Magpie 的窗口实现；尊重系统主题、强调色、辅助功能；Liquid Glass 可选，非 MVP 必须。
- 核心原则：Less is More / Record Once / Local First。
- 阶段 6 不再开发菜单栏帧动画或额外悬停动效；阶段 7 不实现外部移动跨文件自动维护、批量链接更新重试或精确光标/滚动恢复。已绑定 `note_refs` ID 失效时不得按同名笔记重新推断（已修复），详情见 [阶段 7 proposal](docs/07-note-links/proposal.md)。

## 前端工程约束（阶段 12）

- **优先统一已有体验，不为统一而重构**：保留现有 Today / Tasks / Notes 视觉与交互，仅对真实重复、缺陷及可访问性问题做局部优化；不得整体套用 Nova 主题。
- 新 UI 先查找并复用项目内基础组件、Hooks 与已安装成熟库，确有缺口才增加依赖；组件样式以 Pata 语义 Design Tokens 为准。
- 通用组件采用 shadcn/ui Nova 作为风格参考、组件源码在本仓库可控；Headless primitives 优先评估 Base UI，避免并行使用功能重复的套件；不要覆盖已自定义组件。
- 图标统一使用 `lucide-react`（品牌 Logo 和系统原生图标除外）；字体使用 macOS 系统 SF / 苹方 / 等宽回退，不引入额外字体。
- 交互强调色优先跟随 **macOS 系统 Accent**；品牌绿主要用于品牌识别，成功/警告/错误各自独立。不能把固定绿/蓝误称为系统跟随；WKWebView 能力须实机验证并有清楚降级策略。
- Today 拖拽复用现有 `@dnd-kit/react`，禁止另造拖拽引擎；简单动效用 CSS，复杂动效才评估 Motion，避免与 dnd-kit 重复控制 `transform`。
- 阶段 12 的布局约束是已完成历史基线；**阶段 13 明确要求恢复 App Shell 级三栏**：左侧导航、中间 Workspace、全局唯一的可收起/拖拽 Task Inspector。Today / Tasks / Tag 不得分别创建详情栏；只在实测有必要时才评估 `react-resizable-panels`。状态优先 React Hooks，仅真实需求再评估 Zustand。
- 所有交互控件应有可见键盘焦点；Dialog / Popover / 菜单必须正确处理 Esc、Tab、关闭后焦点恢复和必要的危险确认；遵循减少动态效果及中文输入法兼容。
- 操作成功尽量轻量提示，失败保留草稿、明确原因并可恢复；不改变 Go Core / Markdown 数据语义，不破坏保存冲突保护。
- 新依赖必须经过 peer dependency、依赖树、打包体积、离线可用性及 macOS 实机兼容性检查；不为安装组件而升级无关技术栈。
- 阶段 12 的历史选型与验收记录见 [012 proposal](docs/12-frontend-foundation/proposal.md)；**013 的布局和 Activity UI 实施及验收唯一主文档**是 [013 proposal](docs/13-app-shell-activity/proposal.md)。不在 AGENTS.md 复制设计 Tokens 或验收清单。
