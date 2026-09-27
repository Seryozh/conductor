# Checks and diagnostics

Build the app into `dist/`:

```sh
bash build.sh
```

The build is unsigned by default. The release workflow packages the app as a ZIP when a version tag is pushed.

## Latest verification

On 2026-09-27, the integrated public source and motion resources compiled in Swift 5 language mode for arm64 from a fixed snapshot. All twelve `--self-test` groups passed, including completion detection, restored providers, command journaling, localized app aliases, speech buffering, Whisper formatting, and continuous listening. The earlier two fixture failures are resolved in this tested build. The installed app has the public `ai.conductor.public` identity. Its local signature passed strict verification; this is not Apple notarization or a distributable Developer ID signature.

The UI was checked using native screen-state renders, window geometry tests, and an isolated playback fixture. Seven state loops, static posters, rapid transitions, a maximum of two overlapping players, Reduce Motion behavior, hide/show cleanup, and missing/malformed media fallback were checked. The final independent visual review requested answer-layout corrections; those corrections were applied and personally inspected in native renders, without another independent review. Fixture images contain sample data, not completed real requests.

The installed public build completed a live Codex task on 2026-09-27: it opened Calculator and entered `(6 + 7) × 5`. An independent app-scoped screenshot showed `13×5` and `65`, and the command receipt was `done`. The final command panel identified GPT-6 Astra. This check started through local command control, so it does not establish voice capture. A TypeSafe connection check also returned a real ready decision.

Claude's live check is waiting for the account's weekly limit to reset. Runtime status reports Whisper configured, but this does not prove that its server transcribed a recording. Real Fn dictation, recording replay, desktop session-message flows, focus handoff, pointer passthrough and Spaces remain unchecked. The hosted release workflow has not run.

## Available checks

- `--self-test` exercises request parsing, completion checks, restored providers and models, command journaling, action catalogues, speech buffering, local Whisper formatting, continuous listening, and text-entry fixtures. All twelve groups passed on the installed integrated public build.
- `--activity-test` exercises TypeSafe API response handling with local HTTP fixtures. It does not need a real key.
- `--whisper-test file.wav` starts the configured local Whisper server, waits for its own listener, transcribes a 16 kHz mono 16-bit WAV, and stops that server. It requires Whisper to be enabled in Settings and has not been run on this build.
- `--router-test` sends synthetic decision requests to TypeSafe and requires a key saved in macOS Keychain. It uses paid input tokens.
- `--speech-file-test` accepts a local recording for an Apple Speech transcription check. A recording is not included.

Check that `xcode-select -p` points to installed Xcode Command Line Tools before building. Use a distinct bundle identifier for a separate preview, and keep only one live microphone listener running.

## Diagnostics

Diagnostic logs are off by default. When enabled, logs are stored under the current user's Application Support folder with owner-only permissions. Common key and token formats are redacted; commands and screen text can still contain private information. Check the contents before sharing a log. Separately, the Jev activity panel keeps up to 300 Jev API call records in memory while the app is open; closing the app clears that session history.

A normal voice task can change files, send messages, or control apps because the selected brain has full access. Use an isolated test environment for tasks that have external or hard-to-reverse effects. Stop a task with the Stop button or say `cancel task`.
