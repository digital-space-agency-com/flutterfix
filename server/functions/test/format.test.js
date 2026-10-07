'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseAllowList, isAllowed, validateReport, buildIssue } = require('../lib/format');

const report = {
  comment: 'Number is too small',
  element: {
    name: 'card.number',
    location: 'lib/card.dart:12',
    kind: 'RenderParagraph',
    texts: ['4242'],
    nearbyTexts: ['Alex'],
    creatorChain: 'Text ← Row',
  },
  screenName: 'Wallet',
  appVersion: '1.0.0+1',
  platform: 'iOS',
  screenSize: [390, 844],
  extra: { flavor: 'internal' },
};

test('allow list is case and space insensitive', () => {
  const list = parseAllowList(' Dave@X.com , b@y.com ,, ');
  assert.deepEqual(list, ['dave@x.com', 'b@y.com']);
  assert.equal(isAllowed('DAVE@x.com', list, true), true);
  assert.equal(isAllowed('eve@z.com', list, true), false);
  assert.equal(isAllowed(undefined, list, true), false);
  assert.equal(isAllowed('a@b.com', [], true), false);
});

test('a domain entry allows everyone at that domain, and only that domain', () => {
  const list = parseAllowList('*@reelmatch.app');
  assert.equal(isAllowed('hey@reelmatch.app', list, true), true);
  assert.equal(isAllowed('hey+iOS@ReelMatch.app', list, true), true);
  assert.equal(isAllowed('hey@evil-reelmatch.app', list, true), false);
  assert.equal(isAllowed('hey@reelmatch.app.evil.com', list, true), false);
  assert.equal(isAllowed('hey@sub.reelmatch.app', list, true), false);
  assert.equal(isAllowed('reelmatch.app', list, true), false);
});

test('an unverified address is never allowed', () => {
  assert.equal(isAllowed('hey@reelmatch.app', ['*@reelmatch.app'], false), false);
  assert.equal(isAllowed('hey@reelmatch.app', ['*@reelmatch.app'], undefined), false);
  assert.equal(isAllowed('a@b.com', ['a@b.com'], false), false);
});

test('validateReport accepts a normal report and rejects bad ones', () => {
  assert.deepEqual(validateReport(report), []);
  assert.ok(validateReport({}).length > 0);
  assert.ok(validateReport(null).length > 0);
  assert.ok(validateReport({ comment: 'x'.repeat(2001) }).length > 0);
  assert.ok(validateReport({ comment: 'hi', element: 'nope' }).length > 0);
  assert.ok(
    validateReport({ comment: 'hi', screenshotPngBase64: 'A'.repeat(9 * 1024 * 1024) }).length > 0,
  );
});

test('issue leads with the comment and names the element and source', () => {
  const { title, body } = buildIssue(report, {
    id: 'r1',
    repo: 'org/app',
    branch: 'flutterfix-reports',
    shot: { path: 'reports/r1.png', url: 'https://github.com/org/app/blob/b/reports/r1.png?raw=true' },
  });
  assert.match(title, /^\[flutterfix\] Number is too small \(card\.number\)$/);
  assert.ok(body.startsWith('Number is too small'));
  assert.match(body, /`card\.number`/);
  assert.match(body, /`lib\/card\.dart:12`/);
  assert.match(body, /!\[screenshot\]\(https:\/\/github\.com\/org\/app/);
  assert.match(body, /<!-- flutterfix:v1 report=r1 -->/);
  assert.match(body, /\*\*flavor:\*\* internal/);
});

test('issue works without an element or screenshot, and tidies awkward text', () => {
  const { title, body } = buildIssue(
    { comment: 'multi\nline   comment', element: { texts: ['a`b'] } },
    { id: 'r2', repo: 'org/app', branch: 'b' },
  );
  assert.match(title, /multi line comment/);
  assert.doesNotMatch(body, /Screenshot/);
  assert.match(body, /`a'b`/);
});

test('titles are capped', () => {
  const { title } = buildIssue({ comment: 'z'.repeat(500) }, { id: 'r3', repo: 'o/a', branch: 'b' });
  assert.ok(title.length < 140);
});
