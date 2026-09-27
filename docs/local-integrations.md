# Optional local integrations

Conductor works without these integrations. Configure them only if you already have local tools you want the app to use.

## Instructions

Settings → Advanced has an optional instructions file path. Its UTF-8 contents are appended to the selected brain's context. The file stays on your Mac, but its contents go to the Claude or Codex provider when the brain receives them. Leave the field blank to omit it.

## Commands and dashboard

The public app reads optional command arrays from its own macOS preferences domain, `ai.conductor.public`. Each array starts with an executable path, followed by its arguments. The app starts that executable directly, without a shell. A leading `~` in the executable path expands to the current user's home folder.

| Preference | Used for | Expected result |
| --- | --- | --- |
| `agentStatusCommand` | Refresh local agent status at startup and every five minutes | JSON with `ok` and `summary`, or `summary_en` and `summary_ru`; optional `problems` array |
| `agentDashboardCommand` | Refresh a configured dashboard before opening it | Exit status 0 |
| `agentDashboardPath` | Open the local dashboard | A readable HTML file path |
| `agentErrorCaptureCommand` | Record a requested agent correction | Exit status 0; receives `--error`, `--correction`, `--heard` and optional session/agent text |
| `usageSummaryCommand` | Estimate Claude's share of its five-hour usage window | JSON with nonnegative `total_usd` and `conductor_usd`; receives the window's start as a Unix timestamp |

No dashboard, status command, error recorder or usage reader is included or enabled by default. These executables have the user's normal Mac privileges. An error recorder may receive command text and corrections, so choose a tool whose handling of that text you understand.

The usage estimate applies only to Claude. It is based on local session costs and can miss activity on other devices. Codex's reported usage and context remain separate; the app does not convert them into an estimated Claude limit share.

## Diagnostics

Settings → Advanced can enable diagnostic logs. They are off by default. Logs and replay reports go under the app's Application Support directory, with owner-only file permissions. Common key and token formats are redacted, but commands and screen text can still contain private information. Review files before sharing them.

The Jev activity panel is separate. It keeps the current session's API call records in memory, up to 300 entries, and clears them when the app closes.
