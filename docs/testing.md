# Checks and diagnostics

Build the app into `dist/`:

```sh
bash build.sh
```

The build is unsigned by default. The release workflow packages the app as a ZIP when a version tag is pushed.

## Latest verification

On 2026-09-27, the public source compiled in Swift 5 language mode for arm64 to `/tmp/conductor-public-audit-CSyQjz/Conductor.app`. The scratch build used bundle ID `ai.conductor.public.preview`; the GUI was not opened. The executable is arm64, and the English and Russian string tables pass `plutil` checks.

The native UI integration task reports passing input-field and queue checks, screen-state fixtures, geometry checks, and an independent design review. Earlier `--self-test` runs found two failures: the completion detector treated explanatory text as an action claim, then a fixture checked Russian app aliases while English was selected. The source and fixture were revised and compile, but `--self-test` has not been rerun on the new build. Treat the workflow test gate as unverified until that run is approved.

The GUI app has not been opened from this public copy. Claude Code and Codex have not been checked end to end here. TypeSafe live requests, Whisper server behavior, macOS permission prompts, real app actions, and real screenshots remain unverified. Do not describe either brain as verified until it passes a separately approved run.

## Available checks

- `--self-test` exercises request parsing, action catalogues, speech buffering, local Whisper formatting, and text-entry fixtures. Its previous failures were revised in source but not rerun on the current build.
- `--activity-test` exercises TypeSafe API response handling with local HTTP fixtures. It does not need a real key.
- `--whisper-test file.wav` starts the configured local Whisper server, waits for its own listener, transcribes a 16 kHz mono 16-bit WAV, and stops that server. It requires Whisper to be enabled in Settings and has not been run on this build.
- `--router-test` sends synthetic decision requests to TypeSafe and requires a key saved in macOS Keychain. It uses paid input tokens.
- `--speech-file-test` accepts a local recording for an Apple Speech transcription check. A recording is not included.

Check that `xcode-select -p` points to installed Xcode Command Line Tools before building. Use a bundle identifier distinct from any other Conductor copy before opening this one.

## Diagnostics

Diagnostic logs are off by default. When enabled, logs are stored under the current user's Application Support folder and can include commands and screen text. Check the contents before sharing a log. Separately, the Jev activity panel keeps up to 300 TypeSafe API call records in memory while the app is open; closing the app clears that session history.

A normal voice task can change files, send messages, or control apps because the selected brain has full access. Use an isolated test environment for tasks that have external or hard-to-reverse effects. Stop a task with the Stop button or say `cancel task`.
