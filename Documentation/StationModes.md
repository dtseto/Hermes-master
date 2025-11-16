# Station Modes (Read-only)

Hermes now surfaces the Pandora "station modes" metadata without letting the UI
change modes yet. Once a station successfully loads:

- The playback view shows a **Station Mode** label under the progress bar. The
  label stays greyed out to indicate it is informational only. When Pandora
  reports the active mode, the label is updated to `Station Mode: <name>`.
- The `Stations ▸ Station Modes` menu lists every mode returned by Pandora and
  uses a checkmark to highlight the current mode. Items remain disabled so
  clicking them does nothing—this avoids the double-stream race we used to see
  when wiring the actions directly to Core Audio.

If a station has not finished loading (or Pandora does not expose modes for it),
Hermes hides the label and disables the menu entirely. Once the backend work to
switch modes safely is complete we can enable the menu actions, but this read‑
only view gives visibility into Pandora's modes today without destabilizing
playback.
