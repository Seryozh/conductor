# Native interface

The command surface is a SwiftUI view inside a nonactivating AppKit panel. It starts as a 360 × 54 pt rail at the bottom of the active screen and expands upward to at most 600 × 520 pt, within the visible screen. Dragging moves the anchor. Task progress, microphone capture and queued-request count are shown independently.

`Sources/Views.swift` owns the presentation and existing model bindings. `Sources/Main.swift` owns panel lifecycle and focus. `Sources/CommandPanelGeometry.swift` clamps the window. Settings group the existing controls into Voice, Connections, Access, Advanced and Jev activity; the optional setup guide uses those same controls and does not add runtime gates.

The engine behavior is unchanged: Fn/right Option and Option-Space use their existing callbacks; typed submission releases keyboard focus before calling `runTyped`; Stop calls `cancelCurrentTask` and does not disable the microphone. Escape closes typed input and releases focus. Closing an answer calls `dismissAnswer`. Model switching and new conversations keep their existing queue behavior. Long answers scroll; the typed field and bottom rail remain reachable.

Presentation uses opaque near-black surfaces, warm text, yellow action accents and red microphone/attention indicators. The app icon is separate from small operational controls.

Verification: native source builds, screen-state fixtures were visually inspected, and an independent design review passed. Geometry tests covered expansion and screen edges. Real pointer pass-through, Spaces and microphone interaction still require an installed-app check. Fixture images with sample data must not be presented as evidence of real tasks completed.
