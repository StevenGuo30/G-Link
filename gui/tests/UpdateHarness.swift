import AppKit
import CryptoKit
import Sparkle

// Test-only app, linked with the real AppModel/AppDelegate. No AppPaths.live.
@MainActor final class UpdateHarness: NSObject, NSApplicationDelegate, SPUUserDriver {
    let root: URL
    let mode: String
    let delegate = AppDelegate()
    var model: AppModel!
    var updater: SPUUpdater!
    private var retried = false

    init(root: URL, mode: String) { self.root = root; self.mode = mode }
    func record(_ text: String) {
        let url = root.appendingPathComponent("events.txt")
        let data = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close()
        } else { try? data.write(to: url) }
    }
    func finish(_ text: String, status: Int32 = 0) -> Never {
        record(text); try? model?.engine.stop(); exit(status)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            record("relaunched-2"); exit(0)
        }
        do {
            model = AppModel(paths: AppPaths(root: root.appendingPathComponent("state")))
            delegate.model = model
            _ = try model.engine.start()
            model.refresh()
            record("engine-ready")
            updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
            try updater.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.record("manual-check")
                self.updater.checkForUpdates()
            }
        } catch { finish("setup-error: \(error)", status: 2) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reply = delegate.applicationShouldTerminate(sender)
        record(reply == .terminateLater ? "quit-waits-for-cleanup" : "quit-immediate")
        return reply
    }
    func applicationWillTerminate(_ notification: Notification) {
        record(model.engine.isRunning() ? "ERROR-engine-left-running" : "engine-stopped-before-exit")
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        finish("ERROR-background-permission-prompt", status: 2)
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { record("checking") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("found")
        if mode == "cancel" { reply(.skip); finish("cancelled") }
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish("no-update", status: mode == "none" ? 0 : 2)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        record("update-error: \(error)")
        acknowledgement(); finish("rejected", status: mode.hasPrefix("tamper") ? 0 : 2)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { record("download") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { record("verified-download") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { record("install"); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        guard mode == "restore-failure", !applicationTerminated, !retried else { return }
        retried = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard self.model.engine.isRunning(), !self.model.busy, self.model.message != nil,
                  self.model.network.hasBackup else { self.finish("ERROR-restore-did-not-block-quit", status: 2) }
            self.record("restore-failure-blocked-quit")
            // Only a deliberately invalid fixture file, never a system backup.
            try? FileManager.default.removeItem(at: self.model.paths.backup)
            retryTerminatingApplication()
        }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        record("installed"); acknowledgement()
    }
    func dismissUpdateInstallation() {}
}

@main enum UpdateTestEntry {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--keygen" {
            let key = Curve25519.Signing.PrivateKey()
            let path = URL(fileURLWithPath: args[2])
            try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            print(key.publicKey.rawRepresentation.base64EncodedString()); return
        }
        let info = Bundle.main.infoDictionary!
        let root = URL(fileURLWithPath: info["GLinkTestRoot"] as! String)
        let harness = UpdateHarness(root: root, mode: info["GLinkTestMode"] as! String)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.delegate = harness
        NSApp.run()
        withExtendedLifetime(harness) {}
    }
}
