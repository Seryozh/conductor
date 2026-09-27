# How Conductor works

Conductor separates reasoning, action selection, and macOS input.

## Request and reasoning

Apple Speech handles live transcription. Conductor requests on-device recognition when macOS supports it for the selected language; otherwise Apple Speech may use its network service. An optional local Whisper server can make a final pass on recorded audio. Text typed into the command bar follows the same task path.

The selected Claude Code or Codex CLI receives the request, current app context, screen text, open windows, prior action results, and a screenshot when the brain asks for one. The CLI runs with its built-in approval and sandbox checks bypassed. It can use its own shell and file tools while it reasons.

## Choosing visible UI actions

The brain can ask the Swift controller directly to open or close apps, arrange windows, open desktop sessions, or press an exact named control. Those operations do not require Jev to choose a control.

When the brain asks Jev to choose a visible action, the controller reads the current Accessibility tree and builds an action catalogue from controls, menus, installed apps, physical keys, and pointer operations. It sends the text request, screen text, catalogue, and action history through TypeSafe or OpenRouter. The provider is detected from the saved key. Jev returns one choice. The API receives text, not the original audio or a screenshot.

Large catalogues are grouped so each discovered action can be reached within the provider's choice limit. Group selection does not itself operate the Mac.

## Acting and checking

The controller carries out the chosen action through macOS Accessibility APIs, Apple Events, keyboard events, or pointer events. It reads the resulting state and continues the loop. The brain receives fresh context on the next turn. A completion choice is accepted only after the current state and history are checked against the original request.

The brain can also act directly through its own CLI tools. The Jev action catalogue covers visible UI operations. It does not restrict what the unrestricted CLI can do through shell commands or files.

## Access and privacy

The CLI is launched with per-action approval and sandbox checks disabled. Conductor does not ask you to approve each step. macOS permissions still apply, including Microphone, Speech Recognition, Accessibility, Screen Recording, and Automation.

Whisper audio stays on the Mac. Apple Speech may use Apple’s network service when on-device recognition is unavailable. The selected CLI provider receives the request, screen text, and screenshots when needed. The selected Jev provider receives the request and text context used to choose a UI action, not audio or screenshots. With OpenRouter selected, that service forwards the request to TypeSafe. The provider key is stored in macOS Keychain. Diagnostic logging is opt-in and may contain screen text and commands.

The Jev activity panel holds up to 300 API call records in memory for the current app session. Records can contain the request, screen text, action choices, and API response. They are not written to disk and disappear when the app closes. Opt-in diagnostic logs are separate files under macOS Application Support.

The full-access behavior is described in the [README](../README.md#full-access). The editable source is based on [Jev Voice by TypeSafe](https://github.com/ronadin2002/jev-cua).
