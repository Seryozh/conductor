# Automatic repair reports

Conductor records the original command and actual failure in its local diagnostic journal. The optional repair outbox turns new failures into durable incidents. It does not send credentials, use a paid API, click through agent chats or infer that an observation failure means missing Mac access.

Configure scripts/repair_queue.py once with init, an existing owner task, an existing coordinator task and an activation timestamp. Its defaults are the public app's local Logs and RepairQueue folders under the user's Library/Application Support. Personal task IDs live only in the local config. Diagnostic history must be enabled explicitly.

An authorized local Codex heartbeat can run sync every five minutes. For each queued incident it sends one report through the task connector. The report includes the original request, model, outcome, tool actions, error and source evidence. The responsible agent explicitly acknowledges the incident ID. Connector acceptance alone does not prove receipt.

Statuses distinguish queued, dispatching, dispatched, received, repairing, awaiting_verification, waiting_user, delivery_uncertain and closed. If delivery is uncertain, look for the same incident's acknowledgement before any resend. Related problem records are attached to one incident; log rotation and restarts do not reopen a closed incident.

Repair one concrete defect, then verify the original scenario on an owned safe surface. A repairer's claim or green build alone does not close the incident. Record the test/result evidence with mark. Do not repeatedly retry a command whose earlier effects are unknown. Screen tests share the user's desktop and voice queue, so coordinate them first.

Explicit macOS permission failures wait for the user. Tool, observation and reasoning failures go to the repair agent. Ambiguous errors remain unknown until evidence establishes a cause. Passwords, subscription limits, spending, publication and irreversible actions remain user decisions. Account limits must not trigger paid fallback.

The heartbeat stays quiet when there are no new failures or meaningful changes. Existing open incidents retain their owner and progress; they do not trigger another general audit. Delivery runs while the local Codex scheduler can execute, with up to the configured five-minute polling delay. Commands lost before reaching diagnostic history cannot be reconstructed by this outbox.

Offline checks: python3 scripts/test_repair_queue.py.
