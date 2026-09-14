import AppKit
import MouseTalkKit

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--export-assets", args.count == 2 {
    let directory = URL(fileURLWithPath: args[1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let iconset = directory.appendingPathComponent("MouseTalk.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        try MouseTalkBrand.exportPNG(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"), pixels: size)
        try MouseTalkBrand.exportPNG(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"), pixels: size * 2)
    }
    try MouseTalkBrand.exportPNG(to: directory.appendingPathComponent("MouseTalk.png"), pixels: 512)
    print("Exported MouseTalk vector mark to \(directory.path)")
} else if args.isEmpty || args == ["--scan"] {
    let context = ConflictScanner.context()
    let report = ConflictScanner.scan([
        BindingSelection(action: "语音快捷键（右 Option 示例）", keys: [61], mouseButton: 3),
        BindingSelection(action: "确认发送", keys: [36], mouseButton: 4),
        BindingSelection(action: "删除文字", keys: [51], mouseButton: 2),
    ], context: context)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    print(String(data: try encoder.encode(report), encoding: .utf8)!)
} else {
    print("Usage: mousetalk-check [--scan | --export-assets DIRECTORY]\nRead-only scan using sample bindings. Never posts keyboard events or requests permissions.")
}
