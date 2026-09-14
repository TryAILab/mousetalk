import XCTest
import Carbon
@testable import MouseTalkKit

final class ConflictTests: XCTestCase {
    let voice = BindingSelection(action: "语音", keys: [59], mouseButton: 3)

    func testModifierAloneDoesNotConflictWithModifiedLetter() {
        XCTAssertFalse(ShortcutMatch.matches(voice, keyCode: 8, flags: ShortcutMatch.control))
        XCTAssertTrue(ShortcutMatch.matches(voice, keyCode: 62, flags: ShortcutMatch.control))
        XCTAssertFalse(ShortcutMatch.matches(voice, keyCode: 59, flags: ShortcutMatch.control | ShortcutMatch.option))
    }

    func testTwoModifiersRequireTheCompleteCombination() {
        let pair = BindingSelection(action: "语音", keys: [61, 62], mouseButton: 3)
        XCTAssertFalse(ShortcutMatch.matches(pair, keyCode: 58, flags: ShortcutMatch.option))
        XCTAssertTrue(ShortcutMatch.matches(pair, keyCode: 59, flags: ShortcutMatch.option))
    }

    func testMenuDefaultCommandModifierIsNotPlainReturn() {
        let send = BindingSelection(action: "发送", keys: [36], mouseButton: 4)
        XCTAssertFalse(ShortcutMatch.matches(send, keyCode: 36, flags: ShortcutMatch.menuFlags(0)))
        XCTAssertTrue(ShortcutMatch.matches(send, keyCode: 36, flags: ShortcutMatch.menuFlags(8)))
        XCTAssertFalse(ShortcutMatch.matches(send, keyCode: 36, flags: ShortcutMatch.menuFlags(9)))
    }

    func testCarbonFlagsAreConvertedInsteadOfTreatedAsCGFlags() {
        XCTAssertEqual(ShortcutMatch.carbonFlags(UInt32(controlKey | optionKey)), ShortcutMatch.control | ShortcutMatch.option)
        XCTAssertEqual(ShortcutMatch.carbonFlags(UInt32(cmdKey)), ShortcutMatch.command)
        XCTAssertEqual(ShortcutMatch.carbonFlags(UInt32(kEventKeyModifierFnMask)), ShortcutMatch.fn)
    }

    func testCustomMenuEquivalentPreservesModifiersAndDelete() {
        XCTAssertEqual(ShortcutMatch.equivalent("@\r")?.0, 36)
        XCTAssertEqual(ShortcutMatch.equivalent("@\r")?.1, ShortcutMatch.command)
        XCTAssertEqual(ShortcutMatch.equivalent("\u{7f}")?.0, 51)
        XCTAssertNil(ShortcutMatch.equivalent("@C"))
    }

    func testKarabinerUsesSelectedProfileAndCorrectMouseNumbering() {
        let item: [String: Any] = ["from": ["pointing_button": "button4"], "to": [["key_code": "left_control"]]]
        let other: [String: Any] = ["from": ["pointing_button": "button3"], "to": [["key_code": "escape"]]]
        let root: [String: Any] = ["profiles": [
            ["selected": false, "simple_modifications": [item]],
            ["selected": true, "simple_modifications": [other], "complex_modifications": ["rules": [
                ["description": "开始录音", "manipulators": [item]]
            ]]]
        ]]
        let findings = ConflictScanner.karabinerFindings(root, bindings: [voice])
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.function, "开始录音")
        XCTAssertTrue(findings.first?.explanation.contains("button4 → left_control") == true)
    }

    func testNoMatchingBindingDoesNotClaimCompleteCoverage() {
        let context = ScanContext(applications: [], systemKeys: [], systemReadable: false, trusted: false)
        let report = ConflictScanner.scan([], context: context, home: URL(fileURLWithPath: "/nonexistent-mousetalk-test"))
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertTrue(report.coverage.contains { $0.contains("读取失败") })
        XCTAssertTrue(report.coverage.contains { $0.contains("尚无辅助功能权限") })
        XCTAssertTrue(report.coverage.contains { $0.contains("不等于没有冲突") })
    }

    func testDisabledSystemShortcutIsIgnored() {
        let key: [String: Any] = [kHISymbolicHotKeyEnabled as String: false,
                                 kHISymbolicHotKeyCode as String: 59,
                                 kHISymbolicHotKeyModifiers as String: controlKey]
        let context = ScanContext(applications: [], systemKeys: [key], systemReadable: true, trusted: false)
        let report = ConflictScanner.scan([voice], context: context, home: URL(fileURLWithPath: "/nonexistent-mousetalk-test"))
        XCTAssertFalse(report.findings.contains { $0.app == "macOS" })
    }

    func testDriverDetectionDoesNotConfuseLoginwindowWithLogitech() {
        XCTAssertFalse(ConflictScanner.isMouseDriver("com.apple.loginwindow"))
        XCTAssertTrue(ConflictScanner.isMouseDriver("com.logi.optionsplus"))
        XCTAssertTrue(ConflictScanner.isMouseDriver("com.hegenberg.BetterTouchTool"))
    }
}
