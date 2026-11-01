import Foundation
import SystemConfiguration
import Security

struct ProxyPolicy {
    static let managedKeys = ["HTTPEnable", "HTTPProxy", "HTTPPort", "HTTPSEnable", "HTTPSProxy", "HTTPSPort", "SOCKSEnable", "SOCKSProxy", "SOCKSPort", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable", "ExceptionsList", "ExcludeSimpleHostnames"]
    static func enabled(_ original: [String: Any], port: Int) -> [String: Any] {
        var result = original
        for kind in ["HTTP", "HTTPS", "SOCKS"] {
            result[kind + "Enable"] = 1; result[kind + "Proxy"] = "127.0.0.1"; result[kind + "Port"] = port
        }
        result["ProxyAutoConfigEnable"] = 0; result["ProxyAutoDiscoveryEnable"] = 0
        var exceptions = original["ExceptionsList"] as? [String] ?? []
        for item in ["localhost", "*.local", "127.0.0.1", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"] {
            if !exceptions.contains(item) { exceptions.append(item) }
        }
        result["ExceptionsList"] = exceptions; result["ExcludeSimpleHostnames"] = 1
        return result
    }
    static func matches(_ dictionary: [String: Any], port: Int) -> Bool {
        ["HTTP", "HTTPS", "SOCKS"].allSatisfy {
            (dictionary[$0 + "Enable"] as? NSNumber)?.intValue == 1 && dictionary[$0 + "Proxy"] as? String == "127.0.0.1" && (dictionary[$0 + "Port"] as? NSNumber)?.intValue == port
        }
    }
    static func restored(current: [String: Any], original: [String: Any]) -> [String: Any] {
        var result = current
        for key in managedKeys { result[key] = original[key] }
        return result
    }
}

final class MacNetwork {
    let paths: AppPaths
    init(paths: AppPaths) { self.paths = paths }
    var hasBackup: Bool { FileManager.default.fileExists(atPath: paths.backup.path) }
    func systemUses(port: Int) -> Bool {
        guard let active = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return false }
        return ProxyPolicy.matches(active, port: port)
    }
    private func session<T>(_ body: (SCPreferences) throws -> T) throws -> T {
        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess, let authorization else {
            throw LinkError.message("无法发起系统授权，请重试。")
        }
        defer { AuthorizationFree(authorization, []) }
        let status = "system.preferences.network".withCString { name -> OSStatus in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { ptr in
                var rights = AuthorizationRights(count: 1, items: ptr)
                return AuthorizationCopyRights(authorization, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        guard status == errAuthorizationSuccess else {
            throw LinkError.message("系统授权未完成。没有授权时，G-Link不会更改网络代理；你可以再次点击重试。")
        }
        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "QingLink" as CFString, nil, authorization), SCPreferencesLock(prefs, true) else {
            throw LinkError.message("无法锁定网络设置。请关闭系统设置中的网络编辑窗口后重试。")
        }
        defer { SCPreferencesUnlock(prefs) }
        return try body(prefs)
    }
    private func commit(_ prefs: SCPreferences) throws {
        guard SCPreferencesCommitChanges(prefs), SCPreferencesApplyChanges(prefs) else {
            throw LinkError.message("系统未能应用网络设置。恢复备份已保留，请点击“恢复连接”。")
        }
    }
    func enable(port: Int) throws {
        guard !hasBackup else { throw LinkError.message("检测到上次的恢复记录，请先恢复连接，再重新开启。") }
        try session { prefs in
            guard let set = SCNetworkSetCopyCurrent(prefs), let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else {
                throw LinkError.message("未找到当前网络服务，请连接 Wi-Fi 或有线网络。")
            }
            var saved: [[String: Any]] = []
            var changes: [(SCNetworkProtocol, [String: Any])] = []
            for service in services where SCNetworkServiceGetEnabled(service) {
                guard let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies), let id = SCNetworkServiceGetServiceID(service) else { continue }
                let original = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
                saved.append(["id": id as String, "name": (SCNetworkServiceGetName(service) as String?) ?? "网络", "original": original])
                changes.append((proto, ProxyPolicy.enabled(original, port: port)))
            }
            guard !saved.isEmpty else { throw LinkError.message("当前没有可设置代理的网络服务。") }
            let snapshot: [String: Any] = ["version": 1, "port": port, "services": saved]
            try paths.save(PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0), to: paths.backup)
            for (proto, values) in changes {
                guard SCNetworkProtocolSetConfiguration(proto, values as CFDictionary) else {
                    throw LinkError.message("系统拒绝了代理设置。备份已保留，请先恢复连接。")
                }
            }
            try commit(prefs)
        }
    }
    func restore() throws {
        guard hasBackup else { return }
        let data = try Data(contentsOf: paths.backup)
        guard let snapshot = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              snapshot["version"] as? Int == 1, let saved = snapshot["services"] as? [[String: Any]] else {
            throw LinkError.message("网络恢复记录无法读取，请联系维护者；请勿删除应用数据。")
        }
        try session { prefs in
            for item in saved {
                guard let id = item["id"] as? String, let original = item["original"] as? [String: Any] else {
                    throw LinkError.message("网络恢复记录不完整，已保留备份。")
                }
                // 已删除的网络服务不再影响系统，跳过；现存服务必须恢复成功。
                guard let service = SCNetworkServiceCopy(prefs, id as CFString) else { continue }
                guard let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else {
                    throw LinkError.message("无法访问原网络服务的代理设置，已保留备份。")
                }
                let current = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
                guard SCNetworkProtocolSetConfiguration(proto, ProxyPolicy.restored(current: current, original: original) as CFDictionary) else {
                    throw LinkError.message("部分网络设置未恢复，已保留备份，请重试。")
                }
            }
            try commit(prefs)
            try FileManager.default.removeItem(at: paths.backup)
        }
    }
}
