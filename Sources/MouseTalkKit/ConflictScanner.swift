import AppKit
import ApplicationServices
import Carbon

public struct BindingSelection: Equatable {
    public let action: String
    public let keys: [Int]
    public let mouseButton: Int?
    public init(action: String, keys: [Int], mouseButton: Int?) {
        self.action = action; self.keys = keys; self.mouseButton = mouseButton
    }
}

public struct ConflictFinding: Identifiable, Codable {
    public var id: String { [action, app, function, source].joined(separator: "|") }
    public let action: String
    public let app: String
    public let function: String
    public let source: String
    public let explanation: String
}

public struct ConflictReport: Codable {
    public var findings: [ConflictFinding] = []
    public var coverage: [String] = []
    public var checkedAt = Date()
    public var menuAppsRead = 0
    public init() {}
}

public enum ShortcutMatch {
    public static let shift: UInt64 = 1 << 17
    public static let control: UInt64 = 1 << 18
    public static let option: UInt64 = 1 << 19
    public static let command: UInt64 = 1 << 20
    public static let fn: UInt64 = 1 << 23
    public static let mask = shift | control | option | command | fn

    public static func modifier(_ code: Int) -> UInt64 {
        switch code {
        case 56, 60: return shift
        case 59, 62: return control
        case 58, 61: return option
        case 55, 54: return command
        case 63: return fn
        default: return 0
        }
    }

    public static func matches(_ selection: BindingSelection, keyCode: Int, flags: UInt64) -> Bool {
        let modifiersOnly = !selection.keys.isEmpty && selection.keys.allSatisfy { modifier($0) != 0 }
        if modifiersOnly {
            // A Control+C menu command must never be called a collision with Control alone.
            guard modifier(keyCode) != 0 else { return false }
            let expected = selection.keys.reduce(UInt64(0)) { $0 | modifier($1) }
            return expected == ((flags & mask) | modifier(keyCode))
        }
        return selection.keys == [keyCode] && flags & mask == 0
    }

    public static func carbonFlags(_ raw: UInt32) -> UInt64 {
        var flags: UInt64 = 0
        if raw & UInt32(cmdKey) != 0 { flags |= command }
        if raw & UInt32(shiftKey) != 0 { flags |= shift }
        if raw & UInt32(optionKey) != 0 { flags |= option }
        if raw & UInt32(controlKey) != 0 { flags |= control }
        if raw & UInt32(kEventKeyModifierFnMask) != 0 { flags |= fn }
        return flags
    }

    public static func menuFlags(_ raw: UInt32) -> UInt64 {
        var flags: UInt64 = raw & 8 == 0 ? command : 0
        if raw & 1 != 0 { flags |= shift }
        if raw & 2 != 0 { flags |= option }
        if raw & 4 != 0 { flags |= control }
        return flags
    }

    public static func equivalent(_ text: String) -> (Int, UInt64)? {
        var flags: UInt64 = 0
        var chars = Array(text)
        while chars.count > 1 {
            let flag: UInt64
            switch chars[0] {
            case "^": flag = control
            case "~": flag = option
            case "@": flag = command
            case "$": flag = shift
            default: return nil
            }
            flags |= flag; chars.removeFirst()
        }
        guard let character = chars.first else { return nil }
        switch character {
        case "\r": return (36, flags)
        case "\u{8}", "\u{7f}": return (51, flags)
        default: return nil
        }
    }
}

public struct ScanApplication {
    let pid: pid_t
    let name: String
    let bundleID: String
}

public struct ScanContext {
    var applications: [ScanApplication]
    var systemKeys: [[String: Any]]
    var systemReadable: Bool
    var trusted: Bool
    var drivers: [String] = []
}

public enum ConflictScanner {
    /// Capture on main: CopySymbolicHotKeys is explicitly not thread safe.
    public static func context() -> ScanContext {
        precondition(Thread.isMainThread)
        var array: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&array)
        let keys = array?.takeRetainedValue() as? [[String: Any]] ?? []
        let running = NSWorkspace.shared.runningApplications
        let apps = running.compactMap { app -> ScanApplication? in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.activationPolicy != .prohibited, let id = app.bundleIdentifier else { return nil }
            guard app.activationPolicy == .regular || !id.hasPrefix("com.apple.") else { return nil }
            return ScanApplication(pid: app.processIdentifier, name: app.localizedName ?? id, bundleID: id)
        }.sorted { a, b in
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if a.pid == front { return true }
            if b.pid == front { return false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        let drivers = running.compactMap { app -> String? in
            let id = app.bundleIdentifier?.lowercased() ?? ""
            guard isMouseDriver(id) else { return nil }
            return app.localizedName ?? id
        }
        return ScanContext(applications: apps, systemKeys: keys, systemReadable: status == noErr,
                           trusted: AXIsProcessTrusted(), drivers: drivers)
    }

    public static func isMouseDriver(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return id.hasPrefix("com.logi.") || id.hasPrefix("com.logitech.") ||
            id == "com.hegenberg.bettertouchtool" || id.hasPrefix("jp.plentycom.steermouse") ||
            id.hasPrefix("com.usboverdrive.")
    }

    public static func scan(_ bindings: [BindingSelection], context: ScanContext,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ConflictReport {
        var report = ConflictReport()
        let active = bindings.filter { $0.mouseButton != nil }
        for key in context.systemKeys {
            guard (key[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let code = key[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let mods = key[kHISymbolicHotKeyModifiers as String] as? NSNumber else { continue }
            for binding in active where ShortcutMatch.matches(binding, keyCode: code.intValue, flags: ShortcutMatch.carbonFlags(mods.uint32Value)) {
                report.findings.append(ConflictFinding(action: binding.action, app: "macOS", function: "系统快捷键（键码 \(code.intValue)）",
                    source: "系统键盘设置", explanation: "与系统公开的启用快捷键重合；此接口不提供功能名称，需到系统设置核对。"))
            }
        }
        report.coverage.append(context.systemReadable ? "已读取 macOS 系统快捷键。" : "系统快捷键读取失败，本次未覆盖。")
        let global = CFPreferencesCopyAppValue("NSUserKeyEquivalents" as CFString, kCFPreferencesAnyApplication) as? [String: String] ?? [:]
        appendEquivalents(global, app: "所有应用", bindings: active, report: &report)
        for app in context.applications {
            let overrides = CFPreferencesCopyAppValue("NSUserKeyEquivalents" as CFString, app.bundleID as CFString) as? [String: String] ?? [:]
            appendEquivalents(overrides, app: app.name, bindings: active, report: &report)
        }

        if context.trusted {
            let deadline = Date().addingTimeInterval(8)
            var unavailable: [String] = []
            for app in context.applications {
                guard Date() < deadline else {
                    report.coverage.append("扫描达到时间上限，部分应用尚未检查；可再次检查。")
                    break
                }
                let element = AXUIElementCreateApplication(app.pid)
                AXUIElementSetMessagingTimeout(element, 0.15)
                guard let bar = attribute(element, kAXMenuBarAttribute) else {
                    unavailable.append(app.name); continue
                }
                guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
                let menu = unsafeBitCast(bar, to: AXUIElement.self)
                var budget = 500
                var complete = true
                walk(menu, app: app.name, path: [], bindings: active, deadline: deadline,
                     budget: &budget, complete: &complete, report: &report)
                if complete { report.menuAppsRead += 1 } else { unavailable.append(app.name) }
            }
            report.coverage.append("已检查 \(report.menuAppsRead) 个运行中应用的公开菜单；不包含应用内部隐藏的全局绑定。")
            if !unavailable.isEmpty { report.coverage.append("菜单未完整读取：" + unavailable.joined(separator: "、")) }
        } else {
            report.coverage.append("尚无辅助功能权限，未读取其他应用菜单。授权后重新检查。")
        }
        let karabiner = home.appendingPathComponent(".config/karabiner/karabiner.json")
        if FileManager.default.fileExists(atPath: karabiner.path) {
            do {
                let data = try Data(contentsOf: karabiner)
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                report.findings += karabinerFindings(root, bindings: active)
                report.coverage.append("已读取 Karabiner 当前选中配置中的直接鼠标按键映射；复杂条件仅作可能重合提示。")
            } catch { report.coverage.append("Karabiner 配置无法读取，本次未覆盖。") }
        }
        var drivers = context.drivers
        if FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Preferences/com.logi.optionsplus.plist").path) {
            drivers.append("Logi Options+（检测到配置）")
        }
        if !drivers.isEmpty { report.coverage.append("这些鼠标工具的专有按键配置无法完整读取：" + drivers.joined(separator: "、")) }
        report.coverage.append("单按／双击修饰键、未运行软件及专有鼠标驱动可能无法识别。未发现重合不等于没有冲突。")
        var seen = Set<String>()
        report.findings = report.findings.filter { seen.insert($0.id).inserted }
        report.checkedAt = Date()
        return report
    }

    private static func appendEquivalents(_ values: [String: String], app: String,
                                          bindings: [BindingSelection], report: inout ConflictReport) {
        for (function, text) in values {
            guard let (code, flags) = ShortcutMatch.equivalent(text) else { continue }
            for binding in bindings where ShortcutMatch.matches(binding, keyCode: code, flags: flags) {
                report.findings.append(ConflictFinding(action: binding.action, app: app, function: function,
                    source: "自定义菜单快捷键", explanation: "此菜单功能使用相同按键；是否干扰取决于当前应用和输入焦点。"))
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }

    private static func walk(_ element: AXUIElement, app: String, path: [String], bindings: [BindingSelection],
                             deadline: Date, budget: inout Int, complete: inout Bool, report: inout ConflictReport) {
        guard budget > 0, path.count < 10, Date() < deadline else { complete = false; return }
        budget -= 1
        let title = attribute(element, kAXTitleAttribute) as? String ?? ""
        let path = title.isEmpty ? path : path + [title]
        if let code = attribute(element, kAXMenuItemCmdVirtualKeyAttribute) as? NSNumber,
           let mods = attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber,
           (attribute(element, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
            for binding in bindings where ShortcutMatch.matches(binding, keyCode: code.intValue, flags: ShortcutMatch.menuFlags(mods.uint32Value)) {
                report.findings.append(ConflictFinding(action: binding.action, app: app, function: path.joined(separator: " → "),
                    source: "运行中应用菜单", explanation: "此功能使用相同按键；菜单快捷键只在对应应用中生效，不一定是全局冲突。修饰键左右侧与连击语义可能未公开。"))
            }
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                guard budget > 0, Date() < deadline else { complete = false; break }
                walk(child, app: app, path: path, bindings: bindings, deadline: deadline,
                     budget: &budget, complete: &complete, report: &report)
            }
        }
    }

    public static func karabinerFindings(_ root: [String: Any], bindings: [BindingSelection]) -> [ConflictFinding] {
        guard let profiles = root["profiles"] as? [[String: Any]],
              let profile = profiles.first(where: { $0["selected"] as? Bool == true }) else { return [] }
        var items: [(String, [String: Any])] = []
        for item in profile["simple_modifications"] as? [[String: Any]] ?? [] { items.append(("简单按键映射", item)) }
        let complex = profile["complex_modifications"] as? [String: Any] ?? [:]
        for rule in complex["rules"] as? [[String: Any]] ?? [] {
            for item in rule["manipulators"] as? [[String: Any]] ?? [] {
                items.append((rule["description"] as? String ?? "复杂按键映射", item))
            }
        }
        return items.flatMap { title, item -> [ConflictFinding] in
            guard let from = item["from"] as? [String: Any], let button = from["pointing_button"] as? String else { return [] }
            let to = item["to"] as? [[String: Any]] ?? []
            let output = to.compactMap { ($0["key_code"] ?? $0["pointing_button"]) as? String }.joined(separator: " + ")
            return bindings.filter { $0.mouseButton.map { "button\($0 + 1)" } == button }.map {
                ConflictFinding(action: $0.action, app: "Karabiner-Elements", function: title,
                    source: "当前选中配置", explanation: "同样使用 \(button)\(output.isEmpty ? "" : " → " + output)。设备或应用条件、执行顺序可能影响结果，请核对。")
            }
        }
    }
}
