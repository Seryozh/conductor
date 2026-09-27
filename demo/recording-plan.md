# Demo recording plan

Record a 30–40 second screen capture with your own voice after both CLI brains have passed their end-to-end checks in the public app. Open throwaway apps for the first command, and keep private windows, files, messages, and account details off screen.

## Shot list and spoken script

| Time | Screen and action | Spoken line |
| --- | --- | --- |
| 0–3 s | Open on the real moment several throwaway app windows disappear. Use a clip from the first command's actual recording if the command takes longer than three seconds to start working. Keep Conductor visible. | “I asked it to clear the apps I opened for this demo.” |
| 3–13 s | Show the spoken request and the remaining apps closing. Keep the actual response at normal speed. | “Close these test apps, but leave Conductor and the recorder open.” |
| 13–25 s | Ask for a calculation and a new note, then show `486` appear in Notes. Keep the Mac windows visible. | “Calculate 18 times 27 and put the result in a new note.” |
| 25–32 s | Ask Conductor to place Calculator on the left and Notes on the right, then show both windows. | “Put Calculator on the left and Notes on the right.” |
| 32–40 s | Start a harmless waiting task and click Stop while it is still running. Show the actual Stop button. | Say, “Wait 20 seconds before replying. Do not change anything.” Add voiceover afterward: “I can stop it here.” |

The four moments are closing the throwaway apps, putting an answer in Notes, arranging two windows, and stopping a task. The first shot is a cold open from the real recording; do not stage a result or present a different build as the public app. Add narration as a separate voiceover after the screen capture so it is not sent as another command. Trim idle time between commands, but do not speed up a response. If a task fails or the recording does not show the result, record it again instead of narrating over a miss. Adjust the shot lengths to the measured run while keeping the finished video between 30 and 40 seconds.

The 17-app close result is an owner-reported measurement from a prior private build. Put that number or its 12.6-second timing on screen only if the public app repeats and records that exact result on the throwaway setup.

## Turn your recording into the README GIF

Save the original recording as `work/conductor-demo.mov`. `work/` is ignored by Git. Install FFmpeg if it is not already available, then run this from the repository folder:

```sh
bash demo/make-gif.sh work/conductor-demo.mov
```

The script creates `assets/demo.gif` and adds it to the README. Review the GIF at full size before committing it. Confirm the app screen is real, no private material is visible, the spoken request matches the actions, and the full result remains legible. Keep the original video out of the repository.
