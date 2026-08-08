# Repository guidance

## Project identity

- This is ApolloGene, a maintained Objective-C/AppKit fork of the Hermes Pandora client.
- `ApolloGene.xcodeproj` is the canonical Xcode project. The nearly empty `Hermes.xcodeproj` directory is not a build entry point.
- The built product is `ApolloGene.app`, but the main target and day-to-day scheme are still named `Hermes`. Many source symbols, defaults, notifications, tests, and scripts also retain the Hermes name. Do not perform broad renames merely for consistency.
- The compatibility goal is a working modern macOS app on both Apple Silicon and Intel. Agents verify changes by building; the developer owns functional and runtime testing.

## Before changing anything

1. At the start of every task, read this `AGENTS.md` file in full before planning or editing, and follow all guidance that applies.
2. Run `git status --short --branch` and preserve all existing staged, unstaged, and untracked work. Never discard or rewrite unrelated changes.
3. Read the relevant source, tests, and documentation before editing. Prefer a focused root-cause fix over a broad modernization pass.
4. Check `ApolloGene.xcodeproj/project.pbxproj` when a change adds, removes, or relocates production source or resources. A file existing on disk does not guarantee that the app target builds it.
5. Before handoff, review `AGENTS.md` again and update it when the task establishes or changes a durable workflow, architecture, testing, release, compatibility, or safety rule. Keep one-off implementation details and temporary repository state out of this file.

## Repository map

- `Sources/ApolloGeneAppDelegate.*`: application lifecycle, window/view switching, menus, and top-level wiring.
- `Sources/Controllers/`: playback, authentication, stations, history, and preferences UI coordination.
- `Sources/AudioStreamer/`: Core Audio streaming, playlists, buffering, retry behavior, and state notifications. Treat packet order and state-transition order as invariants.
- `Sources/Pandora/`: Pandora protocol requests, authentication state, models, station modes, quality selection, and response parsing.
- `Sources/Integration/`: Keychain, notifications, AppleScript, and scrobbling integrations.
- `Sources/Views/`: AppKit view subclasses and presentation helpers.
- `Resources/Base.lproj/MainMenu.xib`: main window, menu, toolbar, bindings, actions, and outlets. UI wiring often spans this file, app delegate/controller headers, and implementations.
- `Resources/ApolloGene-Info.plist`, `Resources/ApolloGene.sdef`, and `Hermes.entitlements`: product metadata, AppleScript surface, and capabilities.
- `HermesTests/`: the active XCTest target. Keep related test code consistent with implementation changes, but leave test execution to the developer.
- `ImportedSources/`: vendored third-party code. Avoid changing it unless the task specifically requires it, and preserve its license files.
- `Documentation/`: subsystem notes. Some release and historical documents predate the ApolloGene rename; verify them against the current project and scripts before relying on them.
- `Scripts/`, `RELEASING.md`, and release schemes: distribution machinery with signing, credentials, upload, tagging, or external-repository effects. Do not invoke it casually.

## Build only; developer tests

Use the repository root as the working directory.

```sh
# Local agent Debug build; output is under build/Debug/ApolloGene.app
xcodebuild \
  -project ApolloGene.xcodeproj \
  -scheme Hermes \
  -configuration Debug \
  -destination 'platform=macOS' \
  SYMROOT=build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

# Local agent Release build
xcodebuild \
  -project ApolloGene.xcodeproj \
  -scheme Hermes \
  -configuration Release \
  -destination 'platform=macOS' \
  SYMROOT=build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

- Agents must not run XCTest, `xcodebuild test`, `make run`, the app itself, manual UI checks, live Pandora checks, or other functional/runtime tests. Build the requested configuration only and let the developer perform all testing.
- This machine does not have the private certificate for the project's configured Developer ID identity. Every local agent build must start with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` on the `xcodebuild` command line, as shown above. Do not first attempt `make` or a normally signed build and wait for signing to fail.
- In sandboxed agent sessions, request the filesystem permission Xcode needs for `~/Library/Developer/Xcode/DerivedData` before the first `xcodebuild` attempt. Do not run an initial sandboxed build that is already known to fail writing DerivedData and then retry it with elevated permission.
- Disabling signing is strictly a local command-line override. Never weaken or remove checked-in signing, entitlements, or hardened-runtime settings to make a local build pass.
- Do not use `make install`, `make archive`, `make upload-release`, the upload/archive schemes, `agvtool`, or release scripts without explicit authorization. They may replace `/Applications/ApolloGene.app`, alter versions, require private keys/tokens, upload artifacts, or affect other repositories.
- Do not redirect new build output into the tracked root-level `*.log`, `test_*.txt`, or `xcresult*.json` artifacts unless the task explicitly concerns those fixtures. Prefer normal command output or a file under `/tmp`.

## Validation boundary

- The agent's validation ends with a successful build. Do not launch or exercise the app and do not run automated or manual tests.
- For code, resource, or Xcode project changes, build the relevant Debug or Release configuration. Documentation-only changes do not require an app build. For distribution or architecture work, build with `ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO` when appropriate.
- Do not claim that UI behavior, playback, Pandora authentication, permissions, media keys, notifications, Keychain, AppleScript, Intel execution, signing, notarization, or release behavior works based only on a successful build.
- In the handoff, state which build completed and give the developer a concise checklist of behavior that still needs testing for the changed area.
- Report build failures accurately. Do not hide them by deleting tests, broadening ignores, disabling warnings, or changing signing settings in source control.

## Objective-C and AppKit conventions

- Follow `Documentation/Contributing.md`: two-space indentation, braces for control flow, a space after control keywords, readable names, `NSString *value` pointer spacing, and no parentheses around return values.
- Keep changes consistent with the surrounding Objective-C style. Avoid unrelated formatting churn or mass API rewrites.
- UI work belongs on the main thread. Preserve existing dispatch behavior and notification ordering when moving asynchronous code.
- The album artwork must resize with the main window and expand to fill the available playback space while preserving its aspect ratio. Do not leave it at a minimum size when usable space remains, and do not let the downloaded image's intrinsic dimensions determine the window size.
- The playback screen's left station list, flexible center content, and right history panel are panes owned by `PlaybackSplitView`. Keep pane sizing and sidebar visibility in that owner; do not rebuild the outer playback layout with `NSStackView` or reconnect sidebar visibility to width/spacing constraints. The center pane has a zero minimum, and sidebars are preferred-width content that must compress when the window is narrower than their combined widths.
- For main-window resize work, audit the complete horizontal and vertical sizing path from every nested stack, scroll view, control, and titlebar item through the content view. A low-priority width constraint alone does not prove a view is resize-neutral: optional sidebars and other auxiliary panels must not advertise intrinsic or fitting sizes that become window floors, while remaining present and togglable.
- `NSStackView` has stack-specific hugging and clipping-resistance priorities in addition to ordinary `NSView` content hugging and compression resistance. For a stack that must collapse, explicitly audit `huggingPriorityForOrientation:` and `clippingResistancePriorityForOrientation:`; overriding `fittingSize` or lowering ordinary compression resistance does not neutralize the stack's synthesized arranged-subview constraints.
- Prefer public AppKit APIs. If an existing private selector is involved, do not expand its use without documenting why no public alternative meets the behavior.
- Handle playback media keys through `MPRemoteCommandCenter` and publish state through `MPNowPlayingInfoCenter`. Do not reintroduce global keyboard event taps or Input Monitoring/Accessibility permission prompts for Play/Pause or Next Track.
- Preserve established notification names, `NSUserDefaults` keys, Keychain lookup attributes, AppleScript commands, and archive formats unless a migration is explicitly part of the task.
- Treat AudioFileStream packet-size properties as a lower bound for AudioQueue buffer capacity, not the desired capacity itself. Queue buffers must retain the configured reserve so each can hold multiple compressed packets under scheduler load, and startup gating must remain duration-based rather than requiring a fixed number of full buffers.
- Use availability checks for APIs newer than the supported deployment target. Do not lower the deployment target or exclude an architecture as a shortcut.
- The project treats many warnings as errors. Fix new warnings at their source; do not globally relax warning policies to land a change.
- Add comments for non-obvious intent, ordering, compatibility, or safety constraints. Do not narrate straightforward code.

## Xcode project and Interface Builder changes

- Make the smallest possible `project.pbxproj` edit and inspect its diff for duplicate references, malformed sections, accidental signing changes, or unrelated Xcode churn.
- Production `.m` files generally need membership in the Hermes target's Sources phase. Resources need membership in its Resources phase. Confirm both in the project file or with a build.
- `HermesTests/` is a file-system-synchronized test group with some explicit project exceptions. Keep project membership correct, but leave test discovery and execution to the developer.
- Treat XIB object IDs, target/action connections, outlets, menu key equivalents, and toolbar item identifiers as stable wiring. When editing `MainMenu.xib` as XML, keep the diff narrow, build successfully, and tell the developer which nib behavior needs testing.
- Product-facing text should say ApolloGene unless compatibility requires a legacy Hermes identifier. Internal names should not be renamed opportunistically.

## Sensitive and external behavior

- Never log Pandora credentials, authentication tokens, Keychain values, signing material, or release credentials. Redact them from fixtures and diagnostics.
- Preserve the Pandora request encryption/TLS and authentication sequencing unless the task explicitly changes the protocol and includes corresponding developer validation guidance.
- Do not make live rating, station deletion, station creation, release upload, or other externally mutating calls merely to validate a local change. Use mocks/fixtures or obtain explicit approval.
- Release documentation contains legacy Hermes/Sparkle/DSA and website assumptions. Treat the current Xcode project and scripts as the implementation truth, reconcile contradictions before release work, and surface uncertainty rather than guessing.

## Handoff

- Summarize the intended user-visible outcome, the files changed, and the exact build performed.
- Clearly state that functional testing was left to the developer and list the most relevant checks they should perform, especially for live Pandora playback, macOS permission prompts, signing/notarization, Intel execution, or release behavior.
- Leave unrelated working-tree changes exactly as found.
