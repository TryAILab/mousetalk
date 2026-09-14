// 鼠语 MouseTalk menu bar application.
import ApplicationServices
import AppKit
import CoreGraphics
import SwiftUI
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
        case .keyboard: "标准 keyDown / keyUp（推荐）"
        case .flagsChanged: "修饰键 flagsChanged（兼容测试）"
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
        case .confirm: "Return"
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
    @Published var status = "等待权限检查…"
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
        didSet { defaults.set(outputKey.rawValue, forKey: "outputKey"); scheduleConflictCheck() }
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

    func requestPermissions() {
        _ = CGRequestListenEventAccess()
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        refreshPermissions()
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

        if !listen || !post {
            emitter.endBackspace()
            status = "请授予 Input Monitoring 和 Accessibility 权限。授权后可能需要重新打开应用。"
        } else if !monitorRunning {
            status = "权限已授予，但鼠标监听器尚未启动；请重新打开应用。"
        } else if selectedButton == nil || returnButton == nil || backspaceButton == nil {
            status = "权限正常。可以分别绑定语音、Return 和退格按钮。"
        } else {
            status = "正在监听语音、Return 和退格三个鼠标按钮。"
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

    func testOutput() {
        refreshPermissions()
        guard canPost else {
            status = "还不能发送快捷键。请先授予 Accessibility 权限。"
            return
        }
        let keys = configuredKeys
        emitter.emit(keys: keys, shape: eventShape)
        status = "已发送：\(shortcutTitle)。"
    }

    func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleMouseButtonDown(_ button: Int) {
        if let target = captureTarget {
            let previous: [(Int?, String)] = [(selectedButton, "语音快捷键"), (returnButton, "Return"), (backspaceButton, "退格")]
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
            status = "“\(target.title)”绑定成功：button \(button + 1)。"
            return
        }

        guard isEnabled, canPost else { return }

        if backspaceButton == button {
            emitter.beginBackspace()
            status = "鼠标 button \(button + 1) → 退格（按住可连续删除）"
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
            status = "鼠标 button \(button + 1) → \(shortcutTitle)"
        } else {
            emitter.emitReturn()
            status = "鼠标 button \(button + 1) → Return"
        }
    }

    private func handleMouseButtonUp(_ button: Int) {
        guard backspaceButton == button else { return }
        emitter.endBackspace()
        status = "鼠标 button \(button + 1) → 退格已释放"
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
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(name)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .foregroundStyle(.secondary)
            Button("打开设置", action: openSettings)
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
                        .resizable().frame(width: 76, height: 76)
                        .accessibilityLabel("鼠语标志：鼠标形状的老鼠头像")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("鼠语").font(.largeTitle.bold())
                        Text("MouseTalk").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("随口说，随手发。用鼠标触发语音输入、发送和退格。")
                    .foregroundStyle(.secondary)

                GroupBox("1. 权限") {
                    VStack(spacing: 10) {
                        PermissionRow(
                            name: "Input Monitoring（监听鼠标）",
                            granted: controller.canListen,
                            openSettings: controller.openInputMonitoringSettings
                        )
                        PermissionRow(
                            name: "Accessibility（发送按键、检查菜单）",
                            granted: controller.canPost,
                            openSettings: controller.openAccessibilitySettings
                        )
                        HStack {
                            Button("请求并刷新权限", action: controller.requestPermissions)
                            Text("首次授权后若状态未更新，请退出并重新打开应用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("2. 目标应用设置") {
                    Text("先在目标应用中选择一个修饰键或双修饰键组合作为快捷键；下面的输出设置必须与目标应用保持一致。")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }

                GroupBox("3. 绑定鼠标按钮") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("语音快捷键：")
                                .frame(width: 80, alignment: .leading)
                            Text(controller.selectedButton.map { "CG button \($0)（button \($0 + 1)）" } ?? "尚未绑定")
                                .fontWeight(.semibold)
                            Spacer()
                            Button("绑定") { controller.beginCapture(.voice) }
                            Button("清除") { controller.clearBinding(.voice) }
                                .disabled(controller.selectedButton == nil)
                        }
                        HStack {
                            Text("确认发送：")
                                .frame(width: 80, alignment: .leading)
                            Text(controller.returnButton.map { "CG button \($0)（button \($0 + 1)）→ Return" } ?? "尚未绑定")
                                .fontWeight(.semibold)
                            Spacer()
                            Button("绑定") { controller.beginCapture(.confirm) }
                            Button("清除") { controller.clearBinding(.confirm) }
                                .disabled(controller.returnButton == nil)
                        }
                        HStack {
                            Text("删除文字：")
                                .frame(width: 80, alignment: .leading)
                            Text(controller.backspaceButton.map { "CG button \($0)（button \($0 + 1)）→ 退格" } ?? "尚未绑定")
                                .fontWeight(.semibold)
                            Spacer()
                            Button("绑定") { controller.beginCapture(.backspace) }
                            Button("清除") { controller.clearBinding(.backspace) }
                                .disabled(controller.backspaceButton == nil)
                        }
                        if !controller.bindingNotice.isEmpty {
                            Text(controller.bindingNotice).font(.callout).foregroundStyle(.orange)
                        }
                        if let target = controller.captureTarget {
                            HStack {
                                Button("取消", action: controller.cancelCapture)
                                Text("现在按一下要绑定为“\(target.title)”的鼠标侧键…")
                                    .foregroundStyle(.orange)
                            }
                        }
                        HStack {
                            Toggle("启用映射", isOn: $controller.isEnabled)
                                .toggleStyle(.switch)
                            Text("启用后会阻止已绑定侧键原本的前进/后退动作。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("退格键点击一次删除一次；持续按住鼠标按钮会按系统键盘重复速度连续删除。同一个按钮不能同时承担两个动作。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }

                GroupBox("4. 输出快捷键") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("按键")
                            Picker("按键", selection: $controller.outputKey) {
                                ForEach(OutputKey.allCases) { key in
                                    Text(key.title).tag(key)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("第二个键")
                            Picker("第二个键", selection: $controller.secondKeyRawValue) {
                                Text("无（单键）").tag("")
                                ForEach(OutputKey.allCases) { key in
                                    Text(key.title).tag(key.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("实际输出")
                            Text("\(controller.shortcutTitle)（keycode \(controller.shortcutKeyCodes)）")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("事件格式")
                            Picker("事件格式", selection: $controller.eventShape) {
                                ForEach(EventShape.allCases) { shape in
                                    Text(shape.title).tag(shape)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 6)
                }

                ConflictCheckView(controller: controller)

                HStack {
                    Button("直接测试输出", action: controller.testOutput)
                        .keyboardShortcut(.defaultAction)
                    Text(controller.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 680)
        .onAppear { controller.start() }
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
        Button("测试：\(controller.shortcutTitle)") {
            controller.testOutput()
        }
        Divider()
        Toggle("启用鼠标映射", isOn: $controller.isEnabled)
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }
}

private struct ConflictCheckView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        GroupBox("5. 快捷键冲突检查") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if controller.checkingConflicts {
                        ProgressView().controlSize(.small)
                        Text("正在检查系统与应用公开的快捷键…").font(.callout)
                    } else if controller.selectedButton == nil && controller.returnButton == nil && controller.backspaceButton == nil {
                        Text("请先绑定鼠标按钮")
                    } else {
                        Text(controller.conflictReport?.findings.isEmpty == false ? "发现可能重合的绑定" : "已检查范围内未发现重合")
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Button("重新检查", action: controller.checkConflicts)
                        .disabled(controller.checkingConflicts)
                }
                Text("与目标语音软件使用相同快捷键是预期行为；下列记录需结合实际用途判断，不会自动改动其他软件。")
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
