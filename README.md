# dsh-desktop

<p align="center">
  <img src="icon/icon-1024.png" width="104" alt="dsh-desktop icon">
</p>

<p align="center">
  DeepSeek Harness 的原生 macOS 桌面包装器。提供独立窗口、运行时自举、插件管理、桌面宠物、代码侧栏和可配置的 FRP 远程访问。
</p>

<p align="center">
  <a href="https://github.com/sunkeycn/dsh-desktop/releases/latest">下载最新版</a>
  ·
  <a href="#从源码构建">从源码构建</a>
  ·
  <a href="#安全说明">安全说明</a>
</p>

![dsh-desktop 主界面](docs/images/desktop-overview.png)

## 功能

- 原生 macOS 窗口：使用 AppKit + WKWebView，保留系统窗口按钮并采用沉浸式透明标题栏。
- 自动准备运行环境：首次启动下载 Node.js 和 `@deepseek-ai/dsh`，后续可在 App 内检查 Harness 更新。
- 原生插件管理：查看版本、升级、启用、禁用和移除插件，多项修改可统一重启生效。
- 内置代码侧栏：使用开源的 [`dsh-better-sidebar`](https://github.com/omdsh-dev/DSH-better-sidebar)。
- 内置桌面宠物：使用 [`dsh-pet`](https://github.com/PC2005-cloud/dsh-pet)，同时提供 VP9-alpha WebM 和 HEVC-alpha MOV，在 Chromium 与 WKWebView 中均可透明显示。
- FRP 远程访问：在 DSH 设置页配置服务器、TLS、Token、代理端口和公网 HTTPS 地址。
- 本地数据优先：FRP Token 保存到 macOS Keychain，网页端无法读取已保存的 Token。

## 界面预览

### 插件管理

![插件管理](docs/images/plugin-manager.png)

### 远程访问

<img src="docs/images/remote-access.png" width="760" alt="FRP 远程访问设置">

### Harness 更新

<img src="docs/images/update-check.png" width="420" alt="Harness 更新检查">

### 启动状态

<img src="docs/images/loading.png" width="300" alt="插件加载状态">

> 截图中的插件版本可能高于安装包内置版本，因为插件管理器支持独立升级。

## 安装

1. 从 [Releases](https://github.com/sunkeycn/dsh-desktop/releases/latest) 下载与你的 Mac 架构匹配的 DMG。
2. 打开 DMG，将 `DeepSeek Harness.app` 拖入“应用程序”。
3. 首次启动等待 App 自动准备 Node.js、Harness 和内置插件。

当前发布的 DMG 使用 ad-hoc 签名，没有 Apple Developer ID 公证。macOS 若阻止首次打开，请在“系统设置 → 隐私与安全性”中确认打开，或从源码自行构建。

### 系统要求

- macOS 12.0 或更高版本
- 可访问 npm、GitHub Releases 和 Node.js 下载站点的网络
- 当前 Release 标注其构建架构；本项目不会把单架构产物标记为 Universal

## 内置插件

| 插件 | 内置版本 | 用途 | 来源 |
| --- | --- | --- | --- |
| `dsh-pet` | `0.1.8` | 桌面宠物 | [PC2005-cloud/dsh-pet](https://github.com/PC2005-cloud/dsh-pet) |
| `dsh-better-sidebar` | `0.15.2` | 代码与工作区侧栏 | [omdsh-dev/DSH-better-sidebar](https://github.com/omdsh-dev/DSH-better-sidebar) |
| `dsh-frp-remote` | `0.2.0` | FRP 配置与隧道管理 | 本仓库 |

内置版本只用于首次安装和缺失修复。安装后可以通过“DeepSeek Harness → 插件管理…”独立检查更新。

## FRP 远程访问

DSH 设置页中的“远程访问”支持配置：

- FRP Server 地址和端口
- TLS 开关
- Token 鉴权
- 代理名称和远端端口
- 公网 HTTPS 地址

本地服务固定为 `127.0.0.1:3080`。配置文件位于 `~/.dsh/frp`，Token 存放于 macOS Keychain；本地配置 API 仅监听 `127.0.0.1:3081`，写操作需要可信 Origin 和 CSRF 令牌。

## 安全说明

- FRP 只提供网络隧道，不提供公网 HTTPS、登录认证或访问控制。
- 将 DSH 暴露到公网前，必须在入口层配置 HTTPS 和可靠的访问认证。
- 不要把 FRP Token、私钥、Cookie 或其他凭据提交到仓库、Issue 或日志中。
- 远程页面只能读取脱敏状态，不能读取或修改本机保存的 FRP Token。
- 插件会在本机 Harness 进程中运行，只安装你信任的插件和版本。

## 从源码构建

### 依赖

- macOS 12+
- Xcode Command Line Tools（Swift、codesign、iconutil）
- Node.js / npm
- `ffmpeg`（生成宠物 HEVC-alpha 资源）

### 构建命令

```bash
./build.sh
./build.sh --install
./build.sh --dmg
./build.sh --version 1.0.0 --install --dmg
```

构建脚本会：

1. 编译 Swift App。
2. 从 npm 获取清单锁定的插件版本。
3. 为宠物动画生成 WKWebView 使用的 HEVC-alpha MOV。
4. 从 frp Release 下载当前架构的 `frpc 0.71.0` 并校验 SHA-256。
5. 对 App 进行 ad-hoc 签名，并按参数安装或生成 DMG。

可以通过环境变量指定 ffmpeg：

```bash
FFMPEG_BIN=/path/to/ffmpeg ./build.sh --dmg
```

## 测试

```bash
swiftc -swift-version 5 -typecheck \
  -framework Cocoa -framework WebKit \
  main.swift PluginManager.swift

node --test tests/frp-config.test.mjs
```

## 项目结构

```text
.
├── main.swift                 # App 生命周期、WKWebView、自举与菜单
├── PluginManager.swift        # 原生插件管理窗口
├── plugin-catalog.json        # 内置插件清单
├── plugins/
│   ├── dsh-frp-remote/        # FRP 宿主插件和网页设置
│   └── dsh-pet/               # HEVC-alpha 转换与补丁
├── scripts/                   # Profile 迁移和种子清理脚本
├── tests/                     # FRP 配置测试
├── icon/                      # App 图标资源
└── build.sh                   # App / DMG 构建脚本
```

## 数据目录

- App 运行时：`~/Library/Application Support/DeepSeek Harness`
- DSH Profile：`~/.dsh/profiles/web`
- FRP 配置：`~/.dsh/frp`
- 启动日志：`~/.dsh/launcher.log`

退出桌面窗口不会停止已通过 `nohup` 启动的 Harness 服务。

## 第三方项目

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)：MIT
- [dsh-pet](https://github.com/PC2005-cloud/dsh-pet)：MIT
- [DSH-better-sidebar](https://github.com/omdsh-dev/DSH-better-sidebar)：MIT
- [frp](https://github.com/fatedier/frp)：Apache-2.0

第三方项目、插件及媒体资源继续适用各自的许可证和版权声明。本项目与 DeepSeek 官方不存在隶属或背书关系。
详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## License

[MIT](LICENSE)
