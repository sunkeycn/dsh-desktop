import Cocoa

struct PluginDescriptor: Codable {
    let id: String
    let displayName: String
    let summary: String
    let publisher: String
    let bundledVersion: String
    let seed: String
    let registryPackage: String?
    let dataPaths: [String]
}

struct PluginSnapshot {
    let descriptor: PluginDescriptor
    let installedVersion: String?
    let latestVersion: String?
    let enabled: Bool

    var isInstalled: Bool { installedVersion != nil }
    var hasUpdate: Bool {
        guard let installedVersion, let latestVersion else { return false }
        return isNewer(latestVersion, than: installedVersion)
    }
}

private struct PluginLifecycleState: Codable {
    var removed: [String] = []
}

final class PluginService {
    private let runtimeRoot: URL
    private let fileManager = FileManager.default
    private(set) var descriptors: [PluginDescriptor] = []

    init(runtimeRoot: URL) {
        self.runtimeRoot = runtimeRoot
        self.descriptors = loadCatalog()
    }

    private var dshBinURL: URL {
        runtimeRoot.appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
    }

    private var nodeURL: URL {
        runtimeRoot.appendingPathComponent("node/bin/node")
    }

    private var profileURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/profiles/web", isDirectory: true)
    }

    private var stateURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DeepSeek Harness/plugin-state.json")
    }

    private var seedRootURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("PluginSeeds", isDirectory: true)
    }

    private func loadCatalog() -> [PluginDescriptor] {
        guard let url = Bundle.main.url(forResource: "plugin-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode([PluginDescriptor].self, from: data) else {
            NSLog("DeepSeekHarness: plugin catalog is unavailable")
            return []
        }
        return catalog
    }

    private func loadLifecycleState() -> PluginLifecycleState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PluginLifecycleState.self, from: data) else {
            return PluginLifecycleState()
        }
        return state
    }

    private func saveLifecycleState(_ state: PluginLifecycleState) {
        do {
            try fileManager.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("DeepSeekHarness: failed to save plugin state: %@", error.localizedDescription)
        }
    }

    private func profileManifest() -> [String: Any] {
        let url = profileURL.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func installedVersion(for id: String) -> String? {
        let url = profileURL.appendingPathComponent("node_modules/\(id)/package.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["version"] as? String
    }

    private func needsBundledProvision(_ descriptor: PluginDescriptor) -> Bool {
        guard let installed = installedVersion(for: descriptor.id) else { return true }
        if descriptor.id == "dsh-pet" {
            let client = profileURL.appendingPathComponent("node_modules/dsh-pet/lib/client.js")
            let source = try? String(contentsOf: client, encoding: .utf8)
            return source?.contains("const isAppleWebKit") != true
        }
        if descriptor.registryPackage == nil {
            return isNewer(descriptor.bundledVersion, than: installed)
        }
        return false
    }

    private func enabledPluginIDs() -> Set<String> {
        let manifest = profileManifest()
        let dsh = manifest["dsh"] as? [String: Any]
        let profile = dsh?["profile"] as? [String: Any]
        return Set(profile?["bundles"] as? [String] ?? [])
    }

    func snapshots(latestVersions: [String: String] = [:]) -> [PluginSnapshot] {
        let enabled = enabledPluginIDs()
        return descriptors.map { descriptor in
            PluginSnapshot(
                descriptor: descriptor,
                installedVersion: installedVersion(for: descriptor.id),
                latestVersion: latestVersions[descriptor.id] ?? (descriptor.registryPackage == nil ? descriptor.bundledVersion : nil),
                enabled: enabled.contains(descriptor.id)
            )
        }
    }

    func provisionBundledPlugins(completion: @escaping (Bool, Bool) -> Void) {
        installBundledFrpc()
        runProfileMigration { [weak self] in
            guard let self else {
                completion(false, false)
                return
            }
            let removed = Set(self.loadLifecycleState().removed)
            let pending = self.descriptors.filter {
                !removed.contains($0.id) && self.needsBundledProvision($0)
            }
            guard !pending.isEmpty else {
                completion(true, false)
                return
            }
            NSLog("DeepSeekHarness: provisioning bundled plugins: %@", pending.map(\.id).joined(separator: ", "))
            self.installSequentially(pending, index: 0, allSucceeded: true) {
                completion($0, true)
            }
        }
    }

    private func installSequentially(_ pending: [PluginDescriptor], index: Int, allSucceeded: Bool,
                                     completion: @escaping (Bool) -> Void) {
        guard index < pending.count else {
            completion(allSucceeded)
            return
        }
        runProfileMigration { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            let force = self.installedVersion(for: pending[index].id) != nil
            self.install(pending[index], force: force) { [weak self] ok, output in
                guard let self else {
                    completion(false)
                    return
                }
                if !ok {
                    NSLog("DeepSeekHarness: failed to provision %@: %@", pending[index].id, output)
                }
                self.installSequentially(pending, index: index + 1,
                                         allSucceeded: allSucceeded && ok, completion: completion)
            }
        }
    }

    private func installBundledFrpc() {
        guard let source = Bundle.main.url(forResource: "frpc", withExtension: nil, subdirectory: "FRP") else {
            NSLog("DeepSeekHarness: bundled frpc is unavailable")
            return
        }
        let destination = runtimeRoot.deletingLastPathComponent().appendingPathComponent("bin/frpc")
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        } catch {
            NSLog("DeepSeekHarness: failed to install bundled frpc: %@", error.localizedDescription)
        }
    }

    private func runProfileMigration(completion: @escaping () -> Void) {
        guard let script = Bundle.main.url(forResource: "migrate-profile", withExtension: "cjs", subdirectory: "Scripts") else {
            completion()
            return
        }
        runProcess(nodeURL.path, [script.path, runtimeRoot.path, profileURL.path]) { _, _ in completion() }
    }

    func fetchLatestVersions(completion: @escaping ([String: String]) -> Void) {
        let registryPlugins = descriptors.filter { $0.registryPackage != nil }
        guard !registryPlugins.isEmpty else {
            completion([:])
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var result: [String: String] = [:]
        for descriptor in registryPlugins {
            guard let package = descriptor.registryPackage,
                  let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://registry.npmjs.org/\(encoded)/latest") else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { data, _, _ in
                defer { group.leave() }
                guard let data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let version = object["version"] as? String else { return }
                lock.lock()
                result[descriptor.id] = version
                lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { completion(result) }
    }

    func install(_ descriptor: PluginDescriptor, force: Bool = false,
                 completion: @escaping (Bool, String) -> Void) {
        guard let seedRootURL else {
            completion(false, "安装包中缺少插件资源")
            return
        }
        let seed = seedRootURL.appendingPathComponent(descriptor.seed)
        guard fileManager.fileExists(atPath: seed.path) else {
            completion(false, "找不到内置插件 \(descriptor.seed)")
            return
        }
        let wasEnabled = enabledPluginIDs().contains(descriptor.id)
        let finishInstall: (@escaping (Bool, String) -> Void) -> Void = { [weak self] callback in
            guard let self else {
                callback(false, "插件服务已停止")
                return
            }
            self.runPluginCommand([
                "add", seed.path, "--workspace-root", "--config.minimum-release-age=0",
            ]) { [weak self] ok, output in
                if ok, let self {
                    if force && !wasEnabled {
                        _ = self.setBundleEnabled(descriptor.id, enabled: false)
                    }
                    var state = self.loadLifecycleState()
                    state.removed.removeAll { $0 == descriptor.id }
                    self.saveLifecycleState(state)
                }
                callback(ok, output)
            }
        }
        guard force else {
            finishInstall(completion)
            return
        }

        // pnpm reuses the old lockfile integrity when a file tarball keeps the same
        // path and version. Remove it first so a corrected bundled seed is unpacked.
        runPluginCommand(["remove", descriptor.id, "--config.minimum-release-age=0"]) { ok, output in
            guard ok else {
                completion(false, output)
                return
            }
            finishInstall { installOK, installOutput in
                completion(installOK, output + installOutput)
            }
        }
    }

    func update(_ descriptor: PluginDescriptor, to version: String,
                completion: @escaping (Bool, String) -> Void) {
        let wasEnabled = enabledPluginIDs().contains(descriptor.id)
        let operation: (@escaping (Bool, String) -> Void) -> Void
        if version == descriptor.bundledVersion || descriptor.registryPackage == nil {
            operation = { callback in self.install(descriptor, force: true, completion: callback) }
        } else if let package = descriptor.registryPackage {
            operation = { callback in
                self.runPluginCommand(["add", "\(package)@\(version)", "--config.minimum-release-age=0"], completion: callback)
            }
        } else {
            completion(false, "没有可用的升级来源")
            return
        }
        operation { [weak self] ok, output in
            guard let self else {
                completion(false, output)
                return
            }
            if ok && !wasEnabled {
                _ = self.setBundleEnabled(descriptor.id, enabled: false)
            }
            completion(ok, output)
        }
    }

    func setEnabled(_ descriptor: PluginDescriptor, enabled: Bool) -> Bool {
        guard descriptor.isInstalled(in: profileURL) else { return false }
        return setBundleEnabled(descriptor.id, enabled: enabled)
    }

    private func setBundleEnabled(_ id: String, enabled: Bool) -> Bool {
        let url = profileURL.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        var dsh = manifest["dsh"] as? [String: Any] ?? [:]
        var profile = dsh["profile"] as? [String: Any] ?? [:]
        var bundles = profile["bundles"] as? [String] ?? []
        if enabled {
            if !bundles.contains(id) { bundles.append(id) }
        } else {
            bundles.removeAll { $0 == id }
        }
        profile["bundles"] = bundles
        dsh["profile"] = profile
        manifest["dsh"] = dsh
        do {
            let output = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            var text = String(data: output, encoding: .utf8) ?? "{}"
            text += "\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSLog("DeepSeekHarness: failed to update profile bundles: %@", error.localizedDescription)
            return false
        }
    }

    func remove(_ descriptor: PluginDescriptor, deleteData: Bool,
                completion: @escaping (Bool, String) -> Void) {
        runPluginCommand(["remove", descriptor.id, "--config.minimum-release-age=0"]) { [weak self] ok, output in
            guard let self else {
                completion(false, output)
                return
            }
            if ok {
                var state = self.loadLifecycleState()
                if !state.removed.contains(descriptor.id) { state.removed.append(descriptor.id) }
                self.saveLifecycleState(state)
                if deleteData { self.deletePluginData(descriptor) }
            }
            completion(ok, output)
        }
    }

    private func deletePluginData(_ descriptor: PluginDescriptor) {
        for path in descriptor.dataPaths {
            let expanded = NSString(string: path).expandingTildeInPath
            try? fileManager.removeItem(atPath: expanded)
        }
        let generic = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/plugins/\(descriptor.id)")
        try? fileManager.removeItem(at: generic)
        if descriptor.id == "dsh-frp-remote" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["delete-generic-password", "-s", "com.deepseek.harness.frp", "-a", "token"]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private func runPluginCommand(_ arguments: [String], completion: @escaping (Bool, String) -> Void) {
        runProcess(nodeURL.path, [dshBinURL.path, "plugin", "--profile", "web"] + arguments, completion: completion)
    }

    private func runProcess(_ executable: String, _ arguments: [String],
                            completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = self.runtimeRoot.appendingPathComponent("node/bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(process.terminationStatus == 0, output) }
            } catch {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }
}

private extension PluginDescriptor {
    func isInstalled(in profileURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: profileURL.appendingPathComponent("node_modules/\(id)/package.json").path)
    }
}

protocol PluginManagerControllerDelegate: AnyObject {
    func pluginManagerRequestedHarnessRestart(_ controller: PluginManagerController)
}

final class PluginManagerController: NSWindowController {
    weak var delegate: PluginManagerControllerDelegate?

    private let service: PluginService
    private let listStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var latestVersions: [String: String] = [:]
    private var currentSnapshots: [PluginSnapshot] = []
    private var operationInProgress = false
    private var restartRequired = false

    init(service: PluginService) {
        self.service = service
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "插件管理"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        reload(checkUpdates: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "已安装插件")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        let spacer = NSView()
        let checkButton = NSButton(title: "检查插件更新", target: self, action: #selector(checkUpdates(_:)))
        checkButton.bezelStyle = .rounded
        header.addArrangedSubview(heading)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(checkButton)
        content.addSubview(header)

        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 0
        listStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(listStack)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        let footerSpacer = NSView()
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow(_:)))
        let restartButton = NSButton(title: "重新启动 Harness", target: self, action: #selector(restartHarness(_:)))
        restartButton.bezelStyle = .rounded
        restartButton.keyEquivalent = "\r"
        footer.addArrangedSubview(statusLabel)
        footer.addArrangedSubview(footerSpacer)
        footer.addArrangedSubview(closeButton)
        footer.addArrangedSubview(restartButton)
        content.addSubview(footer)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            listStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            listStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            listStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            footer.topAnchor.constraint(greaterThanOrEqualTo: listStack.bottomAnchor, constant: 16),
        ])
    }

    private func reload(checkUpdates: Bool = false) {
        currentSnapshots = service.snapshots(latestVersions: latestVersions)
        rebuildRows()
        if checkUpdates { fetchLatestVersions() }
    }

    private func rebuildRows() {
        for view in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, snapshot) in currentSnapshots.enumerated() {
            listStack.addArrangedSubview(makeRow(snapshot, index: index))
        }
        let enabledCount = currentSnapshots.filter { $0.enabled }.count
        let suffix = restartRequired ? " · 重启后生效" : ""
        statusLabel.stringValue = "\(enabledCount) 个插件已启用\(suffix)"
    }

    private func makeRow(_ snapshot: PluginSnapshot, index: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 82).isActive = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(icon)

        let name = NSTextField(labelWithString: snapshot.descriptor.displayName)
        name.font = .systemFont(ofSize: 14, weight: .medium)
        let detail = NSTextField(labelWithString: "\(snapshot.descriptor.summary) · \(snapshot.descriptor.publisher)")
        detail.textColor = .secondaryLabelColor
        let copy = NSStackView(views: [name, detail])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3
        copy.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(copy)

        let versionText: String
        if let installed = snapshot.installedVersion {
            if snapshot.hasUpdate, let latest = snapshot.latestVersion {
                versionText = "\(installed) → \(latest)"
            } else {
                versionText = installed
            }
        } else {
            versionText = "未安装"
        }
        let version = NSTextField(labelWithString: versionText)
        version.alignment = .right
        version.textColor = snapshot.hasUpdate ? .controlAccentColor : .secondaryLabelColor
        version.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(version)

        let actionTitle = snapshot.isInstalled ? "升级" : "安装"
        let action = NSButton(title: actionTitle, target: self, action: #selector(performPrimaryAction(_:)))
        action.tag = index
        action.bezelStyle = .rounded
        action.isEnabled = !operationInProgress && (!snapshot.isInstalled || snapshot.hasUpdate)
        action.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(action)

        let toggle = NSSwitch()
        toggle.tag = index
        toggle.state = snapshot.enabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(togglePlugin(_:))
        toggle.isEnabled = !operationInProgress && snapshot.isInstalled
        toggle.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(toggle)

        let more = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "更多操作") ?? NSImage(),
                            target: self,
                            action: #selector(showMoreMenu(_:)))
        more.tag = index
        more.bezelStyle = .inline
        more.isBordered = false
        more.isEnabled = !operationInProgress && snapshot.isInstalled
        more.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(more)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(divider)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            copy.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            copy.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            copy.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            more.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
            more.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            more.widthAnchor.constraint(equalToConstant: 28),
            toggle.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            action.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -12),
            action.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            action.widthAnchor.constraint(greaterThanOrEqualToConstant: 62),
            version.trailingAnchor.constraint(equalTo: action.leadingAnchor, constant: -12),
            version.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            version.leadingAnchor.constraint(greaterThanOrEqualTo: copy.trailingAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    private func fetchLatestVersions() {
        statusLabel.stringValue = "正在检查插件更新…"
        service.fetchLatestVersions { [weak self] versions in
            guard let self else { return }
            self.latestVersions = versions
            self.reload()
        }
    }

    @objc private func checkUpdates(_ sender: Any?) {
        guard !operationInProgress else { return }
        fetchLatestVersions()
    }

    @objc private func performPrimaryAction(_ sender: NSButton) {
        guard currentSnapshots.indices.contains(sender.tag), !operationInProgress else { return }
        let snapshot = currentSnapshots[sender.tag]
        beginOperation(snapshot.isInstalled ? "正在升级 \(snapshot.descriptor.displayName)…" : "正在安装 \(snapshot.descriptor.displayName)…")
        let completion: (Bool, String) -> Void = { [weak self] ok, output in
            self?.finishOperation(ok: ok, output: output)
        }
        if snapshot.isInstalled {
            guard let latestVersion = snapshot.latestVersion else {
                finishOperation(ok: false, output: "无法确定目标版本")
                return
            }
            service.update(snapshot.descriptor, to: latestVersion, completion: completion)
        } else {
            service.install(snapshot.descriptor, completion: completion)
        }
    }

    @objc private func togglePlugin(_ sender: NSSwitch) {
        guard currentSnapshots.indices.contains(sender.tag), !operationInProgress else { return }
        let snapshot = currentSnapshots[sender.tag]
        let enabled = sender.state == .on
        if service.setEnabled(snapshot.descriptor, enabled: enabled) {
            restartRequired = true
            reload()
        } else {
            sender.state = snapshot.enabled ? .on : .off
            showError("无法修改插件状态", detail: "请检查 ~/.dsh/profiles/web/package.json 的权限。")
        }
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        guard currentSnapshots.indices.contains(sender.tag) else { return }
        let menu = NSMenu()
        let item = NSMenuItem(title: "移除…", action: #selector(removePlugin(_:)), keyEquivalent: "")
        item.target = self
        item.tag = sender.tag
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func removePlugin(_ sender: NSMenuItem) {
        guard currentSnapshots.indices.contains(sender.tag), !operationInProgress else { return }
        let snapshot = currentSnapshots[sender.tag]
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "移除 \(snapshot.descriptor.displayName)？"
        alert.informativeText = "插件将从 DSH 中卸载。默认保留插件数据，以便以后重新安装。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "同时删除插件数据"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let deleteData = alert.suppressionButton?.state == .on
        beginOperation("正在移除 \(snapshot.descriptor.displayName)…")
        service.remove(snapshot.descriptor, deleteData: deleteData) { [weak self] ok, output in
            self?.finishOperation(ok: ok, output: output)
        }
    }

    private func beginOperation(_ text: String) {
        operationInProgress = true
        statusLabel.stringValue = text
        rebuildRows()
    }

    private func finishOperation(ok: Bool, output: String) {
        operationInProgress = false
        if ok {
            restartRequired = true
            reload(checkUpdates: true)
        } else {
            reload()
            showError("插件操作失败", detail: output.isEmpty ? "请检查网络和 ~/.dsh 目录权限。" : output)
        }
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = String(detail.suffix(1600))
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func restartHarness(_ sender: Any?) {
        restartRequired = false
        delegate?.pluginManagerRequestedHarnessRestart(self)
    }

    @objc private func closeWindow(_ sender: Any?) {
        close()
    }
}
