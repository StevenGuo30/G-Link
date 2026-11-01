import Foundation
import Darwin

enum LinkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

struct ConnectionConfig {
    let port: Int
    let nodeCount: Int
    static func parse(_ data: Data) throws -> ConnectionConfig {
        guard data.count < 5_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = root["inbounds"] as? [[String: Any]], inbounds.count == 1,
              inbounds[0]["type"] as? String == "mixed",
              inbounds[0]["listen"] as? String == "127.0.0.1",
              let number = inbounds[0]["listen_port"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(number.intValue), (1024...65535).contains(number.intValue),
              let outbounds = root["outbounds"] as? [[String: Any]], !outbounds.isEmpty
        else { throw LinkError.message("这份配置无法使用，请重新选择收到的连接配置文件。") }
        if inbounds[0]["set_system_proxy"] as? Bool == true {
            throw LinkError.message("这份配置需要更新，请联系分享者。")
        }
        let nodes = outbounds.filter { !["direct", "block", "selector", "urltest", "dns"].contains($0["type"] as? String ?? "") }
        guard !nodes.isEmpty else { throw LinkError.message("配置中没有可用的代理节点，请向维护者获取连接配置。") }
        return ConnectionConfig(port: number.intValue, nodeCount: nodes.count)
    }
}

struct AppPaths {
    let root: URL
    var config: URL { root.appendingPathComponent("config.json") }
    var backup: URL { root.appendingPathComponent("network-backup.plist") }
    var pid: URL { root.appendingPathComponent("engine.json") }
    var log: URL { root.appendingPathComponent("engine.log") }
    static var live: AppPaths {
        AppPaths(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingLink"))
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
    func save(_ data: Data, to url: URL) throws {
        try prepare()
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct CommandResult { let status: Int32; let output: String }
private final class CommandLifetime: @unchecked Sendable {
    let lock = NSLock()
    var finished = false
}
func command(_ executable: String, _ args: [String], timeout: TimeInterval = 15) throws -> CommandResult {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
    task.standardOutput = pipe; task.standardError = pipe; task.standardInput = FileHandle.nullDevice
    try task.run()
    let lifetime = CommandLifetime()
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        lifetime.lock.lock(); defer { lifetime.lock.unlock() }
        if !lifetime.finished && task.isRunning { task.terminate() }
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    lifetime.lock.lock(); lifetime.finished = true; lifetime.lock.unlock()
    return CommandResult(status: task.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
}

// Read kernel data instead of `ps command=`: Finder-launched apps may have a C
// locale, in which ps escapes Chinese paths and ownership checks silently fail.
private struct EngineProcess {
    let pid: Int32
    let binary: String

    static func read(_ pid: Int32, config: URL) -> EngineProcess? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), info.pbi_status != SZOMB else { return nil }
        var path = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let binary = String(cString: path)
        guard binary.hasSuffix("/Contents/Helpers/sing-box") else { return nil }

        // KERN_PROCARGS2 contains argc, executable path, padding, then argv.
        // Decode only argv; never retain or log the following environment data.
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size, size <= 4_194_304 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        bytes = Array(bytes.prefix(size))
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        var argc: Int32 = 0
        _ = withUnsafeMutableBytes(of: &argc) { bytes.prefix(4).copyBytes(to: $0) }
        guard argc == 4 else { return nil }
        var offset = MemoryLayout<Int32>.size
        guard let executableEnd = bytes[offset...].firstIndex(of: 0) else { return nil }
        offset = executableEnd
        while offset < bytes.count && bytes[offset] == 0 { offset += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0),
                  let value = String(bytes: bytes[offset..<end], encoding: .utf8) else { return nil }
            arguments.append(value); offset = end + 1
        }
        guard arguments[1] == "run", arguments[2] == "-c", arguments[3].hasPrefix("/"),
              URL(fileURLWithPath: arguments[3]).resolvingSymlinksInPath().standardizedFileURL == config.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        return EngineProcess(pid: pid, binary: binary)
    }

    static func candidates() -> [Int32] {
        let size = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard size > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(size) / MemoryLayout<Int32>.size + 64)
        let read = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard read > 0 else { return [] }
        return Array(pids.prefix(Int(read) / MemoryLayout<Int32>.size)).filter { $0 > 1 }
    }
}

final class Engine {
    let paths: AppPaths
    let executable: URL
    private var task: Process?
    init(paths: AppPaths, executable: URL) { self.paths = paths; self.executable = executable }
    func validate(_ url: URL) throws -> ConnectionConfig {
        let config = try ConnectionConfig.parse(Data(contentsOf: url))
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw LinkError.message("随包的连接程序缺失，请重新下载完整应用。")
        }
        let result = try command(executable.path, ["check", "-c", url.path])
        guard result.status == 0 else { throw LinkError.message("配置检查未通过，请联系分享者更新。") }
        return config
    }
    func ownedPID() -> Int32? {
        if let data = try? Data(contentsOf: paths.pid),
           let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let pid = info["pid"] as? Int32,
           EngineProcess.read(pid, config: paths.config) != nil { return pid }
        // The GUI may have died before saving its PID, or an older recovery may
        // have deleted it. Reconcile only this user's helper with this config.
        return EngineProcess.candidates().first { EngineProcess.read($0, config: paths.config) != nil }
    }
    func isRunning() -> Bool { ownedPID() != nil }
    func start() throws -> ConnectionConfig {
        let config = try validate(paths.config)
        if let pid = ownedPID(), let process = EngineProcess.read(pid, config: paths.config) {
            try paths.save(JSONSerialization.data(withJSONObject: ["pid": pid, "binary": process.binary]), to: paths.pid)
            return config
        }
        let check = try command("/usr/sbin/lsof", ["-nP", "-iTCP:\(config.port)", "-sTCP:LISTEN", "-t"])
        guard check.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LinkError.message("端口 \(config.port) 正被另一个代理占用。请先关闭旧工具包（04）或其他代理软件，再开启G-Link。")
        }
        try paths.prepare()
        if FileManager.default.fileExists(atPath: paths.log.path) {
            let old = paths.root.appendingPathComponent("engine.previous.log")
            try? FileManager.default.removeItem(at: old)
            try FileManager.default.moveItem(at: paths.log, to: old)
        }
        FileManager.default.createFile(atPath: paths.log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: paths.log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = executable; process.arguments = ["run", "-c", paths.config.path]
        process.currentDirectoryURL = paths.root
        process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
        try process.run(); task = process
        do {
            try paths.save(JSONSerialization.data(withJSONObject: ["pid": process.processIdentifier, "binary": executable.path]), to: paths.pid)
            for _ in 0..<20 {
                guard process.isRunning else { throw LinkError.message("连接程序未能启动。请检查配置，或在帮助中打开本地日志。") }
                let ready = try command("/usr/sbin/lsof", ["-a", "-p", String(process.processIdentifier), "-iTCP:\(config.port)", "-sTCP:LISTEN", "-t"])
                if ready.status == 0 { return config }
                Thread.sleep(forTimeInterval: 0.2)
            }
            throw LinkError.message("等待连接程序启动超时，请重试。")
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: paths.pid)
            throw error
        }
    }
    func stop() throws {
        let pids = EngineProcess.candidates().filter { EngineProcess.read($0, config: paths.config) != nil }
        for pid in pids {
            // Recheck before signalling; never trust a PID file or a port alone.
            if EngineProcess.read(pid, config: paths.config) != nil { kill(pid, SIGTERM) }
        }
        for _ in 0..<30 {
            if pids.allSatisfy({ EngineProcess.read($0, config: paths.config) == nil }) {
                try? FileManager.default.removeItem(at: paths.pid); task = nil; return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw LinkError.message("连接程序尚未退出，请稍后再试。系统代理已恢复，不会继续指向此程序。")
    }
    func testNetwork(port: Int) -> Bool {
        guard let result = try? command("/usr/bin/curl", ["--noproxy", "", "--proxy", "http://127.0.0.1:\(port)", "-s", "--connect-timeout", "5", "--max-time", "10", "-o", "/dev/null", "-w", "%{http_code}", "https://www.gstatic.com/generate_204"], timeout: 12) else { return false }
        return result.status == 0 && result.output == "204"
    }
}
