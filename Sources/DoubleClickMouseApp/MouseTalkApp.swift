// 妙语 MouseTalk menu bar application.
import ApplicationServices
import AppKit
import CoreGraphics
import SwiftUI
import MouseTalkKit

private enum ProjectLinks {
    static let github = URL(string: "https://github.com/TryAILab/mousetalk")!
    static let feedback = URL(string: "https://github.com/TryAILab/mousetalk/issues/new/choose")!
}

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
    case copy
    case paste

    var title: String {
        switch self {
        case .voice: "语音快捷键"
        case .confirm: "回车发送"
        case .backspace: "退格"
        case .copy: "复制"
        case .paste: "粘贴"
        }
    }
}

private enum DoubleRightAction: String, CaseIterable, Identifiable {
    case none
    case copy
    case paste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "关闭"
        case .copy: "复制（⌘C）"
        case .paste: "粘贴（⌘V）"
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
        emitKey(36)
    }

    func emitCopy() {
        emitKey(8, flags: .maskCommand)
    }

    func emitPaste() {
        emitKey(9, flags: .maskCommand)
    }

    private func emitKey(_ keyCode: CGKeyCode, flags: CGEventFlags? = nil) {
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            else { return }
            let outputFlags = flags ?? CGEventSource.flagsState(.combinedSessionState)
            down.flags = outputFlags
            up.flags = outputFlags
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

    if event.getIntegerValueField(.eventSourceUserData) == MouseMonitor.replayedEventMarker {
        return Unmanaged.passUnretained(event)
    }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reenable()
    } else if type == .rightMouseDown || type == .rightMouseUp {
        if monitor.handleRightMouseEvent(type: type, event: event) { return nil }
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
    static let replayedEventMarker: Int64 = 0x4D54524C

    var onButtonDown: ((Int) -> Void)?
    var onButtonUp: ((Int) -> Void)?
    var onRightDoubleClick: (() -> Void)?
    var onCancelled: (() -> Void)?
    private var suppressedButtons: Set<Int> = []
    private var rightDoubleClickEnabled = false
    private var pendingRightDown: CGEvent?
    private var pendingRightUp: CGEvent?
    private var rightClickTimer: Timer?
    private var suppressNextRightUp = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap.map(CGEvent.tapIsEnabled) ?? false }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        stop()

        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseUp.rawValue)
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
        replayPendingRightClick()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        if let tap { CFMachPortInvalidate(tap) }
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

    func setRightDoubleClickEnabled(_ enabled: Bool) {
        guard enabled != rightDoubleClickEnabled else { return }
        if !enabled { replayPendingRightClick() }
        rightDoubleClickEnabled = enabled
    }

    /// Returns true when the physical event must be held or suppressed.
    func handleRightMouseEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard rightDoubleClickEnabled else { return false }

        if type == .rightMouseDown {
            if pendingRightDown != nil {
                rightClickTimer?.invalidate()
                rightClickTimer = nil
                pendingRightDown = nil
                pendingRightUp = nil
                suppressNextRightUp = true
                DispatchQueue.main.async { [weak self] in self?.onRightDoubleClick?() }
                return true
            }

            pendingRightDown = event.copy()
            pendingRightUp = nil
            let timer = Timer(timeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
                self?.replayPendingRightClick()
            }
            rightClickTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            return true
        }

        if suppressNextRightUp {
            suppressNextRightUp = false
            return true
        }
        if pendingRightDown != nil {
            pendingRightUp = event.copy()
            return true
        }
        return false
    }

    private func replayPendingRightClick() {
        rightClickTimer?.invalidate()
        rightClickTimer = nil
        guard let down = pendingRightDown else { return }
        let up = pendingRightUp
        pendingRightDown = nil
        pendingRightUp = nil
        down.setIntegerValueField(.eventSourceUserData, value: Self.replayedEventMarker)
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        if let up {
            up.setIntegerValueField(.eventSourceUserData, value: Self.replayedEventMarker)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            up.post(tap: .cghidEventTap)
        }
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
    @Published var status = ""
    @Published var testCountdown = 0
    @Published var isRestarting = false
    @Published var repairingPermission = false
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
    @Published var copyButton: Int? {
        didSet {
            if let copyButton {
                defaults.set(copyButton, forKey: "copyButton")
            } else {
                defaults.removeObject(forKey: "copyButton")
            }
            refreshSuppressedButtons()
            scheduleConflictCheck()
        }
    }
    @Published var pasteButton: Int? {
        didSet {
            if let pasteButton {
                defaults.set(pasteButton, forKey: "pasteButton")
            } else {
                defaults.removeObject(forKey: "pasteButton")
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
            refreshRightDoubleClick()
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
    @Published var doubleRightAction: DoubleRightAction {
        didSet {
            defaults.set(doubleRightAction.rawValue, forKey: "doubleRightAction")
            refreshRightDoubleClick()
        }
    }

    private let defaults = UserDefaults.standard
    private let monitor = MouseMonitor()
    private let emitter = ShortcutEmitter()
    private var permissionTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
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
        if UserDefaults.standard.object(forKey: "copyButton") != nil {
            copyButton = UserDefaults.standard.integer(forKey: "copyButton")
        } else {
            copyButton = nil
        }
        if UserDefaults.standard.object(forKey: "pasteButton") != nil {
            pasteButton = UserDefaults.standard.integer(forKey: "pasteButton")
        } else {
            pasteButton = nil
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
        doubleRightAction = DoubleRightAction(
            rawValue: UserDefaults.standard.string(forKey: "doubleRightAction") ?? ""
        ) ?? .none

        if secondKeyRawValue == outputKey.rawValue { secondKeyRawValue = "" }

        monitor.onButtonDown = { [weak self] button in
            self?.handleMouseButtonDown(button)
        }
        monitor.onButtonUp = { [weak self] button in
            self?.handleMouseButtonUp(button)
        }
        monitor.onRightDoubleClick = { [weak self] in
            self?.handleRightDoubleClick()
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
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshPermissions() }
        refreshSuppressedButtons()
        refreshRightDoubleClick()
    }

    deinit {
        permissionTimer?.invalidate()
        testTimer?.invalidate()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
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
        guard !isRestarting, !repairingPermission else { return }
        let listen = CGPreflightListenEventAccess()
        // Accessibility's authoritative status. CGPreflightPostEventAccess can
        // disagree with the Privacy & Security Accessibility toggle.
        let post = AXIsProcessTrusted()
        defaults.set(listen, forKey: "diagnosticCanListen")
        defaults.set(post, forKey: "diagnosticAXTrusted")
        defaults.set(Date().timeIntervalSince1970, forKey: "diagnosticLastCheck")
        if listen != canListen { canListen = listen }
        if post != canPost { canPost = post; scheduleConflictCheck() }

        if listen && post {
            monitorRunning = monitor.start()
        } else {
            monitor.stop()
            monitorRunning = false
            captureTarget = nil
        }
        defaults.set(monitorRunning, forKey: "diagnosticMonitorRunning")

        if !listen || !post { emitter.endBackspace() }
    }

    var readiness: String {
        if isRestarting { return "正在重新打开…" }
        if repairingPermission { return "正在清除旧授权…" }
        if !canListen || !canPost { return "权限尚未生效" }
        if !monitorRunning { return "监听未启动，请重新打开" }
        if !isEnabled { return "已暂停" }
        if selectedButton == nil { return "待绑定语音按钮" }
        return "已就绪"
    }

    func restartApp() {
        guard !isRestarting, !repairingPermission else { return }
        isRestarting = true
        cancelTest()
        captureTarget = nil
        emitter.endBackspaceSynchronously()
        monitor.stop()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                if app != nil, error == nil { NSApp.terminate(nil) }
                else {
                    self?.isRestarting = false
                    self?.status = "重新打开失败，请退出后手动打开妙语。"
                    self?.refreshPermissions()
                }
            }
        }
    }

    func repairPermission(_ service: String) {
        guard ["ListenEvent", "Accessibility"].contains(service),
              let identifier = Bundle.main.bundleIdentifier,
              !repairingPermission, !isRestarting else { return }
        repairingPermission = true
        cancelTest()
        captureTarget = nil
        emitter.endBackspaceSynchronously()
        monitor.stop()
        monitorRunning = false
        // Only reset this app's selected permission. macOS still requires the
        // user to grant it again; never edit TCC or grant access ourselves.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, identifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] task in
            DispatchQueue.main.async {
                guard let self else { return }
                self.repairingPermission = false
                self.refreshPermissions()
                if task.terminationStatus == 0 {
                    self.status = "旧授权已清除，请在系统设置中重新添加并开启妙语。"
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    self.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_" + (service == "ListenEvent" ? "ListenEvent" : "Accessibility"))
                } else {
                    self.status = "请在系统设置中移除妙语旧条目，再用 ＋ 添加当前应用。"
                }
            }
        }
        do { try process.run() }
        catch {
            repairingPermission = false
            status = "未能清除旧授权，请在系统设置中移除旧条目再添加。"
            refreshPermissions()
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
        case .copy: copyButton = nil
        case .paste: pasteButton = nil
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
            let previous: [(Int?, String)] = [
                (selectedButton, "语音快捷键"),
                (returnButton, "回车发送"),
                (backspaceButton, "退格"),
                (copyButton, "复制"),
                (pasteButton, "粘贴"),
            ]
            let replaced = previous.filter { $0.0 == button && $0.1 != target.title }.map { $0.1 }
            bindingNotice = replaced.isEmpty ? "" : "这个按钮原来绑定了“\(replaced.joined(separator: "、"))”，已改为“\(target.title)”。"
            if selectedButton == button { selectedButton = nil }
            if returnButton == button { returnButton = nil }
            if backspaceButton == button { backspaceButton = nil }
            if copyButton == button { copyButton = nil }
            if pasteButton == button { pasteButton = nil }
            switch target {
            case .voice:
                selectedButton = button
            case .confirm:
                returnButton = button
            case .backspace:
                backspaceButton = button
            case .copy:
                copyButton = button
            case .paste:
                pasteButton = button
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

        guard selectedButton == button || returnButton == button || copyButton == button || pasteButton == button else { return }
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
        } else if returnButton == button {
            emitter.emitReturn()
            status = "鼠标按钮 \(button + 1) → 回车"
        } else if copyButton == button {
            emitter.emitCopy()
            status = "鼠标按钮 \(button + 1) → 复制（⌘C）"
        } else if pasteButton == button {
            emitter.emitPaste()
            status = "鼠标按钮 \(button + 1) → 粘贴（⌘V）"
        }
    }

    private func handleRightDoubleClick() {
        guard isEnabled, canPost else { return }
        switch doubleRightAction {
        case .none:
            return
        case .copy:
            emitter.emitCopy()
            status = "双击右键 → 复制（⌘C）"
        case .paste:
            emitter.emitPaste()
            status = "双击右键 → 粘贴（⌘V）"
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
            Set([selectedButton, returnButton, backspaceButton, copyButton, pasteButton].compactMap { $0 })
        )
    }

    private func refreshRightDoubleClick() {
        monitor.setRightDoubleClickEnabled(isEnabled && doubleRightAction != .none)
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

private struct HelpButton: View {
    let title: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("\(title)说明")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(text).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle) { showing = false; action() }
                }
            }.padding(16).frame(width: 300)
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    let openSettings: () -> Void
    let repair: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.fill")
                .foregroundStyle(granted ? .green : .orange).font(.caption)
            Text(name)
            HelpButton(title: name, text: "在系统设置中开启妙语的\(name)权限。若开关已开启但这里未生效，先试“重新打开”。\n\n更新应用后仍无效时，点击下面的按钮清除妙语这一项旧授权，再用 ＋ 添加当前 MouseTalk.app 并开启。需要你在系统设置中重新授权。", actionTitle: "清除旧授权并前往设置", action: repair)
            Spacer()
            Text(granted ? "已开启" : "未生效").font(.caption).foregroundStyle(.secondary)
            Button(granted ? "查看" : "去设置", action: openSettings)
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var controller: AppController
    @State private var showingConflicts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: MouseTalkBrand.image()).resizable().frame(width: 44, height: 44)
                        .accessibilityLabel("妙语标志")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("妙语 MouseTalk").font(.title2.bold())
                        Text(controller.readiness).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("启用", isOn: $controller.isEnabled).toggleStyle(.switch)
                    HelpButton(title: "妙语", text: "用鼠标触发豆包等输入法已有的语音快捷键。妙语负责按键，输入法负责识别语音，无需选择或绑定软件。\n\n设置自动保存。关掉窗口后仍在菜单栏运行，关闭“启用”恢复鼠标原来的动作。")
                }

                GroupBox("权限") {
                    VStack(spacing: 8) {
                        PermissionRow(name: "输入监控", granted: controller.canListen, openSettings: controller.openInputMonitoringSettings, repair: { controller.repairPermission("ListenEvent") })
                        PermissionRow(name: "辅助功能", granted: controller.canPost, openSettings: controller.openAccessibilitySettings, repair: { controller.repairPermission("Accessibility") })
                        if !controller.canListen || !controller.canPost || !controller.monitorRunning {
                            HStack {
                                Spacer()
                                Button("刷新", action: controller.refreshPermissions)
                                Button("重新打开", action: controller.restartApp)
                                    .disabled(controller.isRestarting || controller.repairingPermission)
                            }
                        }
                    }.padding(.top, 4)
                }

                GroupBox("语音快捷键") {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Picker("语音快捷键", selection: $controller.outputKey) {
                                ForEach(OutputKey.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                            Text("+").foregroundStyle(.secondary)
                            Picker("第二个键", selection: $controller.secondKeyRawValue) {
                                Text("无").tag("")
                                ForEach(OutputKey.allCases.filter { $0 != controller.outputKey }) { Text($0.title).tag($0.rawValue) }
                            }.labelsHidden()
                            HelpButton(title: "语音快捷键", text: "选成和豆包输入法中一样的快捷键即可。例如豆包设为“右 Option”，这里也选“右 Option”，第二个键选“无”。\n\n支持单按 Fn、Control、Option、Command 或其中两个键同时按；暂不支持双击、长按说话，以及带字母或空格的组合。")
                        }
                        Link(
                            "没有语音输入法？下载豆包输入法",
                            destination: URL(string: "https://ime.doubao.com/pc")!
                        )
                        .font(.caption)
                        .help("打开豆包输入法官方下载页")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }

                GroupBox("鼠标按钮") {
                    VStack(spacing: 10) {
                        bindingRow("语音", button: controller.selectedButton, target: .voice, help: "点击绑定，再按一个鼠标侧键或滚轮中键。它会触发上方的语音快捷键。若输入法支持再按一次结束录音，同一个鼠标键也能结束录音。")
                        bindingRow("发送", button: controller.returnButton, target: .confirm, help: "可选。相当于按回车，聊天软件需设为“回车发送”，否则可能换行。妙语不会自动选择输入框。")
                        bindingRow("删除", button: controller.backspaceButton, target: .backspace, help: "可选。按一下删除一次，按住连续删除。一个鼠标按钮只能绑定一个动作。")
                        bindingRow("复制", button: controller.copyButton, target: .copy, help: "可选。相当于 macOS 的 ⌘C，复制当前选中的内容。")
                        bindingRow("粘贴", button: controller.pasteButton, target: .paste, help: "可选。相当于 macOS 的 ⌘V，把剪贴板内容粘贴到当前输入位置。")
                        if let target = controller.captureTarget {
                            HStack {
                                Text("按一个鼠标按钮，用于\(target.title)…").foregroundStyle(.orange)
                                Spacer()
                                Button("取消", action: controller.cancelCapture)
                            }.font(.callout)
                        }
                        if !controller.bindingNotice.isEmpty {
                            Text(controller.bindingNotice).font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(.top, 4)
                }

                HStack {
                    if controller.testCountdown > 0 {
                        Button("取消测试（\(controller.testCountdown) 秒）", action: controller.cancelTest)
                    } else {
                        Button("测试语音", action: controller.testOutput).disabled(!controller.canPost)
                    }
                    HelpButton(title: "测试语音", text: "点击后有 3 秒时间切回聊天窗口并选中输入框，然后触发一次语音快捷键。测试不会按回车发送。")
                    Spacer()
                    Button { showingConflicts.toggle() } label: {
                        Text(controller.checkingConflicts ? "检查中…" : (controller.conflictReport?.findings.isEmpty == false ? "查看快捷键重合" : "快捷键检查"))
                    }.popover(isPresented: $showingConflicts) {
                        ScrollView { ConflictCheckView(controller: controller).padding(14) }.frame(width: 460, height: 360)
                    }
                }
                if !controller.status.isEmpty {
                    Text(controller.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("高级") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("兼容模式", selection: $controller.eventShape) {
                                ForEach(EventShape.allCases) { Text($0.title).tag($0) }
                            }
                            HelpButton(title: "按了没反应？", text: "先用键盘确认豆包的快捷键能用，再检查妙语权限、绑定和启用开关。键盘能用而鼠标无效时，可以尝试兼容模式。\n\n滚轮中键通常可以绑定。PPI／DPI 键有时由鼠标硬件或驱动直接处理，如果点击“绑定”后按它没有反应，妙语就无法读取这个键。")
                        }
                        HStack {
                            Picker("双击右键", selection: $controller.doubleRightAction) {
                                ForEach(DoubleRightAction.allCases) { Text($0.title).tag($0) }
                            }
                            HelpButton(title: "双击右键", text: "可选。单击右键仍打开正常菜单，双击右键执行复制或粘贴。\n\n为了判断是否双击，开启后单击右键会延迟一个系统双击间隔。若感觉右键反应变慢，请关闭此项。")
                        }
                    }.padding(.top, 6)
                }.font(.callout)
                Divider()
                HStack(spacing: 18) {
                    Link("GitHub 源码 ↗", destination: ProjectLinks.github)
                    Link("提供反馈 ↗", destination: ProjectLinks.feedback)
                    Spacer()
                    Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                        .foregroundStyle(.secondary)
                }.font(.caption)
                Text("反馈会在浏览器中打开 GitHub；不会自动发送设置或诊断信息。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }
        .frame(minWidth: 480, minHeight: 500)
        .onAppear { controller.start() }
    }

    private func bindingRow(_ title: String, button: Int?, target: BindingTarget, help: String) -> some View {
        HStack {
            Text(title).frame(width: 32, alignment: .leading)
            HelpButton(title: title, text: help)
            Text(button.map { "按钮 \($0 + 1)" } ?? "未绑定").foregroundStyle(.secondary)
            Spacer()
            Button(button == nil ? "绑定" : "更改") { controller.beginCapture(target) }
                .disabled(!controller.monitorRunning || controller.isRestarting || controller.repairingPermission)
            Button { controller.clearBinding(target) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).disabled(button == nil).help("清除\(title)绑定").accessibilityLabel("清除\(title)绑定")
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
        Link("GitHub 源码", destination: ProjectLinks.github)
        Link("提供反馈", destination: ProjectLinks.feedback)
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
                    } else if controller.selectedButton == nil && controller.returnButton == nil && controller.backspaceButton == nil && controller.copyButton == nil && controller.pasteButton == nil {
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
                Text("如果这里出现你要控制的语音软件，通常是正常的；如果出现其他软件，请检查是否会一起触发。妙语不会改动它们的设置。")
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
        WindowGroup("妙语 MouseTalk", id: "settings") {
            ContentView()
                .environmentObject(controller)
        }
        .defaultSize(width: 500, height: 560)

        MenuBarExtra {
            MenuContent()
                .environmentObject(controller)
        } label: {
            Image(nsImage: MouseTalkBrand.image(size: 18, template: true))
                .accessibilityLabel("妙语 MouseTalk")
        }
    }
}
