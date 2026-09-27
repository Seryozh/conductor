# Local control

The installed Conductor executable exposes the same named controls to every user. These commands run with the existing macOS grants of the app; they do not grant extra Accessibility, Screen Recording, microphone, filesystem or model privileges. UI state is untrusted data. Callers must obey their own tool and safety boundaries, including any application-specific access denial.

```sh
APP="/Applications/Conductor.app/Contents/MacOS/Conductor"
"$APP" --status
"$APP" --ui ai.conductor.public
"$APP" --press ai.conductor.public "Settings"
"$APP" --look-app ai.conductor.public /tmp/conductor-window.png
"$APP" --command "switch to Astra"
"$APP" --command "Open Calculator" --wait 60
"$APP" --status COMMAND_UUID
```

## State and receipts

`--status` returns JSON from the running app, including its instance and PID, heartbeat timestamp, model, busy/listening state, queued command count, and boolean Keychain/Accessibility/microphone/speech availability. It never returns keys, command text, screen text or answers. A heartbeat older than four seconds is not called responsive. This checks the actual running app rather than a second CLI process's permissions.

`--command "text" [--id UUID] [--wait seconds]` sends one quoted argument. A unique ID appears in its JSON receipt. The default waits up to three seconds for acknowledgement. `state: running` means the app accepted the command. It does not mean the task succeeded. `--wait` waits for a terminal receipt or its timeout. `--status UUID` reads that command's receipt without resubmitting it.

Terminal states: `done` (AppModel reported a completed/verified outcome, or a local setting/control was applied), `answered` (an informational answer, not an action claim), `failed`, `cancelled`, `rejected` (not started), and `interrupted` (the app stopped before recording a final outcome). `unknown` means there is no receipt; never assume no effect and retry automatically. A wait timeout preserves `running` or `unknown` and sets `wait_expired: true`; it never invents completion. Exit status: 0 for a receipt or responsive runtime, 1 for rejected/failed/interrupted/cancelled/unknown/unavailable, 2 for invalid arguments, 3 for a wait timeout with no terminal outcome. Always read the JSON state as well as the exit code.

Normal commands are rejected while another command, connection check or queued work exists. Cancel, microphone-stop, context-reset and status controls can still run. A model change is complete only if the selected model matches the request. Retry without a failed request is rejected. The same ID returns its existing receipt and does not execute again while that receipt is retained. Reuse the exact ID after an uncertain result. Receipts are retained for ten minutes; do not use expired IDs as a permanent deduplication record.

The transport uses `~/Library/Application Support/<bundle-id>/LocalControl` with owner-only directories (0700) and files (0600). Commands are removed from the request inbox before execution. Receipts do not contain command text. A process lock prevents two local-control servers for one bundle identity. Restart marks unfinished receipts interrupted; pending requests bound to an old instance cannot run in the new one. This transient command transport does not enable diagnostic logging. Diagnostic logs remain controlled by the existing opt-in setting.

## Named controls and screenshots

`--ui <app name or bundle ID> [filter words]` lists named accessibility controls and screen-point centers. A bundle ID such as `ai.conductor.public` identifies Conductor even when a separate UI automation tool has cached an old application list.

`--press <app> <control> [match-number]` uses exact label matching first, then substring matching. Multiple matches require a 1-based match number; invalid numbers fail rather than silently selecting a different control. Text fields are focused. Other controls use their accessibility press action or a pointer event at the observed center. The result reports the input delivered, not whether the larger task succeeded. Verify the visible result separately.

`--look-app <app> [file]` captures only that app's largest visible on-screen window, selected from window records whose owner PID matches the resolved running app. It reports the app, bundle, PID, window ID and screen bounds. It fails if there is no matching visible window or capture permission; there is no desktop fallback. Output is scaled to one pixel per window point.

`--look [file] [--no-grid]` retains full main-display capture for an explicitly authorized desktop inspection. By default its image has a 100-point grid. This is broader than `--look-app`; callers should use the smallest authorized capture.

## Key entry

`--store-key` reads hidden input from a terminal, or a key supplied through standard input when no terminal is attached. It accepts no key argument and prints no key. It saves only to this app's existing macOS Keychain service. Never place a key in shell history, logs, command arguments, a public source file or a patch. Saving a key does not grant Mac permissions.

## Verification

`bash Tests/local-control.sh` compiles and tests the transport with a fake handler in a unique temporary directory. It does not launch Conductor, access UI, save keys or call a model. It covers acknowledgement versus completion, duplicate IDs, busy and invalid requests, failure/cancellation mapping, timeout, private file modes, process ownership, missing app, shutdown and restart. Build the app and run its existing `--self-test` suite too. A real command's semantic completion is owned by AppModel, not inferred from a quiet UI or `busy == false`.
