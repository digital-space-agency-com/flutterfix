'use strict';

const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret, defineString } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { parseAllowList, isAllowed, validateReport, buildIssue } = require('./lib/format');
const { putFiles, createIssue } = require('./lib/github');

admin.initializeApp();

// Set once with `firebase functions:secrets:set FLUTTERFIX_GITHUB_TOKEN`.
const GITHUB_TOKEN = defineSecret('FLUTTERFIX_GITHUB_TOKEN');
// Asked for at deploy time (or put them in functions/.env.<project>).
const REPO = defineString('FLUTTERFIX_GITHUB_REPO'); // owner/repo that gets the issues
const ALLOWED = defineString('FLUTTERFIX_ALLOWED_EMAILS'); // comma separated testers
const DAILY_CAP = defineString('FLUTTERFIX_DAILY_CAP', { default: '20' });

const BRANCH = 'flutterfix-reports';
let coldStart = true; // true for the first request an instance handles

// Where the function runs. Pick the region closest to your users and your
// Firestore database (ReelMatch's is in Europe).
const REGION = 'europe-west1';

exports.flutterfixReport = onRequest(
  { region: REGION, secrets: [GITHUB_TOKEN], maxInstances: 3, timeoutSeconds: 60, memory: '512MiB' },
  async (req, res) => {
    if (req.method !== 'POST') return void res.status(405).json({ error: 'POST only' });
    const started = Date.now();
    const timings = {};
    const mark = (name, since) => { timings[name] = Date.now() - since; };

    // 1. Who is this? Only signed-in, allow-listed testers may send.
    const auth = req.get('Authorization') || '';
    const idToken = auth.startsWith('Bearer ') ? auth.slice(7) : null;
    if (!idToken) return void res.status(401).json({ error: 'sign in first' });
    let email;
    let verified;
    const tAuth = Date.now();
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      email = decoded.email;
      verified = decoded.email_verified;
    } catch (_) {
      return void res.status(401).json({ error: 'invalid sign-in' });
    }
    mark('auth', tAuth);
    if (!isAllowed(email, parseAllowList(ALLOWED.value()), verified)) {
      return void res.status(403).json({ error: 'not a tester' });
    }

    // 2. Is the report sane?
    const problems = validateReport(req.body);
    if (problems.length) return void res.status(400).json({ error: problems.join('; ') });

    // 3. Check the daily cap and store the images at the same time: neither
    //    waits for the other, so a report takes the longer of the two.
    const day = new Date().toISOString().slice(0, 10);
    const usageRef = admin
      .firestore()
      .collection('flutterfixUsage')
      .doc(`${email.toLowerCase().replace(/[^a-z0-9]/g, '_')}_${day}`);
    const cap = parseInt(DAILY_CAP.value(), 10) || 20;
    const checkCap = async () => {
      const t0 = Date.now();
      const ok = await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(usageRef);
        const used = snap.exists ? snap.data().count : 0;
        if (used >= cap) return false;
        tx.set(usageRef, { count: used + 1, email, day });
        return true;
      });
      mark('cap', t0);
      return ok;
    };

    try {
      const token = GITHUB_TOKEN.value();
      const repo = REPO.value();
      const id = `${day.replace(/-/g, '')}-${Date.now().toString(36)}`;

      const files = [];
      if (req.body.screenshotPngBase64) {
        files.push({ key: 'shot', path: `reports/${id}.png`, base64: req.body.screenshotPngBase64 });
      }
      const strip = req.body.replay && req.body.replay.filmstripPngBase64;
      if (strip) files.push({ key: 'replay', path: `reports/${id}-replay.png`, base64: strip });

      const tFiles = Date.now();
      const [allowedNow, stored] = await Promise.all([
        checkCap(),
        files.length
          ? putFiles(token, repo, BRANCH, files, `flutterfix: images for ${id}`)
          : Promise.resolve([]),
      ]);
      mark('images', tFiles);
      if (!allowedNow) return void res.status(429).json({ error: 'daily limit reached' });

      const urlFor = (key) => {
        const i = files.findIndex((f) => f.key === key);
        return i < 0 ? null : { path: files[i].path, url: stored[i].url };
      };
      const { title, body } = buildIssue(req.body, {
        id,
        shot: urlFor('shot'),
        replayShot: urlFor('replay'),
        repo,
        branch: BRANCH,
      });
      const tIssue = Date.now();
      const issue = await createIssue(token, repo, { title, body, labels: ['flutterfix'] });
      mark('issue', tIssue);
      timings.total = Date.now() - started;
      timings.bytes = JSON.stringify(req.body).length;
      timings.cold = coldStart;
      coldStart = false;
      console.log('flutterfix timings', JSON.stringify(timings));
      res.set('Server-Timing', Object.entries(timings).filter(([k]) => k !== 'bytes' && k !== 'cold').map(([k, v]) => `${k};dur=${v}`).join(', '));
      res.status(200).json({ id: `#${issue.number}`, url: issue.url });
    } catch (e) {
      console.error('flutterfix: could not file report', e);
      res.status(502).json({ error: 'could not file the report' });
    }
  },
);
