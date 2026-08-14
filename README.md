# DeepSeek Harness — 原生 macOS 安装包

用 WKWebView 把 DSH Web UI（http://127.0.0.1:3080）包成独立窗口的原生 app（无浏览器边框），
首次启动自举安装 Node + @deepseek-ai/dsh 运行时。产物是 `DeepSeek Harness.app` 和 `DeepSeek Harness.dmg`。

## 目录结构

- main.swift — app 源码（WKWebView + 安装器 UI + 启动/更新检查）
- Info.plist — bundle 元数据（版本用 build.sh --version 修改）
- icon/ — AppIcon.icns（已提交）；favicon.svg + icon-1024.png + make-icon.cjs 用于重新生成
- build.sh — 编译、打包、签名、安装、做 DMG
- dist/ — 构建产物输出

## 构建

    ./build.sh                      # 编译 + 打包 + 签名（临时目录）
    ./build.sh --install            # 同时安装到 /Applications 并注册
    ./build.sh --dmg                # 生成 dist/DeepSeek Harness.dmg，并复制一份到 ~/Desktop
    ./build.sh --version 1.6.0 --install --dmg

## 重新生成图标（仅当鲸鱼 logo 变化时）

1. 更新 icon/favicon.svg
2. 用运行时 node 运行：'/Users/sunkey/Library/Application Support/DeepSeek Harness/runtime/node/bin/node' icon/make-icon.cjs
3. iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns

## 注意事项 / 坑

- macOS 的 WKWebView 没有 .scrollView，NSScrollView 也没有 .bounces；禁用橡皮筋回弹要遍历 subviews
  找到 NSScrollView 并设置 verticalScrollElasticity / horizontalScrollElasticity = .none（见 main.swift 的 disableWebViewBounce）。
- 只构建本机架构：本机 CommandLineTools 缺 x86_64 的 Swift 库，做 universal（arm64+x86_64）需要完整 Xcode。
- 杀掉 dsh server 会杀掉跑在里面的 agent；app 只是浏览器壳，退出 app 不会停 server（server 是 nohup 独立进程，监听 3080）。
