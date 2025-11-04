# AudioStreamer Error Classification

Hermes now classifies stream failures as either **transient** (safe to retry) or
**fatal** (requires user attention). The classification is surfaced publicly via
`+[AudioStreamer isErrorCodeTransient:networkError:]` and the
`ASStreamErrorInfoNotification` notification. Consumers can inspect the
`transient` flag in the notification payload to decide when to retry playback or
surface richer error messaging. This change does not alter playback behaviour
yet—it simply exposes the data needed for the upcoming retry loop.
