// Command-line event-shape experiment for Double Click Mouse.
import CoreGraphics
import Darwin
import Foundation

private enum TestKey: String {
    case rightControl = "right-control"
    case rightOption = "right-option"

    var keyCode: CGKeyCode {
        switch self {
        case .rightControl: 62
        case .rightOption: 61
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .rightControl: .maskControl
        case .rightOption: .maskAlternate
        }
    }

    var displayName: String {
        switch self {
        case .rightControl: "Right Control"
        case .rightOption: "Right Option"
        }
    }
}

private enum TestMode: String {
    case single
    case double
}

private enum EventStyle: String {
    case keyboard
    case flagsChanged = "flags-changed"
}

private enum SourceStyle: String {
    case hid
    case none
}

private struct Configuration {
    var key: TestKey = .rightControl
    var mode: TestMode = .single
    var style: EventStyle = .keyboard
    var source: SourceStyle = .hid
    var holdMilliseconds = 30
    var intervalMilliseconds = 100
    var countdownSeconds = 3
    var dryRun = false
}

private let usage = """
double-click-key-test — inspect synthetic modifier-key event behavior

Usage:
  double-click-key-test send [options]

Options:
  --key right-control|right-option    Default: right-control
  --mode single|double                Default: single
  --style keyboard|flags-changed      Default: keyboard
  --source hid|none                   Default: hid
  --hold-ms N                         Down-to-up duration; default: 30
  --interval-ms N                     Double-tap interval; default: 100
  --countdown N                       Seconds before sending; default: 3
  --dry-run                           Validate without posting events
  -h, --help                          Show this help

Suggested test order:
  double-click-key-test send --mode single --style keyboard
  double-click-key-test send --mode double --style keyboard
  double-click-key-test send --mode single --style flags-changed
  double-click-key-test send --mode double --style flags-changed
"""

private enum ArgumentError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(text): text
        }
    }
}

private func parsePositiveOrZero(_ text: String, option: String) throws -> Int {
    guard let value = Int(text), value >= 0 else {
        throw ArgumentError.message("\(option) requires a non-negative integer, got: \(text)")
    }
    return value
}

private func parseArguments() throws -> Configuration? {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments.contains("-h") || arguments.contains("--help") {
        return nil
    }
    guard arguments.first == "send" else {
        throw ArgumentError.message("Expected the 'send' command.\n\n\(usage)")
    }

    var configuration = Configuration()
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--dry-run" {
            configuration.dryRun = true
            index += 1
            continue
        }

        guard index + 1 < arguments.count else {
            throw ArgumentError.message("Missing value for \(argument)")
        }
        let value = arguments[index + 1]
        switch argument {
        case "--key":
            guard let key = TestKey(rawValue: value) else {
                throw ArgumentError.message("Unknown key: \(value)")
            }
            configuration.key = key
        case "--mode":
            guard let mode = TestMode(rawValue: value) else {
                throw ArgumentError.message("Unknown mode: \(value)")
            }
            configuration.mode = mode
        case "--style":
            guard let style = EventStyle(rawValue: value) else {
                throw ArgumentError.message("Unknown style: \(value)")
            }
            configuration.style = style
        case "--source":
            guard let source = SourceStyle(rawValue: value) else {
                throw ArgumentError.message("Unknown source: \(value)")
            }
            configuration.source = source
        case "--hold-ms":
            configuration.holdMilliseconds = try parsePositiveOrZero(value, option: argument)
        case "--interval-ms":
            configuration.intervalMilliseconds = try parsePositiveOrZero(value, option: argument)
        case "--countdown":
            configuration.countdownSeconds = try parsePositiveOrZero(value, option: argument)
        default:
            throw ArgumentError.message("Unknown option: \(argument)")
        }
        index += 2
    }
    return configuration
}

private func sleep(milliseconds: Int) {
    guard milliseconds > 0 else { return }
    usleep(useconds_t(milliseconds * 1_000))
}

private func makeSource(_ style: SourceStyle) -> CGEventSource? {
    switch style {
    case .hid:
        CGEventSource(stateID: .hidSystemState)
    case .none:
        nil
    }
}

private func postTap(key: TestKey, style: EventStyle, source: CGEventSource?, holdMilliseconds: Int) throws {
    guard
        let down = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: false)
    else {
        throw ArgumentError.message("Could not create CGEvent keyboard events")
    }

    // A physical modifier press changes both its key position and the aggregate
    // modifier flags. Supplying both lets us compare the two event shapes.
    down.flags = key.flag
    up.flags = []
    if style == .flagsChanged {
        down.type = .flagsChanged
        up.type = .flagsChanged
    }

    down.post(tap: .cghidEventTap)
    sleep(milliseconds: holdMilliseconds)
    up.post(tap: .cghidEventTap)
}

private func printPermissionInstructions() {
    fputs("""
    \nNo permission to post keyboard events.

    Open:
      System Settings
      → Privacy & Security
      → Accessibility

    Enable Terminal (or double-click-key-test if it appears directly), then run the test again.
    \n
    """, stderr)
}

do {
    guard let configuration = try parseArguments() else {
        print(usage)
        exit(EXIT_SUCCESS)
    }

    let tapCount = configuration.mode == .double ? 2 : 1
    print("Test: \(configuration.mode.rawValue) \(configuration.key.displayName)")
    print("Event style: \(configuration.style.rawValue); source: \(configuration.source.rawValue)")
    print("Timing: hold \(configuration.holdMilliseconds) ms; interval \(configuration.intervalMilliseconds) ms")
    fflush(stdout)

    if configuration.dryRun {
        print("Dry run complete; no event was posted.")
        exit(EXIT_SUCCESS)
    }

    guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
        printPermissionInstructions()
        exit(EXIT_FAILURE)
    }

    if configuration.countdownSeconds > 0 {
        print("Focus a text field. Sending in \(configuration.countdownSeconds) second(s)…")
        for remaining in stride(from: configuration.countdownSeconds, through: 1, by: -1) {
            print("\(remaining)…")
            fflush(stdout)
            sleep(1)
        }
    }

    let source = makeSource(configuration.source)
    for tapIndex in 0..<tapCount {
        try postTap(
            key: configuration.key,
            style: configuration.style,
            source: source,
            holdMilliseconds: configuration.holdMilliseconds
        )
        if tapIndex + 1 < tapCount {
            sleep(milliseconds: configuration.intervalMilliseconds)
        }
    }
    print("Event sequence posted.")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
