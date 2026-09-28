# Contributing

Thanks for looking at Conductor.

## Build locally

Install Xcode Command Line Tools, then run:

```sh
bash build.sh
'dist/Conductor.app/Contents/MacOS/Conductor' --self-test
'dist/Conductor.app/Contents/MacOS/Conductor' --activity-test
```

The two local checks use synthetic state and HTTP fixtures. The router check makes paid TypeSafe API calls. The speech-file check uses a local recording you provide and requests Speech Recognition access. See [checks and diagnostics](docs/testing.md) before running these checks.

## Changes

Keep UI actions grounded in the current Accessibility tree and verify them against fresh state. Avoid adding app-specific command recipes or silently reporting completion after an attempted action.

Report what you checked, including whether you used fixtures, a recording, a physical microphone, or a live app. Never include API keys, private recordings, or unredacted screen text in an issue or patch.
