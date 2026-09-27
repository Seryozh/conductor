# Checks and diagnostics

Build the app into `dist/`:

```sh
bash build.sh
```

The build is unsigned by default. The release workflow packages the app as a ZIP when a version tag is pushed.

## Latest verification

On 2026-09-27, the integrated public source and motion resources compiled in Swift 5 language mode for arm64 from a fixed snapshot. All twelve `--self-test` groups passed, including completion detection, restored providers, command journaling, localized app aliases, speech buffering, Whisper formatting, and continuous listening. The earlier two fixture failures are resolved in this tested build. The installed app has the public `ai.conductor.public` identity. Its local signature passed strict verification; this is not Apple notarization or a distributable Developer ID signature.

The UI was checked using native screen-state renders, window geometry tests, and an isolated playback fixture. Seven state loops, static posters, rapid transitions, a maximum of two overlapping players, Reduce Motion behavior, hide/show cleanup, and missing/malformed media fallback were checked. The final independent visual review requested answer-layout corrections; those corrections were applied and personally inspected in native renders, without another independent review. Fixture images contain sample data, not completed real requests.

The setup task is checking the installed app separately. This validation does not establish end-to-end Claude Code or Codex behavior, TypeSafe live requests, the Whisper server, real Fn dictation, focus handoff, pointer passthrough or Spaces. Do not describe those paths as verified based on fixture results. The hosted release workflow has not run.

## Available checks

- `--self-test` exercises request parsing, completion checks, restored providers and models, command journaling, action catalogues, speech buffering, local Whisper formatting, continuous listening, and text-entry fixtures. All twelve groups passed on the installed integrated public build.
- `--activity-test` exercises TypeSafe API response handling with local HTTP fixtures. It does not need a real key.
- `--whisper-test file.wav` starts the configured local Whisper server, waits for its own listener, transcribes a 16 kHz mono 16-bit WAV, and stops that server. It requires Whisper to be enabled in Settings and has not been run on this build.
- `--router-test` sends synthetic decision requests to TypeSafe and requires a key saved in macOS Keychain. It uses paid input tokens.
- `--speech-file-test` accepts a local recording for an Apple Speech transcription check. A recording is not included.

Check that `xcode-select -p` points to installed Xcode Command Line Tools before building. Use a distinct bundle identifier for a separate preview, and keep only one live microphone listener running.

## Diagnostics

Diagnostic logs are off by default. When enabled, logs are stored under the current user's Application Support folder and can include commands and screen text. Check the contents before sharing a log. Separately, the Jev activity panel keeps up to 300 TypeSafe API call records in memory while the app is open; closing the app clears that session history.

A normal voice task can change files, send messages, or control apps because the selected brain has full access. Use an isolated test environment for tasks that have external or hard-to-reverse effects. Stop a task with the Stop button or say `cancel task`.
