import SwiftUI
import AppKit

struct QingLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("G-Link") {
            RootView(model: model).onAppear { delegate.model = model; model.rememberWindow() }
        }
        .windowStyle(.hiddenTitleBar).defaultSize(width: 880, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) { Button("显示G-Link") { model.showWindow() }.keyboardShortcut("0") }
            CommandGroup(replacing: .help) { Button("G-Link使用指南") { model.openGuide() } }
        }
        MenuBarExtra("G-Link", systemImage: model.state == .on ? "link.circle.fill" : "link.circle") {
            Text(model.state == .on ? "已开启" : model.state == .recovery ? "需要恢复连接" : "未开启")
            Button("显示主窗口") { model.showWindow() }
            Button(model.state == .on ? "关闭" : model.state == .recovery ? "恢复连接" : "开启") { model.toggle() }.disabled(model.busy)
            Divider()
            Button("使用指南") { model.openGuide() }
            Button("退出G-Link") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@main enum Entry {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--self-test") {
            do { try runSelfTests(); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        if let index = args.firstIndex(of: "--engine-test"), args.count > index + 3 {
            do { try runEngineTest(root: URL(fileURLWithPath: args[index + 1]), port: Int(args[index + 2])!, target: args[index + 3]); exit(0) }
            catch { fputs("Engine test failed: \(error)\n", stderr); exit(1) }
        }
        if let index = args.firstIndex(of: "--render-previews"), args.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let cityIndex = args.firstIndex(of: "--preview-city")
            let city = cityIndex.flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 1
            do { try renderPreviews(to: URL(fileURLWithPath: args[index + 1]), city: city); exit(0) }
            catch { fputs("Preview failed: \(error)\n", stderr); exit(1) }
        }
        if args.contains("--design-preview") || Bundle.main.object(forInfoDictionaryKey: "GLinkDesignPreview") as? Bool == true {
            DesignPreviewApp.main()
        } else {
            QingLinkApp.main()
        }
    }
}

func runEngineTest(root: URL, port: Int, target: String) throws {
    let paths = AppPaths(root: root)
    let engine = Engine(paths: paths, executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sing-box"))
    let config: [String: Any] = [
        "inbounds": [["type": "mixed", "listen": "127.0.0.1", "listen_port": port]],
        "outbounds": [["type": "socks", "tag": "unused", "server": "127.0.0.1", "server_port": 9], ["type": "direct", "tag": "direct"]],
        "route": ["final": "direct"]
    ]
    try paths.save(JSONSerialization.data(withJSONObject: config), to: paths.config)
    defer { try? engine.stop() }
    _ = try engine.start()
    guard let pid = engine.ownedPID() else { throw LinkError.message("进程所有权检查失败") }
    _ = try engine.start()
    guard engine.ownedPID() == pid else { throw LinkError.message("重复启动创建了第二个进程") }
    let result = try command("/usr/bin/curl", ["--noproxy", "", "-sS", "--proxy", "http://127.0.0.1:\(port)", "--max-time", "5", target])
    guard result.status == 0, result.output == "qinglink-ok" else { throw LinkError.message("实际 HTTP 转发失败") }
    try engine.stop()
    guard !engine.isRunning() else { throw LinkError.message("停止后仍有进程") }
    print("PASS: 原生 Engine 配置校验、启动、重复启动、真实 HTTP 转发、停止")
}

@MainActor func renderPreviews(to directory: URL, city: Int = 1) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, state, page, step) in [
        ("connection-off", LinkState.off, Page.connection, 1),
        ("connection-on", LinkState.on, Page.connection, 1),
        ("setup", LinkState.unconfigured, Page.setup, 2),
        ("recovery", LinkState.recovery, Page.connection, 1)
    ] {
        let model = AppModel(preview: state, previewCity: city); model.page = page; model.setupStep = step
        if state == .on { model.checkResult = "连接正常" }
        let view = RootView(model: model).frame(width: 880, height: 650)
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw LinkError.message("无法生成界面预览")
        }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

func runSelfTests() throws {
    func expect(_ condition: Bool, _ label: String) throws { if !condition { throw LinkError.message(label) }; print("PASS: \(label)") }
    let original: [String: Any] = ["HTTPEnable": 0, "HTTPProxy": "old.proxy", "HTTPPort": 8080, "ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "https://example.test/proxy.pac", "ExceptionsList": ["example.test"], "UnrelatedSetting": "keep"]
    var enabled = ProxyPolicy.enabled(original, port: 17890)
    try expect(ProxyPolicy.matches(enabled, port: 17890), "HTTP / HTTPS / SOCKS 使用指定端口")
    try expect((enabled["ExceptionsList"] as? [String])?.contains("100.64.0.0/10") == true, "内网与 Tailscale 绕过代理")
    try expect(enabled["ProxyAutoConfigURLString"] as? String == original["ProxyAutoConfigURLString"] as? String, "保留 PAC 地址")
    enabled["OtherAppSetting"] = 42
    let restored = ProxyPolicy.restored(current: enabled, original: original)
    try expect(restored["HTTPProxy"] as? String == "old.proxy" && restored["HTTPEnable"] as? Int == 0 && restored["SOCKSProxy"] == nil, "恢复原设置及原本不存在的键")
    try expect(restored["OtherAppSetting"] as? Int == 42, "保留未被本应用改动的设置")
    let valid: [String: Any] = ["inbounds": [["type": "mixed", "listen": "127.0.0.1", "listen_port": 17890]], "outbounds": [["type": "vless", "tag": "test"]]]
    let data = try JSONSerialization.data(withJSONObject: valid)
    try expect(try ConnectionConfig.parse(data).port == 17890, "识别可导入配置")
    for bad in ["{}", "{\"inbounds\":[]}", "not json"] {
        do { _ = try ConnectionConfig.parse(Data(bad.utf8)); throw LinkError.message("无效配置不应通过") }
        catch { if error.localizedDescription == "无效配置不应通过" { throw error } }
    }
    print("PASS: 无效配置拒绝导入")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("qinglink-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppPaths(root: root)
    try paths.save(data, to: paths.config)
    let permissions = try FileManager.default.attributesOfItem(atPath: paths.config.path)[.posixPermissions] as? Int
    try expect(permissions == 0o600, "私人配置权限为 0600")
    try expect(!MacNetwork(paths: paths).hasBackup, "干净安装没有恢复记录")
    try MacNetwork(paths: paths).restore()
    print("PASS: 无备份时恢复为空操作，不请求管理员授权")
}
