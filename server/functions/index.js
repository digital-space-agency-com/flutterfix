'use strict';

const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret, defineString } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { parseAllowList, isAllowed, validateReport, buildIssue } = require('./lib/format');
const { putScreenshot, createIssue } = require('./lib/github');

admin.initializeApp();

// Set once with `firebase functions:secrets:set FLUTTERFIX_GITHUB_TOKEN`.
const GITHUB_TOKEN = defineSecret('FLUTTERFIX_GITHUB_TOKEN');
// Asked for at deploy time (or put them in functions/.env.<project>).
const REPO = defineString('FLUTTERFIX_GITHUB_REPO'); // owner/repo that gets the issues
const ALLOWED = defineString('FLUTTERFIX_ALLOWED_EMAILS'); // comma separated testers
const DAILY_CAP = defineString('FLUTTERFIX_DAILY_CAP', { default: '20' });

const BRANCH = 'flutterfix-reports';

exports.flutterfixReport = onRequest(
  { secrets: [GITHUB_TOKEN], maxInstances: 3, timeoutSeconds: 60, memory: '512MiB' },
  async (req, res) => {
    if (req.method !== 'POST') return void res.status(405).json({ error: 'POST only' });

    // 1. Who is this? Only signed-in, allow-listed testers may send.
    const auth = req.get('Authorization') || '';
    const idToken = auth.startsWith('Bearer ') ? auth.slice(7) : null;
    if (!idToken) return void res.status(401).json({ error: 'sign in first' });
    let email;
    let verified;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      email = decoded.email;
      verified = decoded.email_verified;
    } catch (_) {
      return void res.status(401).json({ error: 'invalid sign-in' });
    }
    if (!isAllowed(email, parseAllowList(ALLOWED.value()), verified)) {
      return void res.status(403).json({ error: 'not a tester' });
    }

    // 2. Is the report sane?
    const problems = validateReport(req.body);
    if (problems.length) return void res.status(400).json({ error: problems.join('; ') });

    // 3. Daily cap per tester, so a loop or a slip cannot run up costs.
    const day = new Date().toISOString().slice(0, 10);
    const usageRef = admin
      .firestore()
      .collection('flutterfixUsage')
      .doc(`${email.toLowerCase().replace(/[^a-z0-9]/g, '_')}_${day}`);
    const cap = parseInt(DAILY_CAP.value(), 10) || 20;
    const allowedNow = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(usageRef);
      const used = snap.exists ? snap.data().count : 0;
      if (used >= cap) return false;
      tx.set(usageRef, { count: used + 1, email, day });
      return true;
    });
    if (!allowedNow) return void res.status(429).json({ error: 'daily limit reached' });

    // 4. File it.
    try {
      const token = GITHUB_TOKEN.value();
      const repo = REPO.value();
      const id = `${day.replace(/-/g, '')}-${Date.now().toString(36)}`;
      const shot = req.body.screenshotPngBase64
        ? await putScreenshot(token, repo, BRANCH, id, req.body.screenshotPngBase64)
        : null;
      const { title, body } = buildIssue(req.body, { id, shot, repo, branch: BRANCH });
      const issue = await createIssue(token, repo, { title, body, labels: ['flutterfix'] });
      res.status(200).json({ id: `#${issue.number}`, url: issue.url });
    } catch (e) {
      console.error('flutterfix: could not file report', e);
      res.status(502).json({ error: 'could not file the report' });
    }
  },
);
