# Open Island 落地页官网 — 设计文档

- **日期**: 2026-05-29
- **分支**: `feat/landing-site`
- **状态**: 待用户复核

## 1. 目标与背景

为 Open Island 做一个**独立的像素复古风官网落地页**，设计语言参考 [xisland.app](https://xisland.app)（同类闭源产品），但**内容、品牌、代码全部原创**，体现 Open Island 自己的定位：开源、本地优先、原生 macOS、多 Agent。

核心看点是中间一段**自演示的"假灵动岛"动画**——把产品最核心的体验（刘海里监听多个 Agent、审批权限、回答提问、一键跳回终端）直接演给访客看。

### 来源与版权约定

- xisland 官网源码（`github.com/bluedusk/xisland`，Astro 项目）**没有 LICENSE 文件**，默认保留所有权利。因此**不复制其任何代码或文案**。我们只借鉴：(a) 像素复古的设计语言；(b) 那套"会变形 div 状态机 + canvas 像素精灵 + 假鼠标 + setTimeout 剧本 + IntersectionObserver 播放门控"的**动画技术思路**。所有 HTML/CSS/JS/文案重新编写。
- 字体 `Press Start 2P` 与 `JetBrains Mono` 均为开源、可商用（OFL / Apache-2.0），可放心使用。

## 2. 范围

### 做（v1）
- 单页（`index`）落地页，双语 EN + 简体中文。
- 8 个分区：Nav / Hero / NotchMockup(核心动画) / Features / Support(Agents+Terminals) / WhyOpen / FAQ / Footer。
- 自演示灵动岛动画组件（原创重写）。
- 部署到 X-Pages（pages.xingshulin.com）。

### 不做（v1，非目标）
- blog / docs / download / pricing 等多页面（xisland 有，我们 v1 不做）。
- 任何后端、表单、账号、分析/埋点（违背项目"本地优先、零分析"原则）。
- 明暗主题切换（v1 只做暗色）。
- 自定义域名绑定（先用 X-Pages 默认路径，后续可加）。

## 3. 技术栈与项目结构

- **Astro**（静态输出 `output: 'static'`），与 xisland 同款；Astro 默认零运行时 JS，符合"轻量"诉求。
- 独立目录 `site/`，与 Swift 包隔离。
- `.gitignore` 追加 `site/node_modules/`、`site/dist/`、`site/.astro/`。

```
site/
  package.json
  astro.config.mjs          # output: static; base/site 按 X-Pages 子路径配置
  tsconfig.json
  public/
    favicon.svg             # 用 Scout mark 重画的像素 favicon
    og.png                  # 社交分享图（基于 hero 截图）
  src/
    layouts/BaseLayout.astro  # <head>、字体、global.css、og meta、JSON-LD
    pages/index.astro
    components/
      Nav.astro
      Hero.astro
      NotchMockup.astro       # ★ 核心动画组件（含 scoped <style> + inline module script）
      Features.astro
      Support.astro           # Agents + Terminals 两个网格
      WhyOpen.astro
      FAQ.astro
      Footer.astro
      LangToggle.astro        # 中/EN 切换按钮
    styles/global.css         # 设计令牌（见 §4）
    i18n/strings.ts           # { en: {...}, zh: {...} } 文案字典
```

## 4. 视觉系统（设计令牌）

调性：**暗底 + CRT 琥珀金**（已与用户确认）。

```css
:root {
  /* 底色 */
  --bg:          #0b0b0d;   /* 近黑终端底 */
  --bg-2:        #101013;
  --bg-elevated: #161619;
  --bg-card:     #1a1a1e;

  /* 文字（米白，呼应 Open Island 品牌） */
  --text:   #F2EBDD;
  --text-2: rgba(242, 235, 221, 0.66);
  --text-3: rgba(242, 235, 221, 0.40);

  /* 主强调：CRT 琥珀金 */
  --accent:      #FFB000;
  --accent-dim:  rgba(255, 176, 0, 0.15);
  --accent-glow: rgba(255, 176, 0, 0.30);

  /* 语义/状态色（与 App 内灵动岛状态一致） */
  --blue:   #5797FF;   /* 监听中 */
  --orange: #FF9B28;   /* 待审批 / 提问 */
  --green:  #2AE86B;   /* 已通过 / 完成 */
  --red:    #FF5555;   /* 拒绝 / 危险 */

  --border:   rgba(242, 235, 221, 0.10);
  --border-2: rgba(242, 235, 221, 0.18);

  /* 字体 */
  --pixel: 'Press Start 2P', monospace;
  --mono:  'JetBrains Mono', 'SF Mono', 'Menlo', monospace;

  --radius: 16px;
  --radius-sm: 10px;
}
```

- **字体加载**：`<link>` 引 Google Fonts（`Press Start 2P` + `JetBrains Mono:wght@400;500`，`display=swap`）。可选后续自托管 woff2 以提速，v1 用 CDN。
- **排版**：`Press Start 2P` 仅 400 字重、像素字大字号易糊，故：标题/导航/按钮/标签用 pixel；正文、长段落、代码、FAQ 答案用 `--mono`；全局 `line-height: 1.8`。
- **纹理**：
  - 像素网格背景 `.pixel-grid`（16px `linear-gradient`）。
  - Hero 顶部"刘海打光"光锥 `.light-cone`（琥珀 `radial-gradient` 从顶部中心散下，呼应刘海发光）。
  - CRT 扫描线 `.scanlines`（极淡的重复 `linear-gradient`，`opacity` 很低，`prefers-reduced-motion` 下不动）。
- **选区**：`::selection { background: var(--accent); color: var(--bg); }`
- **响应式**：`max-width: 980px` 容器；`@media (max-width:768px)` 下 `html{font-size:12px}`、分区 padding 收紧、网格降列、动画 mockup 等比缩放。

## 5. 双语机制

- 文案集中在 `src/i18n/strings.ts`：`{ en: {...}, zh: {...} }`，键名语义化（如 `hero.title`、`faq.privacy.q`）。
- 渲染：HTML 默认输出 **EN**，文本节点带 `data-i18n="key"`；整份字典以 inline JSON 注入页面。
- 切换脚本（小，内联）：`DOMContentLoaded` 时读取 `localStorage['oi-lang']`，无则按 `navigator.language`（`zh*` → zh，否则 en）选定；遍历 `[data-i18n]` 用字典填充；同步设置 `<html lang>`。`LangToggle` 点击切换并写回 `localStorage`，无整页刷新、无闪烁（首屏 EN 已可读）。
- pixel 字体对中文无字形 → **中文正文一律走 `--mono` 链中的中文回退**（系统 `PingFang SC` 等）；只有英文标题用 pixel。中文标题用 `--mono` 加粗 + 字间距，保持像素气质但可读。

## 6. 页面分区（内容以仓库为准）

> 内容真实来源：`docs/product.md`、`README.md`。Agent/终端列表是 README/product 的单一事实源，发版时需保持同步。

### 6.1 Nav
- 左：Scout mark（像素重绘）+ "Open Island" pixel 文字。
- 右：`Features` `Agents` `FAQ`（锚点）、`★ GitHub`、`中/EN` 切换、`Download` 主按钮（琥珀实心）。
- 滚动时加半透明毛玻璃底 + 下边框。

### 6.2 Hero
- 徽章：`● Open Source · Local-first`（绿点）。
- H1（pixel）：`The notch companion / for your AI coding agents`。
- Agent 轮播行：`for {Claude Code → Codex → Gemini CLI → OpenCode → Kimi CLI …}` + 闪烁 `_` 光标（独立小脚本，每 ~2.6s 淡入淡出切换；列表取自真实支持的 Agent）。
- 副标题（mono）：一句话讲清"在刘海里监听、审批、回答、跳回，全程不离开编辑器；开源、本地、原生 Swift"。
- CTA：`Download .dmg`（链 `releases/latest`）+ `View on GitHub`（ghost）。
- 安装命令块（mono，可点复制）：`brew install --cask octane0411/tap/openisland`。
- 背景：light-cone + pixel-grid + scanlines 三层。

### 6.3 NotchMockup（核心，见 §7）

### 6.4 Features（像素卡片网格，每卡：像素图标 + 标题 + 一句话）
取自 `docs/product.md` 真实能力：
1. **刘海覆盖层** — 有刘海的 Mac 落在刘海区；外接/无刘海机型回退为顶部居中紧凑条。
2. **行内审批** — Agent 请求运行工具/改文件/删除前，刘海展开 Allow / Deny，原地批准。
3. **回答提问** — 弹窗里直接回答 Agent 的提问，不切窗口。
4. **一键精准跳回** — 跳回到正确的终端会话，支持 tmux 会话/窗口/分屏精确定位。
5. **本地优先** — 无服务器、无账号、无埋点；全部走本地 Unix socket IPC。
6. **原生 Swift** — SwiftUI + AppKit，不是 Electron 套壳；空闲资源占用极低。
7. **自动更新** — 基于 Sparkle 的 appcast 自动更新。
8. **通知与声音** — 权限/事件通知，可配系统提示音，可静音。
9. **Watch / iOS 伴侣** — 事件可推送到 Apple Watch / iPhone。
10. **零配置** — 首次启动 / 设置面板里一键为各 Agent 安装 hook；fail-open（App/桥不在时 Agent 照常运行）。

### 6.5 Support（两个像素芯片网格）
- **Coding Agents（9）**：Claude Code、Codex、OpenCode、Qoder、Qwen Code、Factory、CodeBuddy、Gemini CLI、Kimi CLI。
- **Terminals（8）**：Terminal.app、Ghostty、cmux、Kaku、WezTerm、iTerm2、tmux（复用器）、Warp（规划中，标 `Planned` 弱化样式）。
- 注脚：精准跳回（含分屏/tmux）在 iTerm2、Ghostty、Terminal.app、WezTerm、IDE 终端等可用。

### 6.6 WhyOpen（差异化灵魂区，相对 xisland 的核心区别）
要点：**开源（GPL v3）· 全部代码由 AI 生成 · 零分析零账号 · 本地优先 · fail-open · 原生**。链接到 GitHub、CONTRIBUTING、LICENSE。

### 6.7 FAQ（折叠项，答案用 Open Island 真实信息）
- 支持哪些 Agent？（列 9 个）
- 支持哪些终端？精准跳回范围？（列 8 个 + 跳回说明）
- 能不切到终端就批准权限吗？（能，刘海原地 Allow/Deny）
- 我的数据会离开本机吗？（不会，App 与 CLI 之间全是本机通信，无服务器）
- 零配置怎么做到的？（首启/设置里自动为各 CLI 安装本地 hook，无 API key、无云账号）
- 占资源多吗？（原生 Swift，空闲近零 CPU）
- 外接显示器/无刘海 Mac 能用吗？（能，回退为顶部居中浮条）
- 免费吗？（免费且开源，GPL v3；可从 Releases 或 Homebrew 安装）
- 为什么用"灵动岛"形态？（保持心流，审批/提问/进度都在刘海，不打断写码）
- 同时附 JSON-LD `FAQPage` 结构化数据利于 SEO。

### 6.8 Footer / 大 CTA
- 大号 `Download` 按钮 + brew 命令复读。
- 链接列：GitHub 仓库、Releases、README、CONTRIBUTING、PRIVACY_POLICY、Discord、微信群（`docs/images/wechat-group.jpg`）。
- 版权 + GPL v3 + "By developers, for developers / 全部由 AI 生成"。

### 真实链接表
| 用途 | URL |
|---|---|
| 仓库 | `https://github.com/Octane0411/open-vibe-island` |
| 下载（最新） | `https://github.com/Octane0411/open-vibe-island/releases/latest` |
| Homebrew | `brew install --cask octane0411/tap/openisland` |
| Discord | `https://discord.gg/bPF2HpbCFb` |
| 许可证 | GPL v3（仓库 `LICENSE`） |
| 隐私政策 | 仓库 `PRIVACY_POLICY.md` |
| 微信群图 | `docs/images/wechat-group.jpg` |

## 7. NotchMockup 组件设计（核心动画，原创重写）

### 7.1 DOM 结构
```
.mockup
  .screen #demo-screen          // 假 macOS 桌面/顶栏（暗色 + 极简菜单栏）
    .cursor #cursor             // 假鼠标指针（绝对定位，CSS 缓动）
    .island #island             // 会变形的灵动岛本体
      .layer.active[data-layer=compact]   // 紧凑药丸：mascot + 计数
      .layer[data-layer=sessions]         // 多 Agent 会话列表（状态点）
      .layer[data-layer=approval]         // 权限审批卡：命令 + Allow/Deny
      .layer[data-layer=approved]         // 收回确认
      .layer[data-layer=question]         // 提问 + 选项
      .layer[data-layer=answered]         // 回答确认
      .layer[data-layer=jump]             // 跳回：高亮某终端窗口
      .layer[data-layer=done]             // 完成态
    .label.pixel #demo-label              // 当前状态文字（idle/sessions/...）
```

### 7.2 灵动岛变形
- `#island` 用 CSS transition 过渡 `width / height / border-radius`。
- 状态尺寸表 `SIZES = { compact:{w,h}, sessions:{...}, ... }`。
- 紧凑/确认态 → 圆角药丸（`border-radius` 大、四角圆）；展开态 → `border-radius: 0 0 28px 28px` + 顶边透明，伪装成从刘海垂下的面板。
- 切层 = 移除所有 `.layer.active`，给目标 `[data-layer=x]` 加 `.active`，并套用对应尺寸。

### 7.3 像素精灵系统
- Scout mascot 用**字符串位图**（如 8×8 或 16×16，每字符映射调色板 RGB）画进 `<canvas>`，逐格 `fillRect`。
- `drawSprite(canvasId, { tint, dim })`：`tint` 把精灵按比例混向状态色（蓝/橙/绿），`dim` 去饱和。一张精灵复用成多状态。
- 这是**重新绘制的 Scout 位图**（黑刘海 + 一横一点眼睛），非 xisland 的紫脸。

### 7.4 假鼠标
- `#cursor` 用 CSS `left/top` + `cubic-bezier` 缓动移动；`moveTo(x,y,ms)`。
- `moveToEl(id)`：`getBoundingClientRect` 算目标中心（相对 `#demo-screen`）后移动。
- `click()`：加 `.clicking` 类做按下动画；`pulse(id)`：目标按钮 `scale(1.05)+brightness` 反馈。

### 7.5 剧本（setTimeout 队列）
`storyboard()` 按 `step(fn, delay)` 压入队列后顺序执行，跑空则重排（无限循环）：
```
idle(compact) → 展开 sessions（多 Agent 列表）
→ approval（弹审批，光标移到 Allow）→ click + pulse → approved
→ 收回 compact → question（弹提问，光标移到某选项）→ click → answered
→ 收回 compact → jump（高亮目标终端窗口，演"精准跳回"）→ done
→ 收回 compact → 循环
```
状态文字同步更新 `#demo-label`。

### 7.6 播放门控与无障碍
- `IntersectionObserver(threshold 0.1)` 监听 `.mockup`：进视口 play、离开 pause。
- `visibilitychange`：标签页隐藏时 pause。
- **`prefers-reduced-motion: reduce`**：不启动 JS 循环，直接静态停在 `sessions` 层、隐藏假鼠标（对 xisland 的改进）。
- 纯 CSS/DOM/canvas，零外部依赖；Astro 不打包额外运行时。

## 8. 部署（X-Pages）

- `npm run build` → 静态产物 `site/dist/`。
- 用 `xpages-deploy` skill 打包 `dist/` 部署到 pages.xingshulin.com；**部署时再确认 X-Pages 分配的子路径/slug**，据此设置 `astro.config.mjs` 的 `base`（资源用相对路径，避免子路径 404）。
- 产物纯静态，无需服务端。

## 9. 无障碍与性能

- 语义标题层级、`alt`、`sr-only` 补充屏幕阅读器文案、按钮 `aria-label`。
- 字体 `display=swap`；图片限尺寸；Astro 默认零 JS，仅少量内联脚本（轮播、语言切换、动画）。
- 目标：移动端可读、动画在 reduced-motion 下静止、首屏不阻塞。

## 10. 验证

- `cd site && npm run build` 成功，无报错。
- `npm run preview` 本地起服务，用浏览器实测：
  - 灵动岛动画完整循环、滚出视口暂停、reduced-motion 下静止。
  - 中/EN 切换正确、刷新后记忆、中文无 pixel 字形糊。
  - 375 / 768 / 1280 三档响应式正常。
  - 所有外链/锚点/复制按钮可用。
- 部署到 X-Pages 后打开线上 URL 复测一遍。

## 11. 后续（非 v1）
- 自托管字体提速、自定义域名（如 openisland.app）。
- blog / docs / 下载页、更精致的 OG 图、Lighthouse 调优。
