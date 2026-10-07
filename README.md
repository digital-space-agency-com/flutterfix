# FlutterFix

Long press anything in your Flutter app, say what is wrong, and a report lands
in front of Claude: the element, its text, the widgets that built it, a
screenshot with the element outlined, and your words. Claude finds the code and
fixes it.

It works two ways:

| | At your Mac | Away from your Mac (phone, 5G) |
|---|---|---|
| **Where you test** | iOS simulator, Android emulator, or a phone on your Wi-Fi | TestFlight or Play internal builds on a real phone, anywhere |
| **Where the report goes** | Straight into your running Claude Code session | A GitHub issue, then Claude opens a pull request |
| **You get back** | A fix in your working folder | A pull request to review and merge from the GitHub app |
| **Setup** | 5 minutes | About an hour, once per app |

Both use the same widget. You pick the destination with one line of code.

---

## Contents

1. [How it works](#how-it-works)
2. [Quick start (at your Mac)](#quick-start-at-your-mac)
3. [Using it](#using-it)
4. [Turning it on for testers only](#turning-it-on-for-testers-only)
5. [Away from your Mac: the cloud route](#away-from-your-mac-the-cloud-route)
6. [What to change for your own app](#what-to-change-for-your-own-app)
7. [Reference](#reference)
8. [Safety and cost](#safety-and-cost)
9. [Troubleshooting](#troubleshooting)
10. [Limits](#limits)

---

## How it works

```
                        ┌──────────────────────────── in the app ───────────────────────────┐
 long press ──▶ find the element ──▶ outline it ──▶ you type a comment ──▶ screenshot + report
                        └────────────────────────────────────────────────────────────────────┘
                                                       │
                              ┌────────────────────────┴───────────────────────┐
                              ▼                                                ▼
              LocalReceiverSink  (at your Mac)                   HttpSink + OutboxSink  (anywhere)
                              │                                                │
              dart run flutterfix:receiver                     Firebase function (checks sign-in
              prints one line per report                       and a tester list, daily cap)
                              │                                                │
              Claude Code session (Monitor)                    GitHub issue + screenshot
                              │                                                │
              Claude edits your working folder                 GitHub Action runs Claude
                                                                               │
                                                               pull request ──▶ your PR checks
                                                                               │
                                                                    you review and merge
```

**Finding the element.** When you press, FlutterFix hit-tests the screen to find
the smallest thing under your finger, then collects the text drawn inside it
and next to it. If you marked widgets with `.fixable('name')`, the innermost
mark wins and the report names it.

**What a report contains**

| Field | Where it comes from | Debug builds | Release / internal test builds |
|---|---|---|---|
| Your comment | You | yes | yes |
| Element kind and bounds | Hit test | yes | yes |
| Text on the element and beside it | The text drawn on screen | yes | yes |
| Name you gave it (`.fixable`) | Your mark | yes | yes |
| **Source file and line** of the mark | Call site of `Fixable(...)` | **yes** | no (stripped) |
| **Chain of widgets** (`Text ← Row ← MovieDetails`) | Flutter's debug info | **yes** | no (stripped) |
| Screenshot, element outlined in red | Screen capture | yes | yes |
| Screen name, app version, platform | What you pass in | yes | yes |

So on a phone running a TestFlight build, Claude has the text and your names to
go on, not the source line. **Mark the things you care about with `.fixable`**:
the name is searchable in the code even in release builds.

---

## Quick start (at your Mac)

You need Flutter (built against 3.24 and later, tested on 3.47) and Claude Code. Nothing else.

**1. Add the package.** In your app's `pubspec.yaml`:

```yaml
dependencies:
  flutterfix:
    git:
      url: https://github.com/digital-space-agency-com/flutterfix.git
      ref: main
```

**2. Wrap the app.** In `MaterialApp` (or `MaterialApp.router`), use `builder`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutterfix/flutterfix.dart';

MaterialApp(
  builder: (context, child) => FlutterFix(
    enabled: kDebugMode,                  // off in release builds
    sink: const LocalReceiverSink(),      // sends to your Mac
    appVersion: '1.2.3+45',               // optional, helps you know which build
    child: child!,
  ),
  // ...
)
```

It must go in `builder` so it wraps the whole app, above the navigator.

**3. Start the receiver in your Claude Code session.** The receiver is a small
program that listens for reports and prints one line for each. Ask Claude Code to
start it with its Monitor tool, so every report arrives in the conversation:

```bash
dart run flutterfix:receiver
```

Each report then appears as one line, for example:

```
[fix r3] welcome.title · lib/screens/welcome.dart:139 · RenderParagraph · text "Stop Scrolling" · in Text ← Column ← WelcomePage · .flutterfix/reports/r3.png :: Make this smaller
```

Reports and screenshots are also saved in `.flutterfix/reports/`. Add
`.flutterfix/` to your `.gitignore`, and let Claude read the screenshots without
asking each time by adding this to `.claude/settings.json`:

```json
{ "permissions": { "allow": ["Read(./.flutterfix/**)"] } }
```

**4. Run the app and long press something.** Say what is wrong and press Send.
Claude sees the line and can start fixing.

### Emulators and phones on your network

| Where the app runs | What to do |
|---|---|
| iOS simulator | Nothing. It reaches `127.0.0.1`. |
| Android emulator | The address `10.0.2.2` (the emulator's name for your Mac) is used automatically. Android blocks plain `http` by default, so allow it in debug builds only: create `android/app/src/debug/AndroidManifest.xml` containing `<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:usesCleartextTraffic="true"/></manifest>`. |
| A real phone on the same Wi-Fi | `LocalReceiverSink(host: '192.168.1.20')` with your Mac's address. On iPhone also add `NSAllowsLocalNetworking` under `NSAppTransportSecurity` and an `NSLocalNetworkUsageDescription` to `Info.plist` for debug builds. |
| A phone on mobile data, away from home | Use the [cloud route](#away-from-your-mac-the-cloud-route). |

---

## Using it

**Report a problem.** Press and hold for about half a second. The screen dims,
the element under your finger is outlined, and a box opens with its name. Type
what is wrong and press Send (or the keyboard's send key). Tap outside the box
or press Cancel to dismiss it. Normal taps, scrolls and swipes still work.

**Name an element.** Anything can be marked, with a method or a widget:

```dart
Text(card.number).fixable('card.number')

Fixable('home.walletCard', child: WalletCard())
```

Put the mark on the widget whose code you want Claude to open: the `Text`
itself for a typo or colour, the container for spacing or layout. Nested marks
resolve to the innermost one under the finger. Names can be anything that makes
sense to you, including data, such as `'transaction.${t.merchant}'`.

**Say which screen it is.** Pass the current route so reports say where they
came from:

```dart
FlutterFix(
  screenName: () => currentRouteName(),   // whatever your router exposes
  // ...
)
```

**Attach anything else.** Values you add are sent with every report:

```dart
FlutterFix(
  extra: () => {'flavor': 'internal', 'user': currentUserId},
  // ...
)
```

---

## Turning it on for testers only

In a release build (TestFlight, Play internal testing) `kDebugMode` is false, so
`enabled: kDebugMode` shows nothing. To let your testers report problems from
those builds without exposing it to real users, switch it on from something you
control:

```dart
FlutterFix(
  enabled: kDebugMode || isTester,
  // ...
)
```

Choose `isTester` to suit the app. Two common ways:

- **A list of tester emails** (simple and safe, since the server checks it too):

  ```dart
  const testers = {'you@example.com', 'tester@example.com'};
  final isTester = testers.contains(FirebaseAuth.instance.currentUser?.email);
  ```

- **A Remote Config flag**, so you can switch it off for everyone from the console:

  ```dart
  final isTester = remoteConfig.getBool('flutterfix_enabled') &&
      testers.contains(user?.email);
  ```

When `enabled` is false the widget returns your app unchanged: no gesture
recognizer, no overlay, no work.

---

## Away from your Mac: the cloud route

This lets a tester (you, on your phone, on 5G) send a report and get a pull
request back, with your Mac switched off.

```
phone ──(HTTPS, signed in)──▶ Firebase function ──▶ GitHub issue (+ screenshot)
                                                         │
                                         GitHub Action runs Claude
                                                         │
                                        pull request ──▶ your checks ──▶ you merge
```

- On the phone, **`HttpSink`** sends the report and **`OutboxSink`** keeps it on
  the phone if there is no signal, then sends it later (on app start, when the
  app comes back to the foreground, and after the next successful send).
- The **function** (`server/functions`) checks the caller's sign-in and a tester
  list, applies a daily limit, stores the screenshot on a `flutterfix-reports`
  branch, and files a GitHub issue labelled `flutterfix`.
- The **workflow** (`server/github/flutterfix.yml`) runs Claude on that issue
  and opens a pull request. It never merges.

### Costs and accounts you need

| You need | Why | Typical cost |
|---|---|---|
| A Firebase project with the **Blaze** (pay as you go) plan | Cloud Functions needs it | Pennies a month at this volume |
| Firebase Authentication in the app | The function checks who is sending | Free |
| A GitHub repository for the app | Receives the issues and pull requests | Free |
| A GitHub fine-grained access token | Lets the function create issues | Free |
| An Anthropic API key | Lets the GitHub Action run Claude | Per use; the monthly cap limits it |
| Node 20 and the Firebase CLI | To deploy the function | Free |

### Step by step

**1. Deploy the function** (once per Firebase project).

```bash
git clone https://github.com/digital-space-agency-com/flutterfix.git
cd flutterfix/server/functions
npm install
node --test                      # optional: runs the function's own tests
```

Copy that `functions` folder into your Firebase project (or point
`firebase.json` at it as a codebase), then from your Firebase project folder:

```bash
firebase login
firebase use <your-project-id>
firebase functions:secrets:set FLUTTERFIX_GITHUB_TOKEN      # paste the token when asked
firebase deploy --only functions:flutterfixReport
```

During deploy it asks for two values (or put them in
`functions/.env.<your-project-id>`):

```
FLUTTERFIX_GITHUB_REPO=your-org/your-app-repo
FLUTTERFIX_ALLOWED_EMAILS=you@example.com,tester@example.com
```

Create the token at GitHub, Settings, Developer settings, Fine-grained tokens:
choose your app repo only, with **Contents: read and write** and **Issues: read
and write**. The GitHub account that owns the token is the "reporter" the
workflow trusts, so use an account you control.

When it finishes, note the function's URL:
`https://us-central1-<your-project-id>.cloudfunctions.net/flutterfixReport`

**2. Add the workflow to your app repo.**

Copy `server/github/flutterfix.yml` to `.github/workflows/flutterfix.yml` in
your app repo. Then in the repo, Settings, Secrets and variables, Actions:

| Kind | Name | Value |
|---|---|---|
| Secret | `ANTHROPIC_API_KEY` | Your Anthropic API key |
| Variable | `FLUTTERFIX_REPORTER` | The GitHub username that owns the token from step 1 |
| Variable (optional) | `FLUTTERFIX_MONTHLY_CAP` | Most runs a month; default 30 |
| Variable (optional) | `FLUTTER_VERSION` | Flutter version for the runner; default 3.47.5 |

Also create a label named `flutterfix` in the repo (Issues, Labels), because the
function applies it. The workflow runs `flutter pub get`, `flutter analyze`
and `flutter test`; if your project needs more (code generation, an `.env`
file), add those steps before the Claude step.

**3. Point the app at the function.**

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

final sink = OutboxSink(
  HttpSink(
    Uri.parse('https://us-central1-<your-project-id>.cloudfunctions.net/flutterfixReport'),
    headers: () async => {
      'Authorization':
          'Bearer ${await FirebaseAuth.instance.currentUser?.getIdToken()}',
    },
  ),
  dir: await getApplicationSupportDirectory(),   // where unsent reports wait
);

MaterialApp(
  builder: (context, child) => FlutterFix(
    enabled: kDebugMode || isTester,
    sink: sink,
    appVersion: appVersion,
    child: child!,
  ),
)
```

Not using Firebase Authentication? `HttpSink` takes any header callback, so use
whatever your backend checks, and change the function's sign-in check to match.

**4. Try it.** Install a build on your phone, long press something, send, and
watch for the GitHub issue (seconds), the Action run (a few minutes) and the
pull request. Review it in the GitHub app, merge, and install the next build.

---

## What to change for your own app

A checklist of everything specific to the app. Search these placeholders.

| What | Where | Change it to |
|---|---|---|
| Package source | App `pubspec.yaml` | The git URL above (or a path while developing) |
| Who sees the overlay | `enabled:` on `FlutterFix` | `kDebugMode` alone at your Mac; add a tester check for phones |
| Where reports go | `sink:` on `FlutterFix` | `LocalReceiverSink()` at your Mac; `OutboxSink(HttpSink(...))` for the cloud route |
| Function URL | `HttpSink(Uri.parse(...))` | Your deployed function URL |
| Your GitHub repo | `FLUTTERFIX_GITHUB_REPO` (function) | `your-org/your-app-repo` |
| Tester emails | `FLUTTERFIX_ALLOWED_EMAILS` (function) and your `isTester` check | Your emails |
| Daily limit per tester | `FLUTTERFIX_DAILY_CAP` (function) | A number; default 20 |
| GitHub token | Firebase secret `FLUTTERFIX_GITHUB_TOKEN` | A fine-grained token on your app repo |
| Reporter account | Variable `FLUTTERFIX_REPORTER` (workflow) | Owner of that token |
| Anthropic key | Secret `ANTHROPIC_API_KEY` (workflow) | Your key |
| Flutter version | Variable `FLUTTER_VERSION` (workflow) | The version your app uses |
| Extra build steps | `.github/workflows/flutterfix.yml` | Anything your project needs before `flutter test` |
| Branch for screenshots | `BRANCH` in `server/functions/index.js` | Leave as `flutterfix-reports` unless it clashes |
| Names of widgets | `.fixable('...')` | Names that mean something to you |

Nothing else in the package is specific to one app.

---

## Reference

### `FlutterFix` (widget)

| Parameter | Type | Meaning |
|---|---|---|
| `child` | `Widget` | Your app (required). |
| `sink` | `FlutterFixSink` | Where reports go (required). |
| `enabled` | `bool` | Switch it on or off. Default: `kDebugMode`. |
| `screenName` | `String? Function()?` | Name of the screen on display. |
| `appVersion` | `String?` | Sent with each report. |
| `extra` | `Map<String,String> Function()?` | Extra values sent with each report. |
| `holdDuration` | `Duration` | How long to hold. Default 600 ms. |

### Destinations (sinks)

| Class | Use it for |
|---|---|
| `LocalReceiverSink({host, port = 4747})` | Your Mac, from a simulator, emulator or phone on your network. |
| `HttpSink(url, {headers, timeout})` | Your own HTTPS endpoint from anywhere, such as the function in `server/`. |
| `OutboxSink(inner, {dir, maxItems = 20})` | Wrap another sink to keep reports on the phone while offline and send them later. |
| `MemorySink()` | Tests and demos. |

`HttpSink` treats `401/403` and other `4xx` as final (the report is not kept) and
`408`, `429`, `5xx` and network errors as retryable.

**Write your own** by extending `FlutterFixSink` and returning a `FixSendResult`:

```dart
class SlackSink extends FlutterFixSink {
  @override
  Future<FixSendResult> send(FixReport report) async {
    // post report.comment, report.element, report.screenshotPng ...
    return const FixSendResult.ok('sent');
  }
}
```

### Marking elements

| | |
|---|---|
| `Fixable(name, child: widget)` | Wraps a widget. |
| `widget.fixable(name)` | The same, as an extension method. |

### The receiver (at your Mac)

```bash
dart run flutterfix:receiver [--port 4747] [--out .flutterfix]
```

Listens for reports, saves `rN.json` and `rN.png` in `<out>/reports/`, and
prints one line per report. One receiver per machine; starting a second one on
the same port fails.

### Server configuration

| Setting | Where | Meaning |
|---|---|---|
| `FLUTTERFIX_GITHUB_TOKEN` | Firebase secret | Token used to file issues and store screenshots. |
| `FLUTTERFIX_GITHUB_REPO` | Function parameter | `owner/repo` that receives the issues. |
| `FLUTTERFIX_ALLOWED_EMAILS` | Function parameter | Comma-separated emails allowed to send. |
| `FLUTTERFIX_DAILY_CAP` | Function parameter | Reports per tester per day. Default 20. |
| `ANTHROPIC_API_KEY` | GitHub secret | Runs Claude in the Action. |
| `FLUTTERFIX_REPORTER` | GitHub variable | The only issue author the workflow trusts. |
| `FLUTTERFIX_MONTHLY_CAP` | GitHub variable | Action runs per month. Default 30. |

More detail on the function is in [`server/README.md`](server/README.md).

---

## Safety and cost

- **Only your testers can send.** The function verifies the caller's Firebase
  sign-in and checks the email against your list. Everyone else gets a refusal.
- **Limits stop runaway costs.** A daily cap per tester (function) and a monthly
  cap on Action runs (workflow).
- **Reports are treated as data.** The workflow only reacts to issues created by
  your reporter account, and tells Claude to treat the text as a bug description,
  not as instructions. Claude gets a limited set of tools in the Action.
- **Nothing is merged for you.** Claude opens a pull request; your normal checks
  run and you decide.
- **Secrets stay out of the app.** The GitHub token lives in Firebase and the
  Anthropic key in GitHub. The app holds only the function URL and a sign-in.
- **What leaves the phone:** your comment, the element details, screen and
  version, and a screenshot of the app (which may show user data in the app).
  Use it with test accounts, and only for people you trust.
- **Switch it off** by setting `enabled: false` in a release, or removing the
  tester from the list.

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Nothing happens on long press | `enabled` is false (check `kDebugMode`, `isTester`), or `FlutterFix` is not in `MaterialApp.builder`. |
| "Could not reach the receiver" | The receiver is not running (`dart run flutterfix:receiver`), or on a phone the `host` is wrong or the phone is not on the same Wi-Fi. |
| Android emulator cannot reach the Mac | Add the debug `usesCleartextTraffic` manifest from the table above. |
| Real iPhone cannot reach the Mac | Add the local-network settings to `Info.plist`; accept the iOS local network prompt. |
| "Not allowed to send reports" | The caller is not signed in, or their email is not in `FLUTTERFIX_ALLOWED_EMAILS`. |
| "daily limit reached" | The tester sent more than `FLUTTERFIX_DAILY_CAP` today. |
| The banner says "Saved, will send automatically" | There was no connection. It sends when the app next has one. |
| Issue appears but no pull request | The Action did not run: check `FLUTTERFIX_REPORTER` matches the token's owner, the `flutterfix` label exists, `ANTHROPIC_API_KEY` is set, and the monthly cap is not reached (see the Actions tab). |
| The Action cannot fetch the screenshot | The workflow needs `fetch-depth: 0` (already set) so the `flutterfix-reports` branch is available. |
| The box covers the element | It moves to the top when the element is in the lower half; if it still overlaps, report it. |
| Reports have no source line | Expected in release builds. Mark elements with `.fixable('name')`. |

---

## Limits

- Mobile and desktop only: it uses `dart:io`, so it does not compile for Flutter web.
- It finds elements by hit testing and reading drawn text. Custom painted
  content (a game canvas) is reported as one element.
- Text inside platform views (maps, web views, video players) is not seen.
- A report sent from a release build has no source line or widget chain; name the
  elements that matter.
- The Claude Action needs a project Claude can build and test on a Linux runner.
  Projects needing secrets, code generation or other setup need extra workflow
  steps.

---

## Development

```bash
flutter test                  # the package's tests
cd server/functions && node --test   # the function's tests
```

MIT licensed. Issues and pull requests are welcome.
