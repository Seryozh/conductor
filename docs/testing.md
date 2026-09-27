# Checks and diagnostics

Build the app into `dist/`:

```sh
bash build.sh
```

The build is unsigned by default. The release workflow packages the app as a ZIP when a version tag is pushed.

## Latest verification

On 2026-09-27, the current public source compiled in Swift 5 language mode for arm64 to `/tmp/conductor-public-verify-Gb7WeP/Conductor.app`. The scratch build used bundle ID `ai.conductor.public.preview`; the GUI was not opened. The executable is arm64, the packaged icon matches `AppIcon.icns`, and `Info.plist` plus the English and Russian string tables pass `plutil` checks.

The native UI integration task reports passing input-field and queue checks, screen-state fixtures, geometry checks, and an independent design review. Its full `--self-test` run still fails at `Sources/SelfTests.swift:65`: the current completion detector treats ordinary words such as “opened” in “You opened Calculator at 8:44” and “closing” in explanatory prose as completion claims. This is a runtime detection issue, not a UI fixture failure, and remains open.

The GUI app has not been opened from this public copy. Claude Code and Codex have not been checked end to end here. TypeSafe live requests, Whisper server behavior, macOS permission prompts, real app actions, and real screenshots remain unverified. Do not describe either brain as verified until it passes a separately approved run.

## Available checks

- `--self-test` exercises request parsing, action catalogues, speech buffering, local Whisper formatting, and text-entry fixtures. It currently fails on the completion-detection cases above.
- `--activity-test` exercises TypeSafe API response handling with local HTTP fixtures. It does not need a real key.
- `--router-test` sends synthetic decision requests to TypeSafe and requires a key saved in macOS Keychain. It uses paid input tokens.
- `--speech-file-test` accepts a local recording for an Apple Speech transcription check. A recording is not included.

Check that `xcode-select -p` points to installed Xcode Command Line Tools before building. Use a bundle identifier distinct from any other Conductor copy before opening this one.

## Diagnostics

Diagnostic logs are off by default. When enabled, logs are stored under the current user's Application Support folder and can include commands and screen text. Check the contents before sharing a log. Separately, the Jev activity panel keeps up to 300 TypeSafe API call records in memory while the app is open; closing the app clears that session history.

A normal voice task can change files, send messages, or control apps because the selected brain has full access. Use an isolated test environment for tasks that have external or hard-to-reverse effects. Stop a task with the Stop button or say `cancel task`.
