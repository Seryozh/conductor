# Building and distributing

The build script creates an unsigned Apple silicon app by default:

```sh
JEV_OUTPUT_DIR=/tmp/jev-voice-build bash build.sh
```

The `v*` tag workflow builds the same app on an Apple silicon macOS runner and uploads `Jev Voice-macos-arm64.zip` as a workflow artifact. It does not create a GitHub Release, publish a repository, or notarize the app.

## Notarization

A public app download can be signed with a Developer ID certificate and submitted to Apple's notarization service. Apple Developer Program membership is currently $99 USD per year. The account supplies the Developer ID certificate and notarization credentials. Whether to pay for this membership is a release decision. [Apple enrollment](https://developer.apple.com/programs/enroll/) · [Notarization overview](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

The current workflow produces an unsigned ZIP. Users may see a macOS warning when they open it. A signed and notarized release needs a separate workflow update and an Apple Developer account decision.
