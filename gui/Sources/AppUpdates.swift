import AppKit
import Sparkle

// Created only after an explicit click, never by previews or at app launch.
// Sparkle downloads and verifies first, then asks NSApplication to terminate.
// AppDelegate's existing terminateLater path must finish restoring networking
// before the updater can replace the app. Cancelling authorization cancels quit.
@MainActor final class AppUpdates: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    func check() throws {
        if controller == nil {
            let candidate = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            try candidate.updater.start()
            controller = candidate
        }
        controller?.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updates else {
            throw LinkError.message("请点击“检查更新”手动更新。")
        }
    }
}
