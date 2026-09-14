# Security policy

## Permission model

鼠语 MouseTalk requests macOS Input Monitoring and Accessibility access.
Those permissions allow an application to observe input events and synthesize
keyboard events. This project deliberately limits its behavior to:

- receiving standard extra mouse-button down/up events;
- emitting the user-configured modifier shortcut, Return, or Backspace; and
- storing button and shortcut preferences in macOS `UserDefaults`;
- reading enabled system shortcut metadata and public menu shortcuts from running
  apps through Accessibility, without activating menus or commands; and
- reading `NSUserKeyEquivalents` and the selected Karabiner profile for possible
  overlap with the configured bindings. Proprietary driver preferences are not
  reverse-engineered, edited or exported.

It does not contain networking code, analytics, automatic updates, or audio
recording. It does not inspect text typed in other applications.
The scan can read menu labels (including app-provided document names) while
traversing public menus, but only matching shortcut descriptions are retained
in memory. It does not read text fields, window contents or clipboard contents.
GUI scan results are not persisted or transmitted. The diagnostic CLI prints
its report to the caller and should not be shared without reviewing it.

## Safer use

- Build from a reviewed source revision.
- Keep the application at a stable path after granting permissions.
- Remove its Input Monitoring and Accessibility permissions when no longer in
  use.
- Treat third-party binaries claiming to be this project as untrusted unless
  their provenance is independently verified.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for the repository.
Do not include passwords, access tokens, or unrelated personal data in a report.
