# Demo recording plan

Record a 30–40 second screen capture with your own voice after the scratch app and both CLI brains have passed their end-to-end checks. Use only a disposable test setup. Do not show private windows, real files, messages, or account details.

## Shot list and spoken script

| Time | Screen and action | Spoken line |
| --- | --- | --- |
| 0–3 s | Show the real command bar, turn the mic on, and begin the request. Do not add title text over the app. | Begin: “Calculate 18 times 27, open Notes, and write the result in a new note.” |
| 3–12 s | Finish the request and show Calculator produce 486. | Continue the same spoken request through the app. |
| 12–22 s | Show Notes open and the new note appear with the result. Keep the actual app window visible. | Voiceover: “The answer is in Notes, and Calculator is still open.” |
| 22–28 s | Turn the mic on, ask Conductor to place Calculator on the left and Notes on the right, then show both windows. | Say the arrangement request through Conductor. |
| 28–38 s | Say, “Wait 20 seconds before replying. Do not change anything.” Turn the mic off, open Settings at Full access and privacy, then click Stop while the request is still running. | Voiceover: “The CLI can run commands, use apps, and read or change files available to this account. I can stop it here, and macOS privacy permissions still apply.” |

The four moments are the cross-app request, the new note, side-by-side windows, and the visible Stop button. Add the narration as a separate voiceover after the screen capture so it is not sent as another command. Keep the cursor visible when it explains what happened. Do not speed up the app response. If a task fails or the recording does not show the result, record it again instead of narrating over a miss.

The 17-app close result is an owner-reported measurement from a prior run. Use it in a separate cut only if you safely repeat and record that exact task on a disposable setup. Never close personal work apps for the demo.

## Turn your recording into the README GIF

Save the original recording as `work/conductor-demo.mov`. `work/` is ignored by Git. Install FFmpeg if it is not already available, then run this from the repository folder:

```sh
bash demo/make-gif.sh work/conductor-demo.mov
```

The script creates `assets/demo.gif` and adds it to the README. Review the GIF at full size before committing it. Confirm the app screen is real, no private material is visible, the spoken request matches the actions, and the full result remains legible. Keep the original video out of the repository.
