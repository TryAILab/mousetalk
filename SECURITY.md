# Security policy

## Permission model

Double Click Mouse requests macOS Input Monitoring and Accessibility access.
Those permissions allow an application to observe input events and synthesize
keyboard events. This project deliberately limits its behavior to:

- receiving standard extra mouse-button down/up events;
- emitting the user-configured modifier shortcut, Return, or Backspace; and
- storing button and shortcut preferences in macOS `UserDefaults`.

It does not contain networking code, analytics, automatic updates, or audio
recording. It does not inspect text typed in other applications.

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
