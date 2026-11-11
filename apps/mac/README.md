# Omnicast for macOS

SwiftUI app, no third-party dependencies. SwiftPM builds the executable; `scripts/build.sh`
assembles `build.noindex/Omnicast.app` around it and ad-hoc signs it (TCC prompts key off the
bundle id, which an ad-hoc signature is enough for). The `.noindex` suffix matters: Spotlight skips
those directories, so a dev build does not show up in Launchpad and search as a second copy of an
installed Omnicast.

```
Sources/Omnicast
├── App/         entry point, menu bar, AppEnvironment, action dispatch
├── Launcher/    the Spotlight-style NSPanel and its SwiftUI content
├── Search/      ranking, learning, and one provider per source
├── Clipboard/   pasteboard monitor and SQLite history
├── Dictation/   recorder, model downloads, transcription backends, history
├── Services/    SQLite wrapper, global hot keys, settings, API sync
└── UI/          glass materials, main window, history/model/settings views
```

Points worth knowing before changing things:

- **fn-key dictation is an `NSEvent` monitor, not a hot key.** The fn key can't be registered with
  Carbon, so `FnKeyMonitor` watches `flagsChanged` for key code 63 (arrow and F-keys also set
  `.function` in their flags, which is why the key code matters). The gesture itself lives in
  `FnGestureMachine` — pure, and tested directly.
- **The droplet panel is click-through.** `ignoresMouseEvents`, non-activating, and above the menu
  bar level, so it never takes focus from whatever you are dictating into.

- **The launcher searches installed applications only.** `ClipboardProvider` and
  `DictationProvider` exist to back their own browsing modes (`⌘⇧V`, the Dictation window), never
  the app search. `SearchEngine` still publishes partial results as providers return, which keeps
  the list live from the first keystroke.
- **The panel is non-activating.** That is what lets a paste land in the app underneath the moment
  the launcher closes.
- **Nested observables don't propagate in SwiftUI.** `AppEnvironment` forwards its children's
  `objectWillChange` into its own publisher; views that observe only the environment depend on it.
- **The launcher's text field binds straight to `SearchEngine.query`** — do not reintroduce a
  separate `@State` copy, it drifts.
- **Backspace cannot be caught with `onKeyPress`.** It is text input, so a focused `TextField`
  consumes it before any key-press modifier runs — the browsers' "delete past the start to go
  back" gesture needs a local `NSEvent` monitor, guarded on the launcher being the key window so a
  backspace typed anywhere else is never swallowed.
- **An empty query means two different things.** In the application search it is a prediction, so
  the list holds only what you have opened before; in a browser it is an unfiltered list and must
  show everything. `SearchEngine.predicts(query:mode:)` is the single place that decides, because
  conflating them silently emptied both browsers.
- **Learning is split three ways on purpose.** `LearningModel` is a pure value type holding the
  decay and scoring maths; `UsageStore` persists it to SQLite and logs each decision;
  `LearningReplay` scores the model against that log. Keeping the maths free of I/O is what makes
  a weight change measurable rather than a matter of taste.
- **A URL detector cannot just look for a dot.** `.app`, `.sh`, `.md`, `.py` and `.js` are all real
  top-level domains, so `Omnicast.app` and `build.sh` parse as perfectly good hosts. `URLDetector`
  requires a curated TLD for a bare host and excludes the ones that collide with filenames, which
  a path or an explicit scheme overrides. The tests are the specification here.
- **Finder is not in `/Applications` either.** It lives in `/System/Library/CoreServices`, next to
  110-odd internal agents nobody launches. Filtering those out by `LSUIElement`/`LSBackgroundOnly`
  does not work — Finder sets neither, and plenty of legitimate menu-bar apps set both (Omnicast
  included) — so `ApplicationProvider` names the handful worth listing outright.
- **Safari is not in `/Applications`.** It ships in a sealed cryptex volume with only a symlink
  left behind, and directory enumeration does not follow symlinks — hence the extra search root in
  `ApplicationProvider`. Without it the launcher cannot find Safari at all.
- **Microphone sensitivity lives in `AudioLevel`,** not the shader. It maps RMS from a -52 dBFS
  floor to a -12 dBFS ceiling and expands the quiet end (`pow(x, 0.65)`), because a linear dB map
  leaves ordinary speech at a third of the range and the waveform looks dead. Tests pin the curve
  at known signal levels.
- **The dictation waveform is a Metal shader.** `UI/SiriWave.metal` is a port of the Siri voice
  waveform (chromatic aberration, four offset copies, band fill), with a `level` input added so it
  answers to the microphone rather than a timer. SwiftPM does not build Metal sources, so
  `scripts/build.sh` compiles it into `Contents/Resources/default.metallib`, where
  `ShaderLibrary.default` finds it. Running the raw SwiftPM binary instead of the `.app` leaves the
  shader unavailable.
- **Never hand a shader an absolute timestamp.** Shader uniforms are `float`, and a float32 near
  `timeIntervalSinceReferenceDate` (~7.85e8) steps in jumps of 1024 seconds — every frame gets an
  identical value and the wave freezes solid. `SiriWaveView` passes elapsed seconds from a
  per-view epoch instead, wrapped hourly. Tests pin both halves of that.
- **The shader carries its own alpha** rather than using an additive blend mode. A blend mode
  composites against whatever SwiftUI decides the backdrop is, and that isolated the layer and
  painted the glass solid black.
- **The launcher window carries a transparent margin** (`LauncherView.shadowInset`). A window
  clips anything drawn outside its bounds, so without the margin the glass panel's drop shadow is
  sliced off at the corners.
