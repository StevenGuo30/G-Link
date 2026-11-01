import Foundation
import Darwin

// Separate test executable: never uses AppPaths.live or changes system proxies.
@main struct EngineLifecycle {
    static func main() throws {
        let args = CommandLine.arguments
        let mode = args[1], paths = AppPaths(root: URL(fileURLWithPath: args[2]))
        let engine = Engine(paths: paths, executable: URL(fileURLWithPath: args[3]))
        let port = Int(args[4])!
        let config: [String: Any] = [
            "inbounds": [["type": "mixed", "listen": "127.0.0.1", "listen_port": port]],
            "outbounds": [["type": "socks", "tag": "unused", "server": "127.0.0.1", "server_port": 9], ["type": "direct", "tag": "direct"]],
            "route": ["final": "direct"]
        ]
        try paths.save(JSONSerialization.data(withJSONObject: config), to: paths.config)
        if mode == "hold" {
            _ = try engine.start()
            guard let pid = engine.ownedPID() else { throw LinkError.message("启动后无法识别自己的进程") }
            print("READY \(pid)"); fflush(stdout)
            while true { Thread.sleep(forTimeInterval: 1) }
        }
        if mode == "reject" {
            guard !engine.isRunning() else { throw LinkError.message("误认其他程序或配置") }
            do {
                _ = try engine.start()
            } catch {
                guard error.localizedDescription.contains("端口") else { throw error }
                try engine.stop()
                print("PASS: 拒绝占用端口，不接管或关闭其他程序")
                return
            }
            try engine.stop()
            throw LinkError.message("未拒绝占用端口")
        }
        if mode == "recover" {
            let expected = Int32(args[5])!
            guard engine.ownedPID() == expected else { throw LinkError.message("未识别遗留进程") }
            _ = try engine.start()
            guard engine.ownedPID() == expected else { throw LinkError.message("重复创建进程") }
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.pid)) as! [String: Any]
            guard saved["pid"] as? Int32 == expected else { throw LinkError.message("没有修复进程记录") }
            let result = try command("/usr/bin/curl", ["--noproxy", "", "--proxy", "http://127.0.0.1:\(port)", "-sS", "--max-time", "5", args[6]])
            guard result.status == 0 && result.output == "qinglink-ok" else { throw LinkError.message("恢复后无法转发请求") }
        }
        try engine.stop()
        guard !engine.isRunning() else { throw LinkError.message("恢复后仍有遗留进程") }
        // Also exercise cancellation cleanup followed immediately by retry.
        if mode == "recover" {
            _ = try engine.start()
            try engine.stop()
            guard !engine.isRunning() else { throw LinkError.message("重试后未能停止") }
        }
        print("PASS: 遗留进程接管、转发、清理及再次启动")
    }
}
