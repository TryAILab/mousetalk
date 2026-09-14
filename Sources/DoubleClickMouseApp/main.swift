// 鼠语 MouseTalk menu bar application.
import ApplicationServices
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers
import MouseTalkKit

private enum OutputKey: String, CaseIterable, Identifiable {
    case fn
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fn: "Fn"
        case .leftControl: "左 Control"
        case .rightControl: "右 Control"
        case .leftOption: "左 Option"
        case .rightOption: "右 Option"
        case .leftCommand: "左 Command"
        case .rightCommand: "右 Command"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .fn: 63
        case .leftControl: 59
        case .rightControl: 62
        case .leftOption: 58
        case .rightOption: 61
        case .leftCommand: 55
        case .rightCommand: 54
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .leftControl, .rightControl: .maskControl
        case .leftOption: .maskAlternate
        case .rightOption: .maskAlternate
        case .leftCommand, .rightCommand: .maskCommand
        }
    }

    static func load(rawValue: String?) -> OutputKey? {
        guard let rawValue else { return nil }
        // 0.3.0 called keycode 59 simply "control". Preserve existing users
        // while exposing both physical Control keys explicitly.
        if rawValue == "control" { return .leftControl }
        return OutputKey(rawValue: rawValue)
    }
}

private enum EventShape: String, CaseIterable, Identifiable {
    case keyboard
    case flagsChanged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard: "标准模式（推荐）"
        case .flagsChanged: "兼容模式（标准模式无效时尝试）"
        }
    }
}

private enum BindingTarget {
    case voice
    case confirm
    case backspace

    var title: String {
        switch self {
        case .voice: "语音快捷键"
        case .confirm: "回车发送"
        case .backspace: "退格"
        }
    }
}

private final class ShortcutEmitter {
    private let queue = DispatchQueue(label: "io.github.aaronz021.double-click-mouse.emitter")
    private var backspaceTimer: DispatchSourceTimer?
    private var isBackspaceHeld = false

    func emit(keys: [OutputKey], shape: EventShape) {
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            let uniqueKeys = keys.reduce(into: [OutputKey]()) { result, key in
                if !result.contains(key) { result.append(key) }
            }
            guard !uniqueKeys.isEmpty else { return }

            var baseFlags = CGEventSource.flagsState(.combinedSessionState)
            for key in uniqueKeys {
                baseFlags.remove(key.flag)
            }

            var activeKeys: [OutputKey] = []
            for key in uniqueKeys {
                activeKeys.append(key)
                let flags = activeKeys.reduce(baseFlags) { $0.union($1.flag) }
                self.post(key: key, keyDown: true, flags: flags, shape: shape, source: source)
                usleep(15_000)
            }
            usleep(60_000)
            for key in uniqueKeys.reversed() {
                activeKeys.removeAll { $0 == key }
                let flags = activeKeys.reduce(baseFlags) { $0.union($1.flag) }
                self.post(key: key, keyDown: false, flags: flags, shape: shape, source: source)
                usleep(15_000)
            }
        }
    }

    func emitReturn() {
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
            else { return }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            usleep(50_000)
            up.post(tap: .cghidEventTap)
        }
    }

    func beginBackspace() {
        queue.async {
            guard !self.isBackspaceHeld else { return }
            self.isBackspaceHeld = true
            self.postBackspace(keyDown: true, isRepeat: false)

            let timing = Self.keyboardRepeatTiming()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + .milliseconds(timing.initialDelayMilliseconds),
                repeating: .milliseconds(timing.repeatIntervalMilliseconds),
                leeway: .milliseconds(3)
            )
            timer.setEventHandler { [weak self] in
                guard let self, self.isBackspaceHeld else { return }
                self.postBackspace(keyDown: true, isRepeat: true)
            }
            self.backspaceTimer = timer
            timer.resume()
        }
    }

    func endBackspace() {
        queue.async {
            self.endBackspaceOnQueue()
        }
    }

    func endBackspaceSynchronously() {
        queue.sync {
            self.endBackspaceOnQueue()
        }
    }

    private func endBackspaceOnQueue() {
        guard isBackspaceHeld else { return }
        backspaceTimer?.setEventHandler {}
        backspaceTimer?.cancel()
        backspaceTimer = nil
        isBackspaceHeld = false
        postBackspace(keyDown: false, isRepeat: false)
    }

    private func postBackspace(keyDown: Bool, isRepeat: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: 51,
            keyDown: keyDown
        ) else { return }
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        event.post(tap: .cghidEventTap)
    }

    private static func keyboardRepeatTiming() -> (
        initialDelayMilliseconds: Int,
        repeatIntervalMilliseconds: Int
    ) {
        // macOS stores these values in 1/60-second ticks. Fall back to the
        // common defaults if they are unavailable.
        let defaults = UserDefaults.standard
        let initialTicks = defaults.double(forKey: "InitialKeyRepeat")
        let repeatTicks = defaults.double(forKey: "KeyRepeat")
        let initial = initialTicks > 0 ? initialTicks : 15
        let repeating = repeatTicks > 0 ? repeatTicks : 2
        return (
            max(150, Int(initial * 1_000 / 60)),
            max(16, Int(repeating * 1_000 / 60))
        )
    }

    private func post(
        key: OutputKey,
        keyDown: Bool,
        flags: CGEventFlags,
        shape: EventShape,
        source: CGEventSource?
    ) {
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: key.keyCode,
            keyDown: keyDown
        ) else { return }
        event.flags = flags
        if shape == .flagsChanged {
            event.type = .flagsChanged
        }
        event.post(tap: .cghidEventTap)
    }
}

private let mouseEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<MouseMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reenable()
    } else if type == .otherMouseDown || type == .otherMouseUp {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let shouldSuppress = monitor.shouldSuppress(button: button)
        if type == .otherMouseDown {
            monitor.receiveDown(button: button)
        } else {
            monitor.receiveUp(button: button)
        }
        // Suppress the original action on button-down, but always let the
        // physical button-up reach macOS. Swallowing both edges can leave the
        // session button state latched (most visibly for button 2 / middle
        // click), which makes pop-up controls ignore otherwise valid left
        // clicks because they believe another mouse button is still held.
        // An unmatched mouse-up is ignored by normal controls and safely
        // clears the system state.
        if shouldSuppress, type == .otherMouseDown {
            return nil
        }
    }
    return Unmanaged.passUnretained(event)
}

private final class MouseMonitor {
    var onButtonDown: ((Int) -> Void)?
    var onButtonUp: ((Int) -> Void)?
    var onCancelled: (() -> Void)?
    private var suppressedButtons: Set<Int> = []

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap.map(CGEvent.tapIsEnabled) ?? false }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        stop()

        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseEventCallback,
            userInfo: userInfo
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            return false
        }

        tap = newTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    func reenable() {
        DispatchQueue.main.async { [weak self] in
            self?.onCancelled?()
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func receiveDown(button: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.onButtonDown?(button)
        }
    }

    func receiveUp(button: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.onButtonUp?(button)
        }
    }

    func setSuppressedButtons(_ buttons: Set<Int>) {
        suppressedButtons = buttons
    }

    func shouldSuppress(button: Int) -> Bool {
        suppressedButtons.contains(button)
    }
}

private final class AppController: ObservableObject {
    @Published var canListen = false
    @Published var canPost = false
    @Published var captureTarget: BindingTarget?
    @Published var monitorRunning = false
    @Published var status = "按下面的步骤设置，设置会自动保存。"
    @Published var testCountdown = 0
    @Published var voiceAppPath = UserDefaults.standard.string(forKey: "voiceAppPath") ?? "" {
        didSet { UserDefaults.standard.set(voiceAppPath, forKey: "voiceAppPath") }
    }
    private var testTimer: Timer?
    @Published var conflictReport: ConflictReport?
    @Published var checkingConflicts = false
    @Published var bindingNotice = ""
    private var conflictGeneration = UUID()
    private var pendingConflictCheck: DispatchWorkItem?
    private let conflictQueue = DispatchQueue(label: "mousetalk.conflicts", qos: .userInitiated)


    @Published var selectedButton: Int? {
        didSet {
            if let selectedButton {
                defaults.set(selectedButton, forKey: "selectedButton")
            } else {
                defaults.removeObject(forKey: "selectedButton")
            }
            refreshSuppressedButtons()
            scheduleConflictCheck()
        }
    }
    @Published var returnButton: Int? {
        didSet {
            if let returnButton {
                defaults.set(returnButton, forKey: "returnButton")
            } else {
                defaults.removeObject(forKey: "returnButton")
            }
            refreshSuppressedButtons()
            scheduleConflictCheck()
        }
    }
    @Published var backspaceButton: Int? {
        didSet {
            emitter.endBackspace()
            if let backspaceButton {
                defaults.set(backspaceButton, forKey: "backspaceButton")
            } else {
                defaults.removeObject(forKey: "backspaceButton")
            }
            refreshSuppressedButtons()
            scheduleConflictCheck()
        }
    }
    @Published var isEnabled: Bool {
        didSet {
            if !isEnabled { emitter.endBackspace() }
            defaults.set(isEnabled, forKey: "isEnabled")
            refreshSuppressedButtons()
        }
    }
    @Published var outputKey: OutputKey {
        didSet {
            if secondKeyRawValue == outputKey.rawValue { secondKeyRawValue = "" }
            defaults.set(outputKey.rawValue, forKey: "outputKey")
            scheduleConflictCheck()
        }
    }
    @Published var secondKeyRawValue: String {
        didSet {
            if secondKeyRawValue.isEmpty {
                defaults.removeObject(forKey: "secondKey")
            } else {
                defaults.set(secondKeyRawValue, forKey: "secondKey")
            }
            scheduleConflictCheck()
        }
    }
    @Published var eventShape: EventShape {
        didSet { defaults.set(eventShape.rawValue, forKey: "eventShape") }
    }

    private let defaults = UserDefaults.standard
    private let monitor = MouseMonitor()
    private let emitter = ShortcutEmitter()
    private var permissionTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private var hasStarted = false
    private var lastAcceptedMouseDown: [Int: DispatchTime] = [:]
    private let debounceNanoseconds: UInt64 = 350_000_000

    init() {
        // Import only this tool's settings from the original local experiment.
        if !defaults.bool(forKey: "didImportMouseTalkSettings") {
            let legacy = UserDefaults(suiteName: "com.tryailab.doubao-mouse")
            for key in ["selectedButton", "returnButton", "backspaceButton", "isEnabled", "outputKey", "secondKey", "eventShape", "didMigrateToOneShotModifierEvents"] {
                if defaults.object(forKey: key) == nil, let value = legacy?.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: "didImportMouseTalkSettings")
        }
        if UserDefaults.standard.object(forKey: "selectedButton") != nil {
            selectedButton = UserDefaults.standard.integer(forKey: "selectedButton")
        } else {
            selectedButton = nil
        }
        if UserDefaults.standard.object(forKey: "returnButton") != nil {
            returnButton = UserDefaults.standard.integer(forKey: "returnButton")
        } else {
            returnButton = nil
        }
        if UserDefaults.standard.object(forKey: "backspaceButton") != nil {
            backspaceButton = UserDefaults.standard.integer(forKey: "backspaceButton")
        } else {
            backspaceButton = nil
        }
        captureTarget = nil
        isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        outputKey = OutputKey.load(rawValue: UserDefaults.standard.string(forKey: "outputKey")) ?? .leftControl
        secondKeyRawValue = OutputKey.load(
            rawValue: UserDefaults.standard.string(forKey: "secondKey")
        )?.rawValue ?? ""
        if UserDefaults.standard.bool(forKey: "didMigrateToOneShotModifierEvents") {
            eventShape = EventShape(rawValue: UserDefaults.standard.string(forKey: "eventShape") ?? "") ?? .keyboard
        } else {
            // Some applications interpret both edges of flagsChanged as
            // separate activations. keyDown/keyUp gives one logical modifier
            // press and is the safer default for toggle shortcuts.
            eventShape = .keyboard
            UserDefaults.standard.set("keyboard", forKey: "eventShape")
            UserDefaults.standard.set(true, forKey: "didMigrateToOneShotModifierEvents")
        }

        if secondKeyRawValue == outputKey.rawValue { secondKeyRawValue = "" }

        monitor.onButtonDown = { [weak self] button in
            self?.handleMouseButtonDown(button)
        }
        monitor.onButtonUp = { [weak self] button in
            self?.handleMouseButtonUp(button)
        }
        monitor.onCancelled = { [weak self] in
            self?.emitter.endBackspace()
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.emitter.endBackspaceSynchronously()
        }
        refreshSuppressedButtons()
    }

    deinit {
        permissionTimer?.invalidate()
        testTimer?.invalidate()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        emitter.endBackspaceSynchronously()
        monitor.stop()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshPermissions()
        scheduleConflictCheck()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    func refreshPermissions() {
        let listen = CGPreflightListenEventAccess()
        // Accessibility's authoritative status. CGPreflightPostEventAccess can
        // disagree with the Privacy & Security Accessibility toggle.
        let post = AXIsProcessTrusted()
        defaults.set(listen, forKey: "diagnosticCanListen")
        defaults.set(post, forKey: "diagnosticAXTrusted")
        defaults.set(Date().timeIntervalSince1970, forKey: "diagnosticLastCheck")
        if listen != canListen { canListen = listen }
        if post != canPost { canPost = post; scheduleConflictCheck() }

        if listen {
            monitorRunning = monitor.start()
        } else {
            monitorRunning = false
        }

        if !listen || !post { emitter.endBackspace() }
    }

    var readiness: String {
        if !canListen || !canPost { return "下一步：打开下面两项权限。" }
        if !monitorRunning { return "权限已开启，请退出并重新打开鼠语，让鼠标监听生效。" }
        if captureTarget != nil { return "正在等待你按下鼠标按钮…" }
        if !isEnabled { return "已暂停 · 打开“启用鼠标控制”后继续使用。" }
        if selectedButton == nil { return "下一步：确认语音软件的快捷键，再绑定一个鼠标侧键。" }
        return "鼠标控制已启用 · 请按第 4 步试说一句，确认语音软件能响应。"
    }

    var voiceAppName: String {
        voiceAppPath.isEmpty ? "" : URL(fileURLWithPath: voiceAppPath).deletingPathExtension().lastPathComponent
    }

    func chooseVoiceApp() {
        let panel = NSOpenPanel()
        panel.title = "选择你用来语音输入的软件"
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        voiceAppPath = url.path
        openVoiceApp()
    }

    func openVoiceApp() {
        guard !voiceAppPath.isEmpty else { chooseVoiceApp(); return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: voiceAppPath), configuration: .init()) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.status = error == nil
                    ? "已打开语音软件。请在它自己的设置中找到语音输入快捷键，再回到鼠语选择相同的按键。"
                    : "无法打开所选软件，请点击“重新选择”找到它的新位置。"
            }
        }
    }

    func beginCapture(_ target: BindingTarget) {
        refreshPermissions()
        guard monitorRunning else {
            status = "还不能监听鼠标。请先授予权限。"
            return
        }
        captureTarget = target
        status = "请按一下要绑定为“\(target.title)”的鼠标侧键…"
    }

    func cancelCapture() {
        captureTarget = nil
        status = "已取消绑定。"
    }

    func clearBinding(_ target: BindingTarget) {
        switch target {
        case .voice: selectedButton = nil
        case .confirm: returnButton = nil
        case .backspace: backspaceButton = nil
        }
        if captureTarget == target { captureTarget = nil }
        status = "已清除“\(target.title)”绑定。"
    }

    func cancelTest() {
        testTimer?.invalidate()
        testTimer = nil
        testCountdown = 0
        status = "已取消试用。"
    }

    func testOutput() {
        guard testCountdown == 0 else { return }
        refreshPermissions()
        guard canPost else {
            status = "请先打开“辅助功能”权限，再试用语音快捷键。"
            return
        }
        let keys = configuredKeys
        let shape = eventShape
        let title = shortcutTitle
        testCountdown = 3
        status = "请切换到要输入文字的软件，点一下输入框；3 秒后触发一次语音快捷键。"
        testTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.testCountdown -= 1
            guard self.testCountdown == 0 else { return }
            timer.invalidate()
            self.testTimer = nil
            guard AXIsProcessTrusted() else {
                self.status = "试用未执行：请打开“辅助功能”权限。"
                return
            }
            self.emitter.emit(keys: keys, shape: shape)
            self.status = "已触发一次 \(title)。如果没有出现语音输入，请检查两边的快捷键是否一致。"
        }
    }

    func openAccessibilitySettings() {
        if !canPost {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        if !canListen { _ = CGRequestListenEventAccess() }
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        if !NSWorkspace.shared.open(url) {
            status = "未能打开系统设置，请手动前往：系统设置 → 隐私与安全性 → 输入监控／辅助功能。"
        }
    }

    private func handleMouseButtonDown(_ button: Int) {
        if let target = captureTarget {
            let previous: [(Int?, String)] = [(selectedButton, "语音快捷键"), (returnButton, "回车发送"), (backspaceButton, "退格")]
            let replaced = previous.filter { $0.0 == button && $0.1 != target.title }.map { $0.1 }
            bindingNotice = replaced.isEmpty ? "" : "这个按钮原来绑定了“\(replaced.joined(separator: "、"))”，已改为“\(target.title)”。"
            switch target {
            case .voice:
                selectedButton = button
                if returnButton == button { returnButton = nil }
                if backspaceButton == button { backspaceButton = nil }
            case .confirm:
                returnButton = button
                if selectedButton == button { selectedButton = nil }
                if backspaceButton == button { backspaceButton = nil }
            case .backspace:
                backspaceButton = button
                if selectedButton == button { selectedButton = nil }
                if returnButton == button { returnButton = nil }
            }
            captureTarget = nil
            isEnabled = true
            status = "“\(target.title)”绑定成功：鼠标按钮 \(button + 1)。"
            return
        }

        guard isEnabled, canPost else { return }

        if backspaceButton == button {
            emitter.beginBackspace()
            status = "鼠标按钮 \(button + 1) → 退格（按住可连续删除）"
            return
        }

        guard selectedButton == button || returnButton == button else { return }
        let now = DispatchTime.now()
        let previous = lastAcceptedMouseDown[button] ?? DispatchTime(uptimeNanoseconds: 0)
        let elapsed = now.uptimeNanoseconds &- previous.uptimeNanoseconds
        guard elapsed >= debounceNanoseconds else {
            status = "已忽略 350ms 内的重复 button \(button + 1) 事件。"
            return
        }
        lastAcceptedMouseDown[button] = now

        if selectedButton == button {
            emitter.emit(keys: configuredKeys, shape: eventShape)
            status = "鼠标按钮 \(button + 1) → \(shortcutTitle)"
        } else {
            emitter.emitReturn()
            status = "鼠标按钮 \(button + 1) → 回车"
        }
    }

    private func handleMouseButtonUp(_ button: Int) {
        guard backspaceButton == button else { return }
        emitter.endBackspace()
        status = "鼠标按钮 \(button + 1) → 退格已释放"
    }

    private func refreshSuppressedButtons() {
        guard isEnabled else {
            monitor.setSuppressedButtons([])
            return
        }
        monitor.setSuppressedButtons(
            Set([selectedButton, returnButton, backspaceButton].compactMap { $0 })
        )
    }

    func scheduleConflictCheck() {
        conflictGeneration = UUID()
        conflictReport = nil
        checkingConflicts = true
        pendingConflictCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkConflicts() }
        pendingConflictCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func checkConflicts() {
        pendingConflictCheck?.cancel()
        let generation = UUID()
        conflictGeneration = generation
        conflictReport = nil
        checkingConflicts = true
        let bindings = [
            BindingSelection(action: "语音快捷键", keys: configuredKeys.map { Int($0.keyCode) }, mouseButton: selectedButton),
            BindingSelection(action: "确认发送", keys: [36], mouseButton: returnButton),
            BindingSelection(action: "删除文字", keys: [51], mouseButton: backspaceButton),
        ]
        let context = ConflictScanner.context()
        conflictQueue.async { [weak self] in
            let report = ConflictScanner.scan(bindings, context: context)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.conflictGeneration == generation else { return }
                self.conflictReport = report
                self.checkingConflicts = false
            }
        }
    }

    var configuredKeys: [OutputKey] {
        let secondKey = OutputKey.load(rawValue: secondKeyRawValue)
        if let secondKey, secondKey != outputKey {
            return [outputKey, secondKey]
        }
        return [outputKey]
    }

    var shortcutTitle: String {
        configuredKeys.map(\.title).joined(separator: " + ")
    }

    var shortcutKeyCodes: String {
        configuredKeys.map { String($0.keyCode) }.joined(separator: " + ")
    }
}

private struct PermissionRow: View {
    let name: String
    let purpose: String
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text(purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(granted ? "已开启" : "待开启").foregroundStyle(.secondary)
            Button(granted ? "查看设置" : "去开启", action: openSettings)
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(nsImage: MouseTalkBrand.image())
                        .resizable().frame(width: 64, height: 64)
                        .accessibilityLabel("鼠语标志：鼠标形状的老鼠头像")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("鼠语 MouseTalk").font(.title.bold())
                        Text("把鼠标变成语音输入的遥控器。")
                    }
                    Spacer()
                }
                Text("按一下鼠标侧键，调用你已有的语音输入软件，把话变成文字；再用另一个按钮按回车发送。鼠语本身不录音，也不做语音识别。")
                    .foregroundStyle(.secondary)
                Label(controller.readiness, systemImage: controller.canListen && controller.canPost && controller.monitorRunning && controller.isEnabled && controller.selectedButton != nil ? "checkmark.circle" : "info.circle")
                    .font(.callout)

                GroupBox("1. 开启两项权限") {
                    VStack(alignment: .leading, spacing: 10) {
                        PermissionRow(name: "输入监控", purpose: "让鼠语识别你按了哪个鼠标按钮。", granted: controller.canListen, openSettings: controller.openInputMonitoringSettings)
                        PermissionRow(name: "辅助功能", purpose: "让鼠语替你按快捷键、回车和退格。", granted: controller.canPost, openSettings: controller.openAccessibilitySettings)
                        Text("点击“去开启”，在系统设置里打开“鼠语 MouseTalk”的开关。如果列表里没有它，点击 ＋，添加“应用程序”里的 MouseTalk.app。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("刷新状态", action: controller.refreshPermissions)
                            Text("开启后若仍未生效，请退出并重新打开鼠语。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 6)
                }

                GroupBox("2. 告诉鼠语：按哪个键能开始说话") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("先在你的语音输入软件里找到“语音输入快捷键”，再在下面选成一样的。")
                        HStack {
                            if controller.voiceAppPath.isEmpty {
                                Button("选择并打开语音软件…", action: controller.chooseVoiceApp)
                            } else {
                                Button("打开 \(controller.voiceAppName)", action: controller.openVoiceApp)
                                Button("重新选择…", action: controller.chooseVoiceApp)
                            }
                        }
                        Text("例如：如果语音软件设为“右 Option”，这里也选“右 Option”，第二个键选“无”。选择软件只是方便打开，不会自动读取或修改它的设置。")
                            .font(.caption).foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("语音快捷键")
                                Picker("语音快捷键", selection: $controller.outputKey) {
                                    ForEach(OutputKey.allCases) { Text($0.title).tag($0) }
                                }.labelsHidden()
                            }
                            GridRow {
                                Text("同时按住的第二个键")
                                Picker("同时按住的第二个键", selection: $controller.secondKeyRawValue) {
                                    Text("无（只按一个键）").tag("")
                                    ForEach(OutputKey.allCases.filter { $0 != controller.outputKey }) { Text($0.title).tag($0.rawValue) }
                                }.labelsHidden()
                            }
                        }
                        Text("鼠语会替你按：\(controller.shortcutTitle)").fontWeight(.medium)
                        Text("目前支持单按 Fn、Control、Option、Command，或同时按其中两个键。请选单按触发；暂不支持双击、长按说话，或带字母／空格的快捷键。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }

                GroupBox("3. 挑一个鼠标按钮来控制语音") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("点击“绑定”，再按一下鼠标侧键或滚轮中键。左键和右键保留正常使用。")
                        bindingRow("语音输入", button: controller.selectedButton, target: .voice)
                        bindingRow("回车发送（选填）", button: controller.returnButton, target: .confirm)
                        bindingRow("删除文字（选填）", button: controller.backspaceButton, target: .backspace)
                        Text("只绑定语音按钮就能用。发送按钮相当于按回车：聊天软件需设为“回车发送”，否则可能换行。删除按钮按一下删一次，按住可连续删除。")
                            .font(.caption).foregroundStyle(.secondary)
                        if !controller.bindingNotice.isEmpty {
                            Text(controller.bindingNotice).font(.callout).foregroundStyle(.orange)
                        }
                        if let target = controller.captureTarget {
                            HStack {
                                Text("现在按一下要用于“\(target.title)”的鼠标按钮…").foregroundStyle(.orange)
                                Button("取消", action: controller.cancelCapture)
                            }
                        }
                        Toggle("启用鼠标控制", isOn: $controller.isEnabled).toggleStyle(.switch)
                        Text("绑定后自动启用，原来的前进／后退等动作会被替换。同一按钮只能做一件事；关闭开关即可恢复原来的动作。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }

                GroupBox("4. 试说一句") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("打开聊天软件或备忘录，点一下输入框 → 按已绑定的语音按钮 → 说一句话 → 按语音软件的方式结束录音，确认文字出现。")
                        Text("如果语音软件支持“再按一次结束”，再按同一个鼠标按钮即可。确认文字后，需要发送时再按你绑定的发送按钮。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if controller.testCountdown > 0 {
                                Text("\(controller.testCountdown) 秒后触发，请切换到输入框…")
                                Button("取消试用", action: controller.cancelTest)
                            } else {
                                Button("3 秒后试用语音快捷键", action: controller.testOutput)
                                    .disabled(!controller.canPost)
                            }
                        }
                        Text("这个按钮只测试语音快捷键，不会替你按回车。平时用鼠标时，请让需要接收文字的输入框保持选中。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(controller.status).font(.callout).textSelection(.enabled)
                        Text("设置自动保存。关闭这个窗口后鼠语仍在运行，从菜单栏的鼠语图标可再次打开设置或退出。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }

                ConflictCheckView(controller: controller)

                DisclosureGroup("按了没反应？排查与高级设置") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("• 键盘直接按也没反应：先检查语音软件是否运行、快捷键是否正确，以及它自己的麦克风权限。")
                        Text("• 键盘能用，鼠标不行：检查鼠语的两项权限、绑定和启用开关。仍无效时，尝试下面的兼容模式。")
                        Text("• 绑定时识别不到按钮：鼠语只能识别标准鼠标按钮；Logi Options+ 等驱动可能已将它改成手势或其他按键，请先在驱动里检查。")
                        Picker("快捷键兼容模式", selection: $controller.eventShape) {
                            ForEach(EventShape.allCases) { Text($0.title).tag($0) }
                        }
                        Text("诊断信息：keycode \(controller.shortcutKeyCodes)").font(.caption.monospaced())
                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }.padding(20)
        }
        .frame(minWidth: 640, minHeight: 680)
        .onAppear { controller.start() }
    }

    private func bindingRow(_ title: String, button: Int?, target: BindingTarget) -> some View {
        HStack {
            Text(title).frame(width: 140, alignment: .leading)
            Text(button.map { "鼠标按钮 \($0 + 1)" } ?? "未绑定").fontWeight(.medium)
            Spacer()
            Button(button == nil ? "绑定" : "重新绑定") { controller.beginCapture(target) }
                .disabled(!controller.monitorRunning)
            Button("清除") { controller.clearBinding(target) }.disabled(button == nil)
        }
    }
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var controller: AppController

    var body: some View {
        Button("打开设置") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        if controller.testCountdown > 0 {
            Button("取消试用（\(controller.testCountdown) 秒）", action: controller.cancelTest)
        } else {
            Button("3 秒后试用：\(controller.shortcutTitle)", action: controller.testOutput)
                .disabled(!controller.canPost)
        }
        Divider()
        Toggle("启用鼠标控制", isOn: $controller.isEnabled)
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }
}

private struct ConflictCheckView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        GroupBox("快捷键有没有被其他软件使用？（自动检查）") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if controller.checkingConflicts {
                        ProgressView().controlSize(.small)
                        Text("正在检查系统与应用公开的快捷键…").font(.callout)
                    } else if controller.selectedButton == nil && controller.returnButton == nil && controller.backspaceButton == nil {
                        Text("请先绑定鼠标按钮")
                    } else if controller.conflictReport == nil {
                        Text("尚未检查，点击“重新检查”开始")
                    } else {
                        Text(controller.conflictReport?.findings.isEmpty == false ? "发现可能重合的绑定" : "已检查范围内未发现重合")
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Button("重新检查", action: controller.checkConflicts)
                        .disabled(controller.checkingConflicts)
                }
                Text("如果这里出现你要控制的语音软件，通常是正常的；如果出现其他软件，请检查是否会一起触发。鼠语不会改动它们的设置。")
                    .font(.caption).foregroundStyle(.secondary)
                if let report = controller.conflictReport {
                    ForEach(report.findings) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Label("\(item.action) · \(item.app)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).fontWeight(.medium)
                            Text(item.function).textSelection(.enabled)
                            Text("\(item.source) · \(item.explanation)").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    DisclosureGroup("检查范围与限制") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.coverage, id: \.self) { Text($0).font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                    Text("单按／双击修饰键和鼠标驱动的内部绑定可能无法读取，未发现重合不代表没有冲突。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("检查于 \(report.checkedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
    }
}

@main
private struct DoubleClickMouseApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup("鼠语 MouseTalk", id: "settings") {
            ContentView()
                .environmentObject(controller)
        }
        .defaultSize(width: 640, height: 680)

        MenuBarExtra {
            MenuContent()
                .environmentObject(controller)
        } label: {
            Image(nsImage: MouseTalkBrand.image(size: 18, template: true))
                .accessibilityLabel("鼠语 MouseTalk")
        }
    }
}
