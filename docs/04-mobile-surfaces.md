# 四、手机上的界面与登录

## 1) 设置页：桌面双栏 → 手机全屏单栏

桌面版设置弹窗是固定 **363px** 的双栏卡片（左导航 **188px** + 内容 **175px**）。在 411 CSS px 的手机视口下，
内容列只剩 175px，中文标签被压成「一字一行」，并且内容列实测宽 **459px**、右侧被截断。

移动端 CSS（`html { zoom: .88 }` + 作用域限定在设置壳的类名上）：

- 面板 `100vw × 100vh`，`flex-direction: column`；
- 左导航 → 顶部横排页签，隐藏重复的「设置」标题（四个页签在 411px 内排得下）；
- 所有 section/row 加 `box-sizing: border-box` + `min-width: 0`（**越界元素从 52 个降到 0**）；
- 底部 `padding-bottom: calc(112px + env(safe-area-inset-bottom))`，否则最后一项被系统导航栏压住。

> 注意：`zoom` 之后，任何按视口计算的宽度都要除以缩放系数（`calc(100vw / .88)`），否则面板会缩成一小块。

## 2) `window.open` 登录：必须开多窗口，否则黑屏

DSH 的账号登录先 `window.open('about:blank')`，再把那个窗口导航到
`platform.deepseek.com/dsh/authorize?...`。Android WebView **默认不支持多窗口**：
`window.open` 返回 null、主框架还可能落到 `about:blank` —— 用户看到的就是**点登录后整页黑屏**。

三处一起改：

1. `settings.setSupportMultipleWindows(true)`（**不开这个，`onCreateWindow` 根本不会回调**）；
2. `WebChromeClient.onCreateWindow` 里建一个**应用内弹窗 WebView**（同一个 cookie 库，不需要系统浏览器）
   ——注意 `WebViewTransport.setWebView(popup)` 之后要 `sendToTarget()`，然后把它挂进 Dialog；
3. `WebPageClient.onPageStarted` 里拦 `about:blank`，回载应用页面兜底。

实测：点登录 → 弹窗里完整渲染 DeepSeek 登录页（手机号/邮箱 + 密码 + Cookie 提示），主页面保持在「等待登录」。

## 3) 侧栏默认收起

页面加载后检查侧栏开关的 `aria-label`，处于展开态（`收起侧边栏`）就点一下；
在 600/2500/6000 ms 各试一次，幂等。
