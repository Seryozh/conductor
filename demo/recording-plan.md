# Demo recording plan

Record a 30–40 second screen capture with your own voice after the scratch app and both CLI brains have passed their end-to-end checks. Use only a disposable test setup. Do not show private windows, real files, messages, or account details.

## Shot list and spoken script

| Time | Screen and action | Spoken line |
| --- | --- | --- |
| 0–3 s | Show the real command bar with the mic off. Add the video title “One request. Two apps.” outside the app window. | Voiceover: “One request. Two apps.” |
| 3–12 s | Turn the mic on and speak the full command: “Calculate 18 times 27, open Notes, and write the result in a new note.” Show Calculator produce 486. | Only this quoted line goes through Jev Voice. |
| 12–22 s | Show Notes open and the new note appear with the result. Keep the actual app window visible. | “It carried the result into a new note.” |
| 22–28 s | Turn the mic on, ask Jev to place Calculator on the left and Notes on the right, then show both windows. | Say the arrangement request through Jev Voice. |
| 28–38 s | Say, “Wait 20 seconds before replying. Do not change anything.” Turn the mic off, open Settings at Full access and privacy, then click Stop while the request is still running. | Voiceover: “The CLI brain can use files, commands, and apps without a step-by-step approval in Jev Voice. macOS still asks for its permissions. I can stop a task with the button.” |

The four moments are the cross-app request, the new note, side-by-side windows, and the visible Stop button. Add the narration as a separate voiceover after the screen capture so it is not sent as another command. Keep the cursor visible when it explains what happened. Do not speed up the app response. If a task fails or the recording does not show the result, record it again instead of narrating over a miss.

The 17-app close result is an owner-reported measurement from a prior run. Use it in a separate cut only if you safely repeat and record that exact task on a disposable setup. Never close personal work apps for the demo.

## Turn your recording into the README GIF

Save the original recording as `work/jev-voice-demo.mov`. `work/` is ignored by Git. Install FFmpeg if it is not already available, then run:

```sh
mkdir -p work
ffmpeg -ss 0 -i work/jev-voice-demo.mov -t 38 \
  -vf "fps=12,scale=1200:-1:flags=lanczos,palettegen" \
  -frames:v 1 -y work/jev-palette.png
ffmpeg -ss 0 -i work/jev-voice-demo.mov -i work/jev-palette.png -t 38 \
  -filter_complex "fps=12,scale=1200:-1:flags=lanczos[frames];[frames][1:v]paletteuse=dither=sierra2_4a" \
  -loop 0 -y assets/demo.gif
```

Review the GIF at full size. Confirm the app screen is real, no private material is visible, the spoken request matches the actions, and the full result remains legible. Keep the original video out of the repository.
