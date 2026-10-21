# 阶段 12 · 前端基础设施与设计系统整理 — Proposal

> 状态：设计定稿，**待实施与实机验收**。2026-10-21 两项用户裁决见 [idea.md](idea.md)。
> 产品级布局、体验方向以 [阶段 1 UI 规范](../01-validate/ui.md) 与 [已确认决策](../01-validate/decisions.md) 为依据；本文件是 **012 的实施与验收唯一来源**。若早期原型与已完成阶段/现行代码冲突，不借工程整理之名恢复已取消的功能。

## 1. 首要原则与边界

**优先统一已有体验，不为统一而重构。**

1. **视觉不换肤**：维持当前三入口、布局层次、色彩气质、组件密度；只校准字体可读性、少量不一致的间距/圆角、交互状态和弹层。Nova 是组件参考，**不是**可直接覆盖全局的主题。
2. **系统强调色优先、品牌绿独立**：系统 Accent 作用于选中态、Focus、主要交互等；品牌绿仅作品牌表达和少量有理由的装饰。成功绿、错误红、警告橙是**语义状态**而非品牌主题色，不混作主操作色。
3. **复用优先**：先找已有组件/Hooks 和成熟库，后评估复制源码的 shadcn/ui 组件；禁止重复造拖拽引擎、焦点陷阱、复杂弹层。
4. **增量迁移**：旧代码只在真实重复、缺陷、可访问性、维护负担或新功能需要时改动；不因视觉规范全量批量替换 Tailwind 类名。
5. **不改产品和数据**：Go Core / Markdown 数据协议、Vditor 编辑语义、Notes 只读逐字稿、Today 拖拽提交时机与现有保护逻辑不得改变。

## 2. 现状依据（2026-10-21 main 静态检查）

- `frontend/package.json` 已包含 React 18、Tailwind CSS 4、Lucide、Vditor、`@dnd-kit/react` / `@dnd-kit/helpers`；**未安装** Motion、Zustand、react-resizable-panels 或 shadcn 组件基础层。
- `App.tsx` 使用自写 Pointer Events 拖动左侧栏；`DetailSplit.tsx` 的详情宽度当前固定 400px。**不因为存在自写代码就强制换布局库**。
- `TodayPlanList.tsx` 已用新版 dnd-kit（`DragDropProvider`、`useSortable`、`DragOverlay`）；用户反馈拖拽有“按格跳、不跟手”体验。应先对拖动源、overlay 尺寸/定位、过渡、占位排序与重排反馈进行实机定位，避免叠加第二套 transform/排序引擎。
- `NotesView.tsx` 有多处独立确认弹窗与菜单；`SearchOverlay.tsx`、`QuickCreateInput.tsx` 各自处理部分焦点/键盘语义。基础交互复用收益明显。
- `index.css` 全局取消 `:focus-visible` outline；应让键盘焦点**统一可见**，不能因“原生克制”隐藏所有可访问性反馈。
- `index.css` Vditor 正文约 14px / 1.55，多个列表用 10–12px；改进以实际阅读体验为准，不一次性改变所有字号。
- 现有大量 `stone` / `emerald` 的 Tailwind 类写在各页面；以小型语义变量管理新增和改动区域，逐步减小硬编码范围。
- `AGENTS.md`、`docs/01-validate/ui.md` 已有产品约束；本阶段只补工程实践，不另设平行的产品设计规范。

## 3. 选型冻结：已用保留、新增按需

| 范畴 | 012 规则 | 是否现在强制安装 |
| --- | --- | --- |
| 组件与视觉 | shadcn/ui **Nova 风格参考** + Pata 本地组件源码；先根据现有 UI 调整 Tokens | 只在首次需要的组件引入 |
| Headless primitives | 优先评估 **Base UI**（同一项目内不并行增加功能相同的 Radix / React Aria 套件）；引入前验证当前 React 18 / Vite / WKWebView 兼容性 | 否 |
| 样式 | 保留 Tailwind CSS 4 和已有 Vditor 必要覆盖；使用语义化 CSS 变量 | 已具备 |
| 字体 | macOS 系统 sans（SF Pro / PingFang SC）、系统 mono（SF Mono / Menlo），不捆绑/下载字体文件 | 不引依赖 |
| 图标 | Lucide（`lucide-react`）唯一通用图标来源；品牌 Logo 和必要系统原生图标除外 | 已具备 |
| 拖拽 | 保留 `@dnd-kit/react`，以原生能力完成排序和动画；不新写 Pointer DnD，也不与 Motion 争用 `transform` | 已具备 |
| 动画 | CSS 处理 hover/透明度等简单动效；**仅有明确复杂布局/退场动画需求**时引入 Motion | 否 |
| 布局 | 现有 Flex + 固定详情栏保留；真正新增可调多面板时再评估 react-resizable-panels | 否 |
| 状态管理 | 局部 React Hooks 优先；有明确跨页面共享、高频 Props 传递痛点时才评估 Zustand；服务端数据源仍是 Go Core | 否 |
| 编辑器 / 音频 | Vditor、既有播放器与转写预览机制保持 | 已具备 |

**兼容门槛**：不得为了安装 UI 组件，无评估地升级 React、Wails、Vite 或更换包管理器；核查 peer dependencies、打包大小、离线可用性和 macOS 实机行为后选择实际组件版本。不得通过永久 `--force` / `--legacy-peer-deps` 掩盖依赖冲突。

## 4. 最小 Design Tokens

目标不是创建庞大的主题平台，而是让页面少量稳定的样式规则有唯一来源。

### 4.1 语义色

采用 `background`、`surface`、`foreground`、`muted-foreground`、`border`、`accent` / `accent-foreground`、`focus-ring`、`destructive`、`warning`、`success`、`brand` 等**必要**的语义名。

- `background / surface / border` 维持 Pata 已有暖灰、低对比、安静风格；浅/深色分别定义，原型 `#fafaf8` 等**仅供参考，不是必须逐像素照搬**。
- `accent` 是系统交互强调色，不等于 `brand`。导航选中、主按钮、交互焦点不应继续无条件使用 `emerald-700`。
- `brand` 仅品牌识别；与 `success`（完成/保存成功）区分；`warning` 和 `destructive` 用于真实风险。
- 选中与错误状态不能只靠颜色，还需文字、图标或形状辅助区分；确保深浅色及高对比设置下可读。

### 4.2 macOS 系统强调色的实现前置验证（关键）

**不能假定 CSS `AccentColor` 或某个 `-apple-*` 颜色关键字一定读取用户设置。** WebKit 在不同版本中对 `AccentColor` 的表现可能是固定值。优先使用经验证能跟随系统的 WKWebView 机制，必要时评估已有 Wails 能力/极小原生桥接，再映射为统一 `--pata-accent` / `--pata-accent-foreground`。

验证步骤：

1. 在 **Pata 实际 Wails/WKWebView**（不是 Chrome 浏览器）运行浅/深色、不同 macOS Accent（如蓝色/紫色/石墨色）的视觉测试。
2. 检查窗口重新聚焦、系统 Accent 改动后的更新时机、选中态与前景对比度；无法实时同步时明确刷新/重启行为。
3. 如果纯 CSS **不能可靠跟随系统**，不得默默用品牌绿/固定蓝冒充“系统 Accent”；优先保留系统原生控件表现，其他自绘控件暂用中性选中态/可见焦点，或通过经过验证的原生来源实现。不为了跨版本完美实时同步做复杂架构。
4. 记录实际实现路径、测试系统版本与已知限制。满足验证后方可宣布“系统强调色跟随”。

### 4.3 排版和空间

- 无衬线：`-apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif`；等宽：系统 `ui-monospace` / `SFMono-Regular` / Menlo 回退。没有 WebFont 或额外字体资源。
- **界面密度与阅读密度分开**：导航/任务及标签常用 13–14px；正文较长的 Notes 推荐以 15px、约 1.65–1.75 行高为调整目标；辅助信息建议不低于 11–12px。上述为验收基准、非强制扫全站替换值。
- 延续现有 8px 主要节奏，以 4px 单位细化必要间距；radius 只保留常用三级；阴影克制，优先用留白/细边框分层。
- 统一 Lucide 常用大小和线宽，普通可点击命中区域尽可能达到约 32–36px。
- 不新增“密度模式”“自定义字体”“自选主题色”等用户设置。

### 4.4 组件状态与层级

- 组件统一 `default / hover / active / selected / focus-visible / disabled / loading / error` 中适用的状态；不要求每种组件展示没有意义的状态。
- 恢复可见的键盘焦点，避免全局 `:focus-visible { outline: none; }`。与 Vditor 编辑焦点冲突的情况仅做局部、有替代反馈的处理。
- 统一 Dialog / AlertDialog / Popover / DropdownMenu 的焦点进入、Tab 循环、Esc、取消、恢复触发位置、外部点击与 Portal 层级；不可在未保存或破坏性确认中因外部点击直接丢弃数据。
- 通用入口优先已有 `src/components/ui/` 组件，不允许业务页面再次复制基础弹窗的键盘/遮罩/关闭实现。

## 5. 交互反馈与跨页面统一

1. **成功安静、失败明确**：保存成功尽量就地反馈；错误就地可见、保留输入/草稿；不把所有反馈做成 Toast 系统。
2. **文件安全不回归**：现有冲突检测、Notes 自动保存/重载保护、Activity 提交、Task 状态即时操作及排序落盘仅一次等保护保留。失败恢复真实已保存状态，不显示虚假成功。
3. **明确的危险语义**：永久删除需要足够明确的文案/确认；取消与主要操作的键盘动作不应产生歧义。
4. **统一键盘与中文输入法行为**：`⌘K`、`⌘,`、Escape、Tab / Shift+Tab、`Enter`、组合输入期间提交等均需在实际 WKWebView 复测。
5. **减少动态效果**：CSS、Motion（若引入）、dnd-kit 过渡及 `scrollIntoView({ behavior: 'smooth' })` 均需遵循系统 Reduce Motion；禁止无限循环的装饰动画。
6. **布局现状优先**：Today / Tasks 仍左导航 + 主区 + 按需详情（详情当前 400px）；Notes 仍单列浏览、全主区编辑。早期文档中的“侧栏可收起”是历史提案，当前 `App.tsx` 已取消收起；012 不擅自恢复。窄窗口只修已有布局的遮挡和可用性，不发明全新移动端适配。

## 6. 实施顺序与完成标准

### P12-001 · 现状基线及语义变量

- 为 Today / Tasks / Notes、搜索、设置、两类弹窗与拖拽录制/截图基线，记录浅深色和窄窗口表现。
- 在**现有** `frontend/src/index.css` 等已有主题入口补少量语义色、字体、圆角/间距规则。已有 Vditor 特定覆盖保留，避免分裂多个全局主题 CSS。
- 做系统强调色 Wails/WKWebView 试验；确认真实可用实现与降级策略后再改组件选中色。

**完成条件**：语义色与品牌色分开，系统 Accent 真实支持情况记录清楚；旧页面无大面积视觉偏移。

### P12-002 · 按需建立基础组件

- 排查重复点，优先整理 **Button / Input / Dialog（含危险确认）/ Popover 或 DropdownMenu** 中确实有多个调用点的组件。
- 可从 shadcn/ui Nova + 一套已确认的 primitives 引入组件源码，按 Pata 现有样式调整；不覆盖已修改的本地组件。
- 确认 Portal/overlay 层级、焦点陷阱、Esc、外部点击与焦点恢复一致；不需要的组件**不安装**。

**完成条件**：至少两个重复交互点复用同一个基础组件；未造成重复 primitives 依赖；关键弹层键盘行为通过。

### P12-003 · 小范围迁移与真实交互缺陷修复

- 仅迁移已发现的重复按钮/确认弹窗/菜单；保留交互文案及保存/冲突语义。
- Today 拖拽以用户反馈“跟手性、非一格一跳”为体验验收目标，优先使用 dnd-kit 现有机制排查 overlay 坐标、大小、源项样式/透明度、排序过渡；**拖动过程中不写 Markdown**，有效放下后仍只提交一次。
- 检查并修正全局焦点不可见、特定系统 Reduce Motion 不生效等易复现问题。

**完成条件**：至少目标场景交互更一致，原有任务/Note/Activity 工作流不回归；无新增 UI 模式。

### P12-004 · 回归与收尾

- `frontend` 运行现有 build/test，检查锁文件/依赖树，不增加同类组件库、动画引擎或重复版本；记录相对基线的构建体积变化（不强设不合理的绝对体积门槛）。
- 在真实 macOS Wails 应用验证浅/深色、系统强调色切换、窄窗口、拖拽滚动与取消、键盘焦点、中文 IME、Vditor 编辑、播放器/只读逐字稿、数据冲突和取消删除。
- 以本 proposal 的具体通过项目打勾，不仅以 lint/build 通过称为“验收完成”；仅更新 `docs/README.md` 的阶段状态，不新开 013。

## 7. 验收 Checklist（实施完逐项勾选）

- [ ] Today / Tasks / Notes 的主视觉、主布局和导航保持熟悉，不做全量换肤，不恢复侧栏收起。
- [ ] 统一的基本设计 Tokens 实际用于新增/调整的组件；品牌绿与交互 Accent、成功/警告/错误语义分开。
- [ ] 系统 Accent 在 WKWebView 的真实实现路径和限制被明确记录；实机验证蓝/紫/石墨以及浅/深主题，不能随系统变化时有诚实降级说明。
- [ ] 系统字体栈无需字体包或 CDN；Note 长文本可读性和小字号辅助文本经过实机走查。
- [ ] 已迁移的通用控件复用同一实现；Dialog/Menu 焦点、Esc、遮罩、外部点击、关闭后焦点恢复一致；键盘 focus 可见。
- [ ] Today dnd-kit 拖拽随指针流畅移动、占位反馈可理解；取消不落盘，有效放下只提交一次；失败恢复已保存顺序。
- [ ] 系统 Reduce Motion 下无多余动效，包括播放器逐字稿定位滚动；动画不干扰拖拽 transform。
- [ ] Tasks 完成/重新打开、Activity 创建、Notes 自动保存/冲突保护、只读逐字稿及 MP3 播放无行为回归。
- [ ] macOS 深浅色、窄窗口、真实键盘、中文输入法和高对比/减少透明度等必要项目完成实际走查。
- [ ] 无新增不必要的 Motion / Zustand / react-resizable-panels / 组件展示系统；`package-lock.json` 无无理由的重复同类依赖/版本。

## 8. 不做 / 防止范围扩张

- 不改变产品页面信息架构、Go Core API、Markdown 数据结构。
- 不整体应用 `shadcn apply --preset nova` 覆盖现有 UI；不以自动生成结果覆盖 Pata 已修改组件。
- 不引入另一个拖拽框架、第二套通用图标库、全局状态容器或自建动画编排框架。
- 不将所有 `text-xs`/颜色类一次性全量替换，不追求“零个硬编码类名”的形式指标。
- 不单独开发字体切换、主题颜色选择、复杂尺寸系统、响应式移动 App、Storybook。
- **本阶段的交付目标是更顺手、更可维护的 Pata，而非组件库数量或 UI 风格变化。**
