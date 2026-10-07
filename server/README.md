# FlutterFix server (reports from a phone, away from your Mac)

```
phone ──(HTTPS, signed-in tester)──▶ Firebase function ──▶ GitHub issue + screenshot
                                                                  │
                                          GitHub Action runs Claude ◀┘
                                                  │
                                       pull request ──▶ your PR checks ──▶ you review and merge
```

Nothing here merges code. A tester can only file a report; Claude can only open a
pull request; you decide.

## Safety rules built in

- **Only your testers.** The function checks the caller's Firebase sign-in and an
  allow-list of emails. Everyone else gets 403.
- **Daily cap** per tester (default 20) and a **monthly cap** on Action runs (default 30).
- **Reports are data, not instructions.** The workflow only reacts to issues filed
  by the function's own GitHub account, and the prompt tells Claude to treat the text
  as a bug description.
- **Limited tools** for Claude in the Action, and it never merges.
- Screenshots live on a `flutterfix-reports` branch, away from your code.

## Set up (once per app)

### 1. The function

Needs the Firebase **Blaze** plan (pay as you go; this costs pennies).

```bash
cd server/functions && npm install
# from your app's firebase project folder, with this folder as a functions codebase:
firebase functions:secrets:set FLUTTERFIX_GITHUB_TOKEN     # see below
firebase deploy --only functions:flutterfixReport
```

It asks for `FLUTTERFIX_GITHUB_REPO` (`owner/app-repo`) and
`FLUTTERFIX_ALLOWED_EMAILS` (`you@x.com,tester@y.com`) when you deploy. You can also
put them in `server/functions/.env.<project-id>`.

`FLUTTERFIX_GITHUB_TOKEN`: a fine-grained personal access token on the app repo with
**Contents: read and write** and **Issues: read and write**. The GitHub account that
owns it is the "reporter" the workflow trusts.

The deployed URL looks like
`https://us-central1-<project>.cloudfunctions.net/flutterfixReport`.

### 2. The workflow

Copy `github/flutterfix.yml` to `.github/workflows/flutterfix.yml` in the app repo and
add the secret and variables listed at the top of that file.

### 3. The app

```dart
final sink = OutboxSink(
  HttpSink(
    Uri.parse(functionUrl),
    headers: () async => {
      'Authorization': 'Bearer ${await FirebaseAuth.instance.currentUser?.getIdToken()}',
    },
  ),
  dir: await getApplicationSupportDirectory(),
);

MaterialApp(
  builder: (context, child) => FlutterFix(
    enabled: isTester,   // false for everyone else
    sink: sink,
    child: child!,
  ),
);
```

Reports made without signal are kept on the phone and sent when it is back online.

## Tests

```bash
cd server/functions && node --test
```
