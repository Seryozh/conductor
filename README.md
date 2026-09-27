# Jev Voice, public edition draft

Speak. It acts.

A full-access voice interface for macOS, powered by your Claude Code or Codex login.

![Jev Voice launch artwork, not a screenshot of the app](assets/social-preview.png)

[Architecture](#how-it-works) · [Quick start](#quick-start) · [Full access](#full-access) · [Cost](#what-costs-money)

## Demo

The real screen recording is still pending. The image above is launch artwork, not a screenshot. The recording plan is in [demo/recording-plan.md](demo/recording-plan.md).

## What makes it different

Siri is useful for its built-in requests and app shortcuts. macOS Dictation enters text where you can type. Jev Voice takes a spoken or typed request into a task loop: a reasoning brain can use its CLI tools, Jev can choose among actions found on the current screen, and the Mac controller checks the result. [Apple's Siri guide](https://support.apple.com/guide/mac-pro/siri-apdf7bb2fad4/mac) and [Dictation guide](https://support.apple.com/en-au/guide/mac-help/mh40584/26/mac/26) describe those built-in roles.

There is no honest head-to-head benchmark against Siri, dictation apps, or other computer-use agents yet. The figures below come from the owner’s runs of this build, so treat them as examples rather than a broad benchmark:

- One spoken request closed 17 apps in 12.6 seconds.
- Claude Opus 5.5 answered in about 2.5 seconds.
- Across 38 recordings, local Whisper had 11.5% word error, compared with 16.4% for Apple Speech.

The Claude Code and Codex backends are in this source copy. Their end-to-end checks are still open, so this draft makes no reliability claim for either backend yet.

## Quick start

Jev Voice is an Apple silicon app for macOS 14 or later. Building from source needs Apple's Xcode Command Line Tools. Choose either Claude Code or Codex as the reasoning brain. Jev Voice also needs a TypeSafe API key for its action picker.

### 1. Install and sign in to a CLI brain

Choose at least one:

**Claude Code**

```sh
curl -fsSL https://claude.ai/install.sh | bash
claude
```

Follow the browser sign-in. Claude Code requires a supported Claude account, such as Pro, Max, Team, or Enterprise. The free Claude plan does not include Claude Code access. [Claude Code setup](https://code.claude.com/docs/en/getting-started#authenticate)

**Codex CLI**

```sh
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex
```

Choose **Sign in with ChatGPT** when prompted. Check OpenAI’s [Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli) for current plan availability and limits.

### 2. Get a TypeSafe API key

Create a key from the [TypeSafe dashboard](https://console.typesafe.ai). The app stores it in macOS Keychain when you enter it in **Settings → Jev action selector**. It does not read keys from `.env` files or shell variables. TypeSafe’s current Jev price is **$0.042 per million input tokens; output tokens are free**. [TypeSafe quick start](https://docs.typesafe.ai/introduction/quickstart) · [model pricing](https://docs.typesafe.ai/models)

### 3. Build and open the app

After the public repository is created, clone it and build:

```sh
git clone https://github.com/OWNER/REPOSITORY.git
cd REPOSITORY
xcode-select --install
bash build.sh
open 'dist/Jev Voice.app'
```

Replace `OWNER/REPOSITORY` with the public repository path. The build uses Apple frameworks and Swift, with no package manager or third-party Swift dependencies. It creates an unsigned app by default.

In **Settings**, choose Claude Code or Codex, add the TypeSafe key, and set any CLI path that Jev Voice did not find. Settings stores paths on this Mac. The app starts with Apple Speech. You can leave Whisper off.

### 4. Optional local Whisper

Install [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and download a compatible GGML model. In **Settings → CLI and local speech paths**, enter the path to `whisper-server` and the model file, then turn on **Use local Whisper for final transcription**. Whisper runs on this Mac; Apple Speech remains the fallback.

### 5. Grant macOS permissions

Use the permission buttons in **Settings → macOS permissions** for Microphone and Speech Recognition, Accessibility, and Screen Recording. macOS can also ask for Automation access the first time Jev Voice controls an app. These system prompts still apply.

## How it works

![Architecture diagram showing on-device speech, a Claude Code or Codex CLI brain, TypeSafe Jev action selection, and the macOS controller](assets/architecture.svg)

Voice is transcribed on the Mac. The selected CLI brain receives the request, screen text, and screenshots when a task needs one. It can also use its own tools for files, shell commands, and web work. Jev receives the request, screen text, action choices, and history as text, then selects one available UI action. The Swift controller performs that action and observes the result before the loop continues.

TypeSafe receives text, not audio or screenshots. Its API key is separate from the Claude Code or Codex login. [Read the architecture notes](docs/architecture.md).

## Full access

The selected Claude Code or Codex CLI runs with its approval and sandbox checks bypassed. It can run commands, read and write files, use AppleScript and JXA, control apps, and use keyboard and pointer actions without a separate approval for each step in Jev Voice. A request can reach any file or app available to the signed-in macOS account.

Stop a running task with the **Stop** button or say **“cancel task.”** macOS privacy permissions still apply. Jev Voice cannot bypass the operating system’s Microphone, Speech Recognition, Accessibility, Screen Recording, or Automation grants.

This is a powerful setup. The CLI brain may read local files or other app data while carrying out a request. Secure Accessibility fields are excluded from Jev's captured screen state, but the CLI can still reach data through its own tools. Diagnostic logs are off by default. If enabled, they can include commands and screen text.

The **Jev activity** panel keeps up to 300 TypeSafe API call records in memory while the app is open. These can include the request, screen text, available actions, and API response. Closing the app clears that history. Jev Voice does not save those records to disk. Opt-in diagnostic logs are separate and are written under macOS Application Support.

## What costs money

Jev Voice needs a TypeSafe API key. TypeSafe currently charges $0.042 per million input tokens for Jev, with no output-token charge. The amount for a task depends on how much text the action loop sends. Check the [current TypeSafe model page](https://docs.typesafe.ai/models) before use.

The reasoning brain uses the account already signed in to Claude Code or Codex. Those accounts have their own plan limits and terms. Optional local Whisper uses your Mac’s compute and does not use a Whisper API key.

The downloadable workflow artifact is unsigned. Notarization needs an Apple Developer Program membership, currently $99 USD per year, and a Developer ID certificate. That membership is optional for building locally. The owner has not decided whether to pay for it. [Apple Developer Program](https://developer.apple.com/programs/enroll/) · [Notarization overview](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## FAQ

**Does Jev Voice ask before each action?**

No. The CLI brain runs with its per-action approval and sandbox checks bypassed. macOS’s privacy grants still apply.

**How do I stop it?**

Click **Stop** or say **“cancel task.”**

**Does speech go to TypeSafe?**

Speech is transcribed locally. TypeSafe receives text state for action selection, including the request, screen text, available actions, and history. It does not receive the audio or screenshots.

**Do I need Whisper?**

No. Apple Speech is the default. Whisper is optional and runs locally.

**Does it work with my Claude or ChatGPT subscription?**

The app launches Claude Code or Codex CLI and uses the account already signed in there. The end-to-end checks for both backends remain open in this draft. Plan eligibility and limits can change, so check the provider’s current CLI documentation.

**Can I redistribute this source?**

Not yet. The upstream base repository has no license file, and this copy does not add one. Written permission and license terms are still needed before anyone publishes or redistributes this edition. See [credits and licensing](docs/credits-and-license.md).

## Credit and release status

This edition is based on [Jev Voice by TypeSafe](https://github.com/ronadin2002/jev-cua). The original project and its authors remain credited as the base.

The GitHub Actions workflow builds an unsigned Apple silicon `.zip` on a `v*` tag and uploads it to the workflow run. It does not create a GitHub Release. The repository, public name, license, and notarization decision are still pending.
