import Cocoa
import WebKit

let kURL = "http://127.0.0.1:3080"
let kNodeVersion = "25.7.0"
let kRegistryPackage = "https://registry.npmjs.org/@deepseek-ai%2fdsh"

func isInternal(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "127.0.0.1" || host == "localhost" || host == "::1"
}

/// Single-quote a string for safe embedding in a POSIX shell command line.
func sq(_ s: String) -> String {
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Parse a `major.minor.patch[-prerelease]` version into a comparable tuple.
/// The fourth component is the prerelease number: Int.max for a release, N for `-rc.N`, 0 otherwise.
func versionTuple(_ v: String) -> (Int, Int, Int, Int) {
    var major = 0, minor = 0, patch = 0, pre = Int.max
    let parts = v.split(separator: "-", maxSplits: 1)
    let nums = parts[0].split(separator: ".").compactMap { Int($0) }
    if nums.count > 0 { major = nums[0] }
    if nums.count > 1 { minor = nums[1] }
    if nums.count > 2 { patch = nums[2] }
    if parts.count > 1 {
        let preNum = parts[1].split(separator: ".").last.flatMap { Int($0) }
        pre = preNum ?? 0
    }
    return (major, minor, patch, pre)
}

/// True when `a` is a newer version than `b`.
func isNewer(_ a: String, than b: String) -> Bool {
    let va = versionTuple(a), vb = versionTuple(b)
    if va.0 != vb.0 { return va.0 > vb.0 }
    if va.1 != vb.1 { return va.1 > vb.1 }
    if va.2 != vb.2 { return va.2 > vb.2 }
    return va.3 > vb.3
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, URLSessionDownloadDelegate, PluginManagerControllerDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    // Installer UI state
    var progressBar: NSProgressIndicator?
    var statusLabel: NSTextField?
    var installSession: URLSession?
    var installTarball: URL?
    var installDist = "darwin-arm64"
    var installDownloadFinished = false

    // Bootstrap status line (update check / upgrade)
    var bootstrapStatusLabel: NSTextField?

    // About panel state
    var aboutPanel: NSPanel?
    var aboutHarnessLabel: NSTextField?

    // Update state
    var upgradeInProgress = false
    var checkUpdateItem: NSMenuItem?

    // Bundled plugin lifecycle
    var pluginService: PluginService!
    var pluginManagerController: PluginManagerController?
    var bundledPluginsProvisioned = false
    var bootstrapInProgress = false
    var serverLaunchInProgress = false

    // MARK: - Runtime paths

    func runtimeRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DeepSeek Harness/runtime", isDirectory: true)
    }

    func nodeBinURL() -> URL { runtimeRoot().appendingPathComponent("node/bin/node") }
    func dshBinJSURL() -> URL { runtimeRoot().appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js") }

    func runtimeIsInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: nodeBinURL().path)
            && FileManager.default.fileExists(atPath: dshBinJSURL().path)
    }

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        pluginService = PluginService(runtimeRoot: runtimeRoot())
        buildMenu()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // macOS WKWebView exposes no `scrollView`, and its internal NSScrollView is not part of
        // the UI-process view hierarchy (verified: WKWebView -> WKFlippedView only). The
        // rubber-band overscroll bounce is implemented in WebKit's CSS scroll layer, so disable it
        // there with `overscroll-behavior: none` on every element.
        let noBounceJS = """
        (function () {
          var s = document.createElement('style');
          s.id = 'dsh-no-bounce';
          s.textContent = 'html,body{overscroll-behavior:none !important}*{overscroll-behavior:none !important}';
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: noBounceJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Fallback for older macOS where the scroll view may still be reachable as a subview.
        disableWebViewBounce(webView)

        let contentRect = NSRect(x: 0, y: 0, width: 1320, height: 900)
        window = NSWindow(contentRect: contentRect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "DeepSeek Harness"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("DeepSeekHarnessMainWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if runtimeIsInstalled() {
            showBootstrap()
        } else {
            showInstaller()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Installer UI

    private func showInstaller() {
        let v = NSView(frame: .zero)

        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.doubleValue = 0
        bar.controlSize = .regular
        bar.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(bar)

        let status = NSTextField(labelWithString: "准备安装…")
        status.font = .systemFont(ofSize: 13)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(status)

        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            bar.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            bar.widthAnchor.constraint(equalToConstant: 460),
            status.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            status.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 16),
            status.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
        ])

        progressBar = bar
        statusLabel = status
        window.contentView = v
        beginInstall()
    }

    private func setStatus(_ s: String) {
        statusLabel?.stringValue = s
    }

    private func setProgress(_ pct: Double) {
        progressBar?.doubleValue = pct
    }

    private func setIndeterminate(_ b: Bool) {
        guard let bar = progressBar else { return }
        bar.isIndeterminate = b
        if b { bar.startAnimation(nil) } else { bar.stopAnimation(nil) }
    }

    // MARK: - Install pipeline

    private func detectArch() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/uname")
        p.arguments = ["-m"]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return "arm64"
        }
        let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "arm64"
        return s
    }

    private func beginInstall() {
        installDownloadFinished = false
        installTarball = nil
        let arch = detectArch()
        installDist = (arch == "arm64") ? "darwin-arm64" : "darwin-x64"
        setProgress(0)
        setIndeterminate(false)
        setStatus("检测到 macOS \(arch)，正在下载 Node v\(kNodeVersion)（\(installDist)）…")
        guard let url = URL(string: "https://nodejs.org/dist/v\(kNodeVersion)/node-v\(kNodeVersion)-\(installDist).tar.gz") else {
            fail("下载地址无效")
            return
        }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
        installSession = session
        session.downloadTask(with: url).resume()
    }

    private func extractAndInstall() {
        // Runs on a background queue.
        let rt = runtimeRoot()
        let nodeDir = rt.appendingPathComponent("node")
        do {
            try? FileManager.default.removeItem(at: nodeDir)
            try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        } catch {
            DispatchQueue.main.async { self.fail("创建运行时目录失败") }
            return
        }
        DispatchQueue.main.async {
            self.setIndeterminate(true)
            self.setStatus("正在解压运行时…")
        }
        guard let tarball = installTarball else {
            DispatchQueue.main.async { self.fail("找不到下载文件") }
            return
        }
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tarball.path, "-C", nodeDir.path, "--strip-components=1"]
        do {
            try tar.run()
            tar.waitUntilExit()
        } catch {
            DispatchQueue.main.async { self.fail("解压失败") }
            return
        }
        if tar.terminationStatus != 0 {
            DispatchQueue.main.async { self.fail("解压 Node 失败") }
            return
        }
        // Write a minimal manifest so npm has a package root to install into.
        let manifest = "{\"name\":\"dsh-runtime\",\"private\":true,\"version\":\"1.0.0\"}\n"
        try? manifest.write(to: rt.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        DispatchQueue.main.async {
            self.setStatus("正在安装 DeepSeek Harness 依赖（首次约 1~3 分钟）…")
        }
        runNpmInstall()
    }

    private func runNpmInstall() {
        let node = nodeBinURL().path
        let npmCli = runtimeRoot().appendingPathComponent("node/lib/node_modules/npm/bin/npm-cli.js").path
        runStreaming(node, [npmCli, "install", "--no-audit", "--no-fund", "@deepseek-ai/dsh"],
                     cwd: runtimeRoot(),
                     onLine: { [weak self] line in
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty {
                            self?.setStatus("正在安装依赖… \(t)")
                        }
                     },
                     completion: { [weak self] ok in
                        guard let self = self else { return }
                        if ok && self.runtimeIsInstalled() {
                            self.setStatus("安装完成，正在启动…")
                            DispatchQueue.main.async { self.transitionToApp() }
                        } else {
                            self.fail("依赖安装失败，请检查网络后重试")
                        }
                     })
    }

    private func fail(_ msg: String) {
        setIndeterminate(false)
        setProgress(0)
        setStatus("✗ \(msg)")
        addRetryButton()
    }

    private func addRetryButton() {
        guard let content = window.contentView, let status = statusLabel else { return }
        if content.viewWithTag(777) != nil { return }
        let btn = NSButton(title: "重试", target: self, action: #selector(retryInstall))
        btn.tag = 777
        btn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            btn.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 18),
        ])
    }

    @objc private func retryInstall() {
        window.contentView?.viewWithTag(777)?.removeFromSuperview()
        beginInstall()
    }

    private func transitionToApp() {
        progressBar = nil
        statusLabel = nil
        showBootstrap()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100
            setProgress(pct)
            setStatus("正在下载 Node v\(kNodeVersion)（\(installDist)）… \(Int(pct))%")
        } else {
            setIndeterminate(true)
            setStatus("正在下载 Node v\(kNodeVersion)（\(installDist)）…")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        installDownloadFinished = true
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-node-\(installDist).tar.gz")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            fail("下载文件处理失败")
            return
        }
        installTarball = dest
        session.invalidateAndCancel()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.extractAndInstall()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = error, !installDownloadFinished {
            fail("下载失败：\(e.localizedDescription)")
        }
    }

    // MARK: - App bootstrap (server check / start / load)

    private func showBootstrap() {
        window.contentView = makePlaceholder(text: "正在启动 DeepSeek Harness…", showSpinner: true)
        guard !bundledPluginsProvisioned else {
            bootstrap()
            return
        }
        setBootstrapStatus("正在准备内置插件…")
        pluginService.provisionBundledPlugins { [weak self] ok, changed in
            guard let self else { return }
            self.bundledPluginsProvisioned = true
            if !ok { self.setBootstrapStatus("部分内置插件安装失败，可稍后在插件管理中重试") }
            guard changed else {
                self.bootstrap()
                return
            }
            self.setBootstrapStatus("内置插件已更新，正在重启 Harness…")
            self.stopServer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.bootstrap()
            }
        }
    }

    private func bootstrap() {
        guard !bootstrapInProgress else {
            NSLog("DeepSeekHarness: ignored duplicate bootstrap request")
            return
        }
        bootstrapInProgress = true
        serverIsUp { [weak self] up in
            guard let self = self else { return }
            if up {
                self.loadApp()
            } else {
                self.checkForUpdateThenStart()
            }
        }
    }

    private func serverIsUp(_ completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: kURL) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
            let up = (resp as? HTTPURLResponse) != nil
            DispatchQueue.main.async { completion(up) }
        }
        task.resume()
    }

    private func startServer() {
        guard !serverLaunchInProgress else {
            NSLog("DeepSeekHarness: ignored duplicate server start request")
            return
        }
        serverLaunchInProgress = true
        serverIsUp { [weak self] up in
            guard let self else { return }
            if up {
                self.serverLaunchInProgress = false
                NSLog("DeepSeekHarness: skipped server start because port 3080 is already available")
                return
            }
            self.launchServerProcess()
        }
    }

    private func launchServerProcess() {
        let nodeDir = runtimeRoot().appendingPathComponent("node/bin").path
        let nodeBin = nodeBinURL().path
        let binJs = dshBinJSURL().path
        let trustedHostArgument = frpTrustedAuthority().map { " --trusted-host \(sq($0))" } ?? ""
        let cmd = "mkdir -p \"$HOME/.dsh\"; export PATH=\(sq(nodeDir)):/usr/bin:/bin:/usr/sbin:/sbin; cd \"$HOME\"; nohup \(sq(nodeBin)) \(sq(binJs)) web --no-open\(trustedHostArgument) >> \"$HOME/.dsh/launcher.log\" 2>&1 &"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        do {
            try p.run()
        } catch {
            serverLaunchInProgress = false
            NSLog("DeepSeekHarness: failed to start server: %@", error.localizedDescription)
        }
    }

    private func frpTrustedAuthority() -> String? {
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/frp/config.json")
        guard let data = try? Data(contentsOf: config),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publicURL = object["publicUrl"] as? String,
              let components = URLComponents(string: publicURL),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else { return nil }
        if let port = components.port { return "\(host):\(port)" }
        return host
    }

    private func pollUntilUp(deadline: Date) {
        guard Date() < deadline else {
            bootstrapInProgress = false
            serverLaunchInProgress = false
            window.contentView = makePlaceholder(text: "启动失败，请查看 ~/.dsh/launcher.log", showSpinner: false)
            return
        }
        serverIsUp { [weak self] up in
            guard let self = self else { return }
            if up {
                self.loadApp()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.pollUntilUp(deadline: deadline)
                }
            }
        }
    }

    private func loadApp() {
        guard let url = URL(string: kURL) else { return }
        bootstrapInProgress = false
        serverLaunchInProgress = false
        window.contentView = webView
        webView.load(URLRequest(url: url))
    }

    // MARK: - Update check / upgrade

    private func installedVersion() -> String? {
        let p = runtimeRoot().appendingPathComponent("node_modules/@deepseek-ai/dsh/package.json").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = obj["version"] as? String else { return nil }
        return v
    }

    private func fetchLatestVersion(_ completion: @escaping (String?) -> Void) {
        guard let url = URL(string: kRegistryPackage) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
            var v: String? = nil
            if let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tags = obj["dist-tags"] as? [String: String] {
                // The package ships release candidates on both `latest` and `next`;
                // use whichever tag currently points to the newer version.
                let latest = tags["latest"]
                let next = tags["next"]
                if let latest = latest { v = latest }
                if let next = next, next != v, v == nil || isNewer(next, than: v!) {
                    v = next
                }
            }
            DispatchQueue.main.async { completion(v) }
        }
        task.resume()
    }

    private func checkForUpdateThenStart() {
        setBootstrapStatus("正在检查更新…")
        let current = installedVersion() ?? "0.0.0"
        fetchLatestVersion { [weak self] latest in
            guard let self = self else { return }
            if let latest = latest, isNewer(latest, than: current) {
                self.setBootstrapStatus("发现新版本 \(latest)（当前 \(current)），正在升级…")
                self.upgrade(to: latest) { _ in
                    self.startServer()
                    self.pollUntilUp(deadline: Date().addingTimeInterval(90))
                }
            } else {
                self.setBootstrapStatus("已是最新版本，正在启动…")
                self.startServer()
                self.pollUntilUp(deadline: Date().addingTimeInterval(90))
            }
        }
    }

    private func upgrade(to version: String, completion: @escaping (Bool) -> Void) {
        let node = nodeBinURL().path
        let npmCli = runtimeRoot().appendingPathComponent("node/lib/node_modules/npm/bin/npm-cli.js").path
        runStreaming(node, [npmCli, "install", "--no-audit", "--no-fund", "@deepseek-ai/dsh@\(version)"],
                     cwd: runtimeRoot(),
                     onLine: { [weak self] line in
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { self?.setBootstrapStatus("正在升级… \(t)") }
                     },
                     completion: { ok in
                        DispatchQueue.main.async { completion(ok) }
                     })
    }
    @objc func checkForUpgradeFromMenu(_ sender: Any?) {
        guard !upgradeInProgress else { return }

        guard runtimeIsInstalled(), let current = installedVersion() else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "尚未安装 Harness"
            alert.informativeText = "完成首次安装后即可检查升级。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }

        checkUpdateItem?.isEnabled = false
        checkUpdateItem?.title = "正在检查更新…"
        fetchLatestVersion { [weak self] latest in
            guard let self = self else { return }
            self.checkUpdateItem?.isEnabled = true
            self.checkUpdateItem?.title = "检查升级…"

            guard let latest = latest else {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "检查升级失败"
                alert.informativeText = "无法连接 npm registry，请检查网络后重试。"
                alert.addButton(withTitle: "好")
                alert.runModal()
                return
            }

            if isNewer(latest, than: current) {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "发现新版本"
                alert.informativeText = "当前 Harness 版本：\(current)\n最新 Harness 版本：\(latest)\n\n是否立即升级？"
                alert.addButton(withTitle: "立即升级")
                alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.performMenuUpgrade(to: latest)
                }
            } else {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "已是最新版本"
                alert.informativeText = "当前 Harness 版本：\(current)\n最新 Harness 版本：\(latest)"
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }

    private func performMenuUpgrade(to version: String) {
        guard !upgradeInProgress else { return }
        upgradeInProgress = true
        checkUpdateItem?.isEnabled = false
        checkUpdateItem?.title = "正在升级…"

        window.contentView = makePlaceholder(text: "正在升级 DeepSeek Harness…", showSpinner: true)
        setBootstrapStatus("正在升级到 \(version)…")

        upgrade(to: version) { [weak self] ok in
            guard let self = self else { return }
            if !ok {
                self.upgradeInProgress = false
                self.checkUpdateItem?.isEnabled = true
                self.checkUpdateItem?.title = "检查升级…"
                self.window.contentView = self.makePlaceholder(text: "升级失败", showSpinner: false)
                self.setBootstrapStatus("请查看 ~/.dsh/launcher.log 后重试")
                return
            }

            self.setBootstrapStatus("升级完成，正在重启服务…")
            self.aboutHarnessLabel?.stringValue = "Harness 版本：\(version)"
            self.stopServer()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                self.upgradeInProgress = false
                self.checkUpdateItem?.isEnabled = true
                self.checkUpdateItem?.title = "检查升级…"
                self.startServer()
                self.pollUntilUp(deadline: Date().addingTimeInterval(90))
            }
        }
    }

    private func stopServer() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "/usr/sbin/lsof -ti tcp:3080 | xargs kill 2>/dev/null || true"]
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            NSLog("DeepSeekHarness: failed to stop server: %@", error.localizedDescription)
        }
    }

    private func setBootstrapStatus(_ s: String) {
        bootstrapStatusLabel?.stringValue = s
    }

    private func makePlaceholder(text: String, showSpinner: Bool) -> NSView {
        let v = NSView(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15)
        label.textColor = showSpinner ? .secondaryLabelColor : .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(status)
        bootstrapStatusLabel = status

        if showSpinner {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .large
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.startAnimation(nil)
            v.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -24),
                label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
                status.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                status.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
                status.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                status.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                status.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
                status.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            ])
        }
        return v
    }

    private func launcherVersion() -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.isEmpty { return v }
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !v.isEmpty { return v }
        return "1.0.0"
    }

    // MARK: - About panel

    @objc func showAboutPanel(_ sender: Any?) {
        if let panel = aboutPanel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "关于 DeepSeek Harness"
        panel.isReleasedWhenClosed = false
        panel.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 250))

        let iconView = NSImageView(frame: NSRect(x: 178, y: 158, width: 64, height: 64))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(iconView)

        let titleLabel = NSTextField(frame: NSRect(x: 20, y: 122, width: 380, height: 26))
        titleLabel.stringValue = "DeepSeek Harness"
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        content.addSubview(titleLabel)

        let versionLabel = NSTextField(frame: NSRect(x: 20, y: 92, width: 380, height: 22))
        versionLabel.stringValue = "版本：\(launcherVersion())"
        versionLabel.font = NSFont.systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.isEditable = false
        versionLabel.isBordered = false
        versionLabel.drawsBackground = false
        content.addSubview(versionLabel)

        let harnessLabel = NSTextField(frame: NSRect(x: 20, y: 66, width: 380, height: 22))
        harnessLabel.stringValue = "Harness 版本：获取中…"
        harnessLabel.font = NSFont.systemFont(ofSize: 13)
        harnessLabel.textColor = .secondaryLabelColor
        harnessLabel.alignment = .center
        harnessLabel.isEditable = false
        harnessLabel.isBordered = false
        harnessLabel.drawsBackground = false
        content.addSubview(harnessLabel)

        let button = NSButton(frame: NSRect(x: 170, y: 18, width: 80, height: 28))
        button.title = "好"
        button.target = self
        button.action = #selector(closeAboutPanel(_:))
        button.bezelStyle = .rounded
        content.addSubview(button)

        panel.contentView = content
        aboutPanel = panel
        aboutHarnessLabel = harnessLabel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        refreshAboutHarnessVersion()
    }

    @objc func closeAboutPanel(_ sender: Any?) {
        aboutPanel?.close()
    }

    private func refreshAboutHarnessVersion() {
        if let installed = installedVersion() {
            aboutHarnessLabel?.stringValue = "Harness 版本：\(installed)"
        } else {
            aboutHarnessLabel?.stringValue = "Harness 版本：获取中…"
            fetchLatestVersion { [weak self] latest in
                guard let self = self else { return }
                self.aboutHarnessLabel?.stringValue = latest.map { "Harness 版本：\($0)" } ?? "Harness 版本：未安装"
            }
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let aboutItem = NSMenuItem(title: "关于 DeepSeek Harness", action: #selector(showAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        let checkUpdateItem = NSMenuItem(title: "检查升级…", action: #selector(checkForUpgradeFromMenu(_:)), keyEquivalent: "")
        checkUpdateItem.target = self
        self.checkUpdateItem = checkUpdateItem
        appMenu.addItem(checkUpdateItem)

        let pluginManagerItem = NSMenuItem(title: "插件管理…", action: #selector(showPluginManager(_:)), keyEquivalent: "")
        pluginManagerItem.target = self
        appMenu.addItem(pluginManagerItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 DeepSeek Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        viewItem.submenu = viewMenu
        let reloadItem = NSMenuItem(title: "重新加载", action: #selector(reload(_:)), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)
        viewMenu.addItem(NSMenuItem.separator())

        let openInBrowserItem = NSMenuItem(title: "在浏览器中打开", action: #selector(openInBrowser(_:)), keyEquivalent: "")
        openInBrowserItem.target = self
        viewMenu.addItem(openInBrowserItem)

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc func reload(_ sender: Any?) {
        webView?.reload()
    }

    @objc func openInBrowser(_ sender: Any?) {
        if let url = URL(string: kURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showPluginManager(_ sender: Any?) {
        if pluginManagerController == nil {
            let controller = PluginManagerController(service: pluginService)
            controller.delegate = self
            pluginManagerController = controller
        }
        pluginManagerController?.showWindow(nil)
        pluginManagerController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func pluginManagerRequestedHarnessRestart(_ controller: PluginManagerController) {
        controller.close()
        window.contentView = makePlaceholder(text: "正在重新启动 DeepSeek Harness…", showSpinner: true)
        setBootstrapStatus("正在应用插件和远程访问配置…")
        stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.startServer()
            self.pollUntilUp(deadline: Date().addingTimeInterval(90))
        }
    }

    /// WKWebView does not expose `scrollView` on macOS, so walk its view hierarchy to find the
    /// internal NSScrollView and turn off the rubber-band overscroll bounce.
    private func disableWebViewBounce(_ webView: WKWebView) {
        var stack = webView.subviews
        while !stack.isEmpty {
            let view = stack.removeLast()
            if let scroll = view as? NSScrollView {
                scroll.verticalScrollElasticity = .none
                scroll.horizontalScrollElasticity = .none
            }
            stack.append(contentsOf: view.subviews)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-apply after each navigation in case WebKit rebuilt its internal scroll view.
        disableWebViewBounce(webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, navigationAction.navigationType == .linkActivated {
            if !isInternal(url) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isInternal(url) {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    // MARK: - Process helpers

    private func runStreaming(_ exec: String, _ args: [String], cwd: URL,
                              onLine: @escaping (String) -> Void,
                              completion: @escaping (Bool) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exec)
        p.arguments = args
        p.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        let nodeBinDir = runtimeRoot().appendingPathComponent("node/bin").path
        env["PATH"] = nodeBinDir + ":/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buf = ""
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                buf += s
                while let nl = buf.firstIndex(of: "\n") {
                    let line = String(buf[buf.startIndex..<nl])
                    buf.removeSubrange(buf.startIndex...nl)
                    DispatchQueue.main.async { onLine(line) }
                }
            }
        }
        p.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
        }
        do {
            try p.run()
        } catch {
            DispatchQueue.main.async { completion(false) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
