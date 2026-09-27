# Checks and diagnostics

Build the app into `dist/`:

```sh
bash build.sh
```

The build is unsigned by default. The release workflow packages the app as a ZIP when a version tag is pushed.

## Local checks

The app includes these command-line checks:

- `--self-test` exercises request parsing, action catalogues, speech buffering, local Whisper formatting, and text-entry fixtures.
- `--activity-test` exercises TypeSafe API response handling with local HTTP fixtures. It does not need a real key.
- `--router-test` sends synthetic decision requests to TypeSafe and requires a key saved in macOS Keychain. It uses paid input tokens.
- `--speech-file-test` accepts a local recording for an Apple Speech transcription check. A recording is not included.

The app has not been launched from this public copy yet. The Claude Code and Codex end-to-end checks, live permissions, screenshots, and real app actions still need a separate approved run. Do not describe either brain as verified until it passes that run.

The standalone arm64 build succeeded in Swift 5 language mode with no compiler warnings on the local toolchain. This verifies compilation only, not runtime behavior. Check that `xcode-select -p` points to installed Xcode Command Line Tools before building. If another Jev Voice copy is installed, choose a distinct bundle identifier before opening this one.

## Diagnostics

Diagnostic logs are off by default. When enabled, logs are stored under the current user's Application Support folder and can include commands and screen text. Check the contents before sharing a log. Separately, the Jev activity panel keeps up to 300 TypeSafe API call records in memory while the app is open; closing the app clears that session history.

A normal voice task can change files, send messages, or control apps because the selected brain has full access. Use an isolated test environment for tasks that have external or hard-to-reverse effects. Stop a task with the Stop button or say `cancel task`.
