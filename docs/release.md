# Building and distributing

The build script creates an unsigned Apple silicon app by default:

```sh
CONDUCTOR_OUTPUT_DIR=/tmp/conductor-build bash build.sh
```

The `v*` tag workflow builds the same app on an Apple silicon macOS runner, runs the local command and API-fixture checks, verifies the ZIP, and uploads `Conductor-macos-arm64.zip` as a workflow artifact. It does not create a GitHub Release or notarize the app. Workflow artifacts need a GitHub sign-in to download and expire, so attach the ZIP to a GitHub Release for a public download.

## Notarization

A public app download can be signed with a Developer ID certificate and submitted to Apple's notarization service. Apple Developer Program membership is currently $99 USD per year. The account supplies the Developer ID certificate and notarization credentials. [Apple enrollment](https://developer.apple.com/programs/enroll/) · [Notarization overview](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

The current workflow produces an unsigned ZIP, so macOS warns when a downloaded copy is opened. Building from source avoids the warning.
