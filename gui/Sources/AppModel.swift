import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Page: String, CaseIterable { case connection = "连接", setup = "设置", help = "帮助" }
enum LinkState { case unconfigured, off, busy, on, recovery }

private enum BackdropSession {
    // One selection per process; reopening the window does not change the scene.
    static let city: Int = {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "lastBackdropCity") as? Int
        let next = (0..<4).filter { $0 != previous }.randomElement()!
        defaults.set(next, forKey: "lastBackdropCity")
        return next
    }()
}

@MainActor final class AppModel: ObservableObject {
    @Published var page: Page = .connection
    @Published var state: LinkState = .unconfigured
    @Published var config: ConnectionConfig?
    @Published var message: String?
    @Published var busyText = "正在连接"
    @Published var checkResult: String?
    @Published var checking = false
    @Published var setupStep = 1
    let paths: AppPaths
    let engine: Engine
    let network: MacNetwork
    let presetURL: URL?
    let isPreview: Bool
    let animatePreview: Bool
    let backdropCity: Int
    private var timer: Timer?
    private var mainWindow: NSWindow?
    private lazy var updates = AppUpdates()
    var busy: Bool { state == .busy }
    var hasConfig: Bool { config != nil }
    var hasPreset: Bool { presetURL != nil }
    var installed: Bool { Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications" }
    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版" }

    init(preview: LinkState? = nil, previewCity: Int = 1, animatePreview: Bool = false, paths: AppPaths = .live) {
        self.animatePreview = animatePreview
        backdropCity = preview == nil ? BackdropSession.city : previewCity
        self.paths = paths
        let binary = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sing-box")
        engine = Engine(paths: paths, executable: binary); network = MacNetwork(paths: paths)
        let preset = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("连接配置.qinglink")
        presetURL = FileManager.default.fileExists(atPath: preset.path) ? preset : nil
        isPreview = preview != nil
        if let preview {
            state = preview
            if preview != .unconfigured { config = ConnectionConfig(port: 7890, nodeCount: 3) }
            return
        }
        refresh()
        if !hasConfig { page = .setup }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        guard !busy && !isPreview else { return }
        config = (try? Data(contentsOf: paths.config)).flatMap { try? ConnectionConfig.parse($0) }
        let running = engine.isRunning()
        if network.hasBackup || running {
            state = network.hasBackup && running && config.map { network.systemUses(port: $0.port) } == true ? .on : .recovery
        } else { state = config == nil ? .unconfigured : .off }
    }
    func toggle() {
        if state == .unconfigured { page = .setup; return }
        if state == .on || state == .recovery { disconnect(); return }
        message = nil; busyText = "正在准备连接"; state = .busy; checkResult = nil
        let engine = engine, network = network
        Task {
            let result = await Task.detached { () -> String? in
                do {
                    let config = try engine.start()
                    try network.enable(port: config.port)
                    return nil
                } catch {
                    let original = error.localizedDescription
                    if network.hasBackup {
                        do { try network.restore() }
                        catch { return original + "\n请点击“恢复连接”重试。" }
                    }
                    try? engine.stop()
                    return original
                }
            }.value
            state = .off; message = result
            // SystemConfiguration 通知可能稍后才更新活动网络状态。
            try? await Task.sleep(nanoseconds: 600_000_000)
            refresh()
            if result == nil && state == .on { diagnose() }
        }
    }
    func disconnect(completion: ((Bool) -> Void)? = nil) {
        guard !busy else { completion?(false); return }
        message = nil; busyText = "正在恢复原网络"; state = .busy
        let engine = engine, network = network
        Task {
            let result = await Task.detached { () -> String? in
                do { try network.restore(); try engine.stop(); return nil }
                catch { return error.localizedDescription }
            }.value
            state = .off; message = result; checkResult = nil; refresh()
            completion?(result == nil)
        }
    }
    func diagnose() {
        guard !checking, let config else { return }
        checking = true; checkResult = nil
        let engine = engine
        Task {
            let good = await Task.detached { engine.testNetwork(port: config.port) }.value
            checking = false
            if state == .on {
                checkResult = good ? "连接正常" : "暂时无法联网，请检查 Wi-Fi 或稍后重试。"
            }
        }
    }
    func chooseConfig() {
        guard !busy && !network.hasBackup && !engine.isRunning() else {
            message = "请先关闭连接，再更换配置。"; return
        }
        let panel = NSOpenPanel()
        panel.title = "选择连接配置"; panel.message = "选择收到的连接配置文件。"
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "qinglink") ?? .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { importConfig(url) }
    }
    func importConfig(_ url: URL) {
        guard !busy && !network.hasBackup && !engine.isRunning() else { message = "请先关闭连接，再导入配置。"; return }
        message = nil; state = .busy; busyText = "正在检查配置"
        let engine = engine, paths = paths
        Task {
            let result = await Task.detached { () -> String? in
                do {
                    // 校验与落盘必须是同一份内容，避免导入时源文件被改动。
                    let data = try Data(contentsOf: url)
                    _ = try ConnectionConfig.parse(data)
                    try paths.prepare()
                    let staged = paths.root.appendingPathComponent("import-\(UUID().uuidString).json")
                    defer { try? FileManager.default.removeItem(at: staged) }
                    try paths.save(data, to: staged)
                    _ = try engine.validate(staged)
                    try paths.save(data, to: paths.config)
                    return nil
                } catch { return error.localizedDescription }
            }.value
            state = .off; message = result; refresh()
            if result == nil { setupStep = 3 }
        }
    }
    func installToApplications() {
        guard !busy, state != .on, !network.hasBackup else { message = "请先关闭连接，再移动应用。"; return }
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            let destination = directory.appendingPathComponent("G-Link.app")
            if Bundle.main.bundleURL.standardizedFileURL == destination.standardizedFileURL { message = "G-Link已经放在应用程序文件夹。"; return }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                message = "应用程序文件夹已有G-Link。请先退出旧版本，在 Finder 中替换后打开。"; return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            message = "已添加到应用程序，下次从那里打开即可。"
        } catch { message = "移动应用失败：" + error.localizedDescription }
    }
    func openGuide() {
        if let url = Bundle.main.url(forResource: "使用指南", withExtension: "html", subdirectory: "docs") { NSWorkspace.shared.open(url) }
    }
    func checkForUpdates() {
        guard !isPreview else { return }
        guard !busy else { message = "请等待当前操作完成，再检查更新。"; return }
        do { try updates.check() }
        catch { message = "暂时无法检查更新，请稍后重试。" }
    }
    func openLogs() { try? paths.prepare(); NSWorkspace.shared.open(paths.root) }
    func rememberWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.title == "G-Link" }) else { return }
            window.isReleasedWhenClosed = false
            self?.mainWindow = window
        }
    }
    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        (mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }))?.makeKeyAndOrderFront(nil)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingFile: String?
    weak var model: AppModel? {
        didSet {
            if let pendingFile, let model { self.pendingFile = nil; model.importConfig(URL(fileURLWithPath: pendingFile)) }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.busy { model.message = "正在处理网络设置，完成后再退出。"; model.showWindow(); return .terminateCancel }
        if model.network.hasBackup || model.engine.isRunning() {
            model.disconnect { success in
                if !success { model.showWindow() }
                NSApp.reply(toApplicationShouldTerminate: success)
            }
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { model?.showWindow(); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let file = filenames.first {
            if let model { model.importConfig(URL(fileURLWithPath: file)); model.showWindow() }
            else { pendingFile = file }
        }
    }
}
