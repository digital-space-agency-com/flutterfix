# FixLens

Long press any element of a Flutter app, say what is wrong, and the report
lands in your Claude Code session: the element, its text, the widget it came
from, a screenshot with the element outlined, and your words. Claude finds the
code and fixes it.

Works on the iOS simulator, the Android emulator, and real phones (debug and
internal test builds). A release build with `enabled: false` compiles none of
it into the view tree.

## Add it to an app

```yaml
dependencies:
  fixlens:
    path: ../fixlens   # or a git url once this lives in a repo
```

```dart
MaterialApp(
  builder: (context, child) => FixLens(
    enabled: kDebugMode,                 // or a Remote Config flag for testers
    sink: const LocalReceiverSink(),     // sends to your Mac
    appVersion: '1.2.3+45',
    screenName: () => currentRouteName,  // optional
    child: child!,
  ),
)
```

Put `FixLens` in `MaterialApp.builder` (or `MaterialApp.router`'s builder) so it
wraps the whole app, above the navigator.

### Name an element (optional)

```dart
Text(card.number).fixable('card.number')
Fixable('home.walletCard', child: WalletCard())
```

A mark makes the report lead with the name and, in debug builds, the
`file:line` of the call. Nested marks resolve to the innermost one. Unmarked
elements still work: the report carries their text, nearby text and the chain
of widgets that built them (debug builds).

## Receive reports in Claude Code

In the project folder:

```bash
dart run fixlens:receiver
```

Better, start it from the Claude Code session with the Monitor tool so every
report arrives in the conversation as one line:

```
[fix r3] welcome.title · lib/screens/onboarding/onboarding_screen.dart:139 · RenderParagraph · text "Stop Scrolling. Start Watching." · .fixlens/reports/r3.png :: Make this smaller
```

Reports and screenshots are saved in `.fixlens/reports/` (add `.fixlens/` to
`.gitignore`). Allow Claude to read them without asking:

```json
{ "permissions": { "allow": ["Read(./.fixlens/**)"] } }
```

The Android emulator reaches your Mac as `10.0.2.2` (handled automatically).
A real phone on the same Wi-Fi needs the Mac's address:
`LocalReceiverSink(host: '192.168.1.20')`.

## Other destinations

Implement `FixLensSink` to send reports anywhere (Firestore, a GitHub issue,
a chat). That is how reports get to Claude when you are away from your Mac.

## Status

v0.1: long press, highlight, comment, screenshot, local receiver. Next: cloud
sink and a GitHub Action that turns a report into a pull request.
