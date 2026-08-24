# DeepSeek Harness — 原生 macOS 安装包

用 WKWebView 把 DSH Web UI（http://127.0.0.1:3080）包成独立窗口的原生 app（无浏览器边框），
首次启动自举安装 Node + @deepseek-ai/dsh 运行时。产物是 `DeepSeek Harness.app` 和 `DeepSeek Harness.dmg`。

安装包内置以下插件，首次启动自动安装到 `~/.dsh/profiles/web`：

- `dsh-pet 0.1.8`
- `dsh-better-sidebar 0.15.2`
- `dsh-frp-remote 0.2.0`

App 菜单中的“插件管理…”可检查版本、升级、启用或禁用、移除插件。禁用只调整
`dsh.profile.bundles`，不会改写 `cordis.patch.yml`；多个操作可在最后统一重启 Harness。
内置 `dsh-pet` 同时包含 VP9-alpha WebM 和 HEVC-alpha MOV：Chrome 使用 WebM，WKWebView
自动使用 MOV，避免 macOS App 中出现黑色背景。

## 目录结构

- main.swift — app 源码（WKWebView + 安装器 UI + 启动/更新检查）
- PluginManager.swift — 原生插件管理窗口与插件生命周期服务
- plugin-catalog.json — 允许安装和升级的固定插件清单
- plugins/dsh-frp-remote/ — FRP 宿主插件与网页配置界面
- scripts/migrate-profile.cjs — 旧版 FRP 手工挂载迁移脚本
- Info.plist — bundle 元数据（版本用 build.sh --version 修改）
- icon/ — AppIcon.icns（已提交）；favicon.svg + icon-1024.png + make-icon.cjs 用于重新生成
- build.sh — 编译、打包、签名、安装、做 DMG
- dist/ — 构建产物输出

## 构建

    ./build.sh                      # 编译 + 打包 + 签名（临时目录）
    ./build.sh --install            # 同时安装到 /Applications 并注册
    ./build.sh --dmg                # 生成 dist/DeepSeek Harness.dmg，并复制一份到 ~/Desktop
    ./build.sh --version 1.0.0 --install --dmg

构建过程会从 npm 下载清单锁定版本的插件包，并从 fatedier/frp GitHub Release 下载当前架构的
`frpc 0.71.0`。frpc 压缩包会进行 SHA-256 校验后再写入 App Resources。
宠物种子构建需要可执行的 `ffmpeg` 和 macOS Swift/AVFoundation 工具链，用于生成 HEVC-alpha
资源；可通过 `FFMPEG_BIN=/path/to/ffmpeg ./build.sh` 指定 ffmpeg。

## FRP 远程访问

DSH 设置页的“远程访问”支持配置 FRP Server、端口、TLS、Token、代理名称、远端端口和公网
HTTPS 地址。本地服务固定为 `127.0.0.1:3080`，不能从页面修改。

- 非敏感配置：`~/.dsh/frp/config.json`
- frpc 模板：`~/.dsh/frp/frpc-dsh.toml`
- Token：macOS Keychain，service 为 `com.deepseek.harness.frp`
- 配置接口：仅监听 `127.0.0.1:3081`，只接受本机 DSH Origin 和 CSRF 令牌

远程页面无法读取或修改 FRP 配置。FRP 只负责转发网络流量，公网入口仍必须单独配置 HTTPS
和访问认证。App 启动时会从公网 HTTPS 地址提取 authority，并通过 `--trusted-host` 传给 DSH。

## 测试

    swiftc -swift-version 5 -typecheck -framework Cocoa -framework WebKit main.swift PluginManager.swift
    node --test tests/frp-config.test.mjs

## 重新生成图标（仅当鲸鱼 logo 变化时）

1. 更新 icon/favicon.svg
2. 用运行时 node 运行：'/Users/sunkey/Library/Application Support/DeepSeek Harness/runtime/node/bin/node' icon/make-icon.cjs
3. iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns

## 注意事项 / 坑

- macOS 的 WKWebView 没有 .scrollView，NSScrollView 也没有 .bounces；禁用橡皮筋回弹要遍历 subviews
  找到 NSScrollView 并设置 verticalScrollElasticity / horizontalScrollElasticity = .none（见 main.swift 的 disableWebViewBounce）。
- 只构建本机架构：本机 CommandLineTools 缺 x86_64 的 Swift 库，做 universal（arm64+x86_64）需要完整 Xcode。
- 杀掉 dsh server 会杀掉跑在里面的 agent；app 只是浏览器壳，退出 app 不会停 server（server 是 nohup 独立进程，监听 3080）。
