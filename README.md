# Double Click Mouse

A small, local-only macOS menu bar app that maps extra mouse buttons to a
modifier shortcut, Return, or Backspace. It was originally built to control a
voice-input shortcut without reaching for the keyboard, but it works with any
macOS app that accepts the configured shortcut.

The app does not use the network, collect analytics, record audio, or read the
contents of your keystrokes. It only listens for standard `otherMouseDown` and
`otherMouseUp` events and emits the actions you configure.

## Features

- Bind an extra mouse button to one modifier key or a two-key combination.
- Bind separate buttons to Return and Backspace.
- Hold the Backspace button to repeat at the macOS keyboard-repeat rate.
- Suppress the original action of mapped side buttons.
- Choose regular `keyDown`/`keyUp` events or `flagsChanged` compatibility mode.
- Keep the app available from the menu bar after closing its settings window.
- Use the included CLI to compare single and double synthetic modifier events.

## Requirements

- macOS 13 or later
- Swift 6 toolchain (Xcode 16 or a compatible command-line toolchain)
- A mouse whose extra buttons generate standard macOS mouse-button events

The app needs two macOS permissions:

- **Input Monitoring** to receive extra mouse-button events.
- **Accessibility** to emit the configured keyboard events.

These permissions are powerful. Build from source, inspect the code, and only
grant them if you trust the executable you are running.

## Build the app

```bash
git clone https://github.com/AaronZ021/double-click-mouse.git
cd double-click-mouse
./build-app.sh
open "dist/Double Click Mouse.app"
```

The build script uses ad-hoc signing by default and never searches your
keychain. To use a specific signing identity, pass it explicitly:

```bash
SIGNING_IDENTITY="Developer ID Application: Example" ./build-app.sh
```

Move the built app to `/Applications` if you want a stable path. A rebuild with
ad-hoc signing can cause macOS to request permissions again.

## Configure

1. In the target app, assign the action you want to control to one modifier key
   or a two-modifier combination.
2. Open Double Click Mouse and grant Input Monitoring and Accessibility.
3. Bind an extra mouse button to **Shortcut**, **Return**, or **Backspace**.
4. Set the app's output shortcut to exactly match the target app.
5. Use **Test output** before enabling the mouse mapping.

The UI currently uses Simplified Chinese. Button numbers are displayed in both
Core Graphics' zero-based form and the conventional one-based form.

## CLI event experiment

The companion CLI helps determine which synthetic modifier-event shape a target
app accepts:

```bash
swift build -c release --product double-click-key-test
.build/release/double-click-key-test send --dry-run
.build/release/double-click-key-test send --mode single --style keyboard
.build/release/double-click-key-test send --mode double --style keyboard
.build/release/double-click-key-test send --mode single --style flags-changed
.build/release/double-click-key-test send --mode double --style flags-changed
```

Run with `--help` to see timing, source, and key options. Without `--dry-run`,
the CLI posts synthetic keyboard events and therefore requires Accessibility.

## Limitations

- Only standard extra-button events are supported. Vendor-specific gesture
  buttons may require an IOHID-based implementation.
- The app does not create real hardware HID reports; it posts Core Graphics
  synthetic events.
- Mapped button-down events are suppressed. The corresponding button-up event
  is allowed through so macOS does not retain a stuck mouse-button state.
- There are no prebuilt, notarized releases yet.

## Development

```bash
swift build
swift build -c release
.build/release/double-click-key-test send --dry-run
```

The project has no third-party runtime dependencies.

## Security and privacy

See [SECURITY.md](SECURITY.md) for the permission model and vulnerability
reporting guidance.

## License

MIT. See [LICENSE](LICENSE).
