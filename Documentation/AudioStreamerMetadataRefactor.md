# AudioStreamer Metadata Helper Extraction

This change lifts the file-type hinting and duration/bit-rate math out of `AudioStreamer.m` into a stateless helper (`AudioStreamerMetadata`). The helper mirrors the original logic byte-for-byte, and `AudioStreamer` now delegates to it, so playback behaviour is unchanged while the 1,300‑line file shrinks and becomes easier to reason about. Because the migration only touches pure calculations, the risk of regressions is low; the audio queue, network session, and state machine logic remain untouched.

To exercise the new coverage, build the test target that includes `AudioStreamerMetadataTests.m` (for example, in Xcode select the Hermes test bundle and run). The XCTest cases validate the extension/MIME hints, the bit‑rate calculation edge cases, and duration math so you can refactor further with confidence. If you are integrating outside Xcode, run `xcodebuild test -scheme HermesTests` (or your local test scheme) after adding the new file to that target.

