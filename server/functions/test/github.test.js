'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { putFiles } = require('../lib/github');

// A stand-in for the two GitHub calls putFiles makes: look up the branch head,
// then commit with GraphQL.
function fakeGithub({ graphql = [{ status: 200, json: { data: { createCommitOnBranch: { commit: { oid: 'c1' } } } } }], refStatus = 200 } = {}) {
  const calls = [];
  const sent = [];
  let g = 0;
  const reply = (status, json) => ({ status, text: async () => JSON.stringify(json) });
  global.fetch = async (url, opts = {}) => {
    const method = opts.method || 'GET';
    const path = url.replace('https://api.github.com', '');
    calls.push(`${method} ${path}`);
    if (method === 'GET' && path.includes('/git/ref/heads/')) return reply(refStatus, { object: { sha: `head${calls.length}` } });
    if (method === 'POST' && path === '/graphql') {
      sent.push(JSON.parse(opts.body));
      const r = graphql[Math.min(g++, graphql.length - 1)];
      return reply(r.status, r.json);
    }
    return reply(500, {});
  };
  return { calls, sent };
}

const files = [
  { path: 'reports/a.png', base64: 'QQ==' },
  { path: 'reports/a-replay.png', base64: 'Qg==' },
];

test('both images go up in one commit using just two calls', async () => {
  const { calls, sent } = fakeGithub();
  const out = await putFiles('t', 'o/r', 'flutterfix-reports', files, 'msg');
  assert.deepEqual(out.map((f) => f.path), ['reports/a.png', 'reports/a-replay.png']);
  assert.match(out[0].url, /^https:\/\/github\.com\/o\/r\/blob\/flutterfix-reports\/reports\/a\.png\?raw=true$/);
  assert.equal(calls.length, 2, 'one branch lookup and one commit');
  const input = sent[0].variables.input;
  assert.equal(input.branch.branchName, 'flutterfix-reports');
  assert.equal(input.branch.repositoryNameWithOwner, 'o/r');
  assert.equal(input.expectedHeadOid, 'head1');
  assert.deepEqual(input.fileChanges.additions, [
    { path: 'reports/a.png', contents: 'QQ==' },
    { path: 'reports/a-replay.png', contents: 'Qg==' },
  ]);
});

test('if another report moves the branch first, it looks again and succeeds', async () => {
  const stale = { status: 200, json: { errors: [{ message: 'Expected branch to point to "head1" but it did not.' }] } };
  const ok = { status: 200, json: { data: { createCommitOnBranch: { commit: { oid: 'c2' } } } } };
  const { calls, sent } = fakeGithub({ graphql: [stale, ok] });
  const out = await putFiles('t', 'o/r', 'b', files, 'msg');
  assert.equal(out.length, 2);
  assert.equal(calls.filter((c) => c.includes('/git/ref/heads/')).length, 2);
  assert.notEqual(sent[0].variables.input.expectedHeadOid, sent[1].variables.input.expectedHeadOid);
});

test('a real error is reported, not retried forever', async () => {
  const bad = { status: 200, json: { errors: [{ message: 'Resource not accessible by personal access token' }] } };
  const { calls } = fakeGithub({ graphql: [bad] });
  await assert.rejects(putFiles('t', 'o/r', 'b', files, 'msg'), /GitHub commit failed/);
  assert.equal(calls.length, 2, 'no retry for a permission error');
});

test('it gives up after repeated branch conflicts', async () => {
  const stale = { status: 200, json: { errors: [{ message: 'Expected branch to point to "x" but it did not.' }] } };
  fakeGithub({ graphql: [stale] });
  await assert.rejects(putFiles('t', 'o/r', 'b', files, 'msg'), /GitHub commit failed/);
});
