# AudioStreamer State Controller Extraction

This refactor moves the state/notification plumbing out of `AudioStreamer.m` and into `AudioStreamerStateController`, keeping the 1.3k‑line streamer focused on playback while a small helper owns state transitions, main-thread dispatching, and notification fan-out. The controller mirrors the legacy behaviour (same notification names, ordering, logging, and distributed notifications) and is injectable, so production keeps using the default centres while tests can supply fakes. The surface area touched is deterministic Foundation code—no Core Audio calls—so the behavioural risk stays low.

### Running the new tests

The XCTest coverage for the controller lives in `Sources/AudioStreamer/AudioStreamerStateControllerTests.m`. Add that file to your preferred test target (or create one) and run via Xcode, or from the command line with something like `xcodebuild test -scheme HermesTests` after wiring the file into the scheme. The controller exposes a `dispatchSynchronouslyForTesting` flag so tests can force synchronous execution and avoid racey expectations when needed.

### Migration notes

- `AudioStreamer` now instantiates `AudioStreamerStateController` but retains the legacy logic as a fallback (`legacyTransitionToState:` and `handleFailureSynchronouslyWithCode:`) to guarantee behaviour matches older builds even if the controller is unavailable. This preserves backwards compatibility and makes reversion simple.
- `failWithErrorCode:` routes through the controller for thread-hopping but the error-code gating still occurs inside `AudioStreamer`, which keeps existing error semantics intact.
- Tests sit alongside the production sources because the sandbox prevented creating a dedicated `Tests/` directory. They can be moved into a formal test target as part of integration.

### Reverting

To revert the change, remove `AudioStreamerStateController.{h,m}` and the associated test file, delete the helper import/property from `AudioStreamer.m`, and restore the original `setState:` and `failWithErrorCode:` implementations (now preserved in `legacyTransitionToState:` and `handleFailureSynchronouslyWithCode:`). The project file entries for the controller can then be dropped to return to the prior build graph.

