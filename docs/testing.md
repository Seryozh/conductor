# Checks and diagnostics

Build the app into `dist/`:

```sh
bash build.sh
```

The build is unsigned by default. The release workflow packages the app as a ZIP when a version tag is pushed.

## Available checks

- `--self-test` exercises request parsing, completion checks, restored providers and models, command journaling, action catalogues, speech buffering, local Whisper formatting, continuous listening, and text-entry fixtures.
- `--activity-test` exercises TypeSafe API response handling with local HTTP fixtures. It does not need a real key.
- `--whisper-test file.wav` starts the configured local Whisper server, waits for its own listener, transcribes a 16 kHz mono 16-bit WAV, and stops that server. It requires Whisper to be enabled in Settings.
- `--router-test` sends synthetic decision requests to TypeSafe and requires a saved Jev key. It uses paid input tokens.
- `--speech-file-test` accepts a local recording for an Apple Speech transcription check. A recording is not included.
- `--brain-runtime-test` runs local model-process fixtures for timeouts, Stop and the Codex usage reader. No model is called.
- `--speech-runtime-test file` replays a recording in real time through the live speech pipeline and expects one complete submission; `--release-during-rotation` releases the key while a recognition request is rotating. It must run as the signed app (`open -n -W --stdout out.txt --stderr log.txt Conductor.app --args ...`) so Speech Recognition permission applies. A recording is not included.
- `--render-ui-fixtures folder` renders sample command-panel states to PNG files and checks their sizes.
- `--codex-limits` prints the signed-in Codex subscription's remaining usage without a model request.
- `--render-ui-gallery folder [--language ru]` renders every command-panel, settings, practice and menu state with sample data to numbered PNG files and `gallery.json`; run it as the signed app. `python3 scripts/ui_gallery_grid.py folder out` composes them into contact sheets, and `python3 scripts/readme_flow.py folder` rebuilds the README's `assets/flow.png` from the gallery's README group (both need Pillow).

Check that `xcode-select -p` points to installed Xcode Command Line Tools before building. Use a distinct bundle identifier for a separate preview, and keep only one live microphone listener running.

## Diagnostics

Diagnostic logs are off by default. When enabled, logs are stored under the current user's Application Support folder with owner-only permissions. Common key and token formats are redacted; commands and screen text can still contain private information. Check the contents before sharing a log. Separately, the Jev activity panel keeps up to 300 Jev API call records in memory while the app is open; closing the app clears that session history.

A normal voice task can change files, send messages, or control apps because the selected brain has full access. Stop a task with the Stop button or say `cancel task`.
