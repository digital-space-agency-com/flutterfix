'use strict';

const API = 'https://api.github.com';

function headers(token) {
  return {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'flutterfix-functions',
  };
}

async function gh(token, method, path, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { ...headers(token), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    /* leave null */
  }
  return { status: res.status, json };
}

/** Makes sure [branch] exists, created from the default branch. */
async function ensureBranch(token, repo, branch) {
  const found = await gh(token, 'GET', `/repos/${repo}/git/ref/heads/${branch}`);
  if (found.status === 200) return;
  if (found.status !== 404) throw new Error(`GitHub branch lookup failed (${found.status})`);
  const info = await gh(token, 'GET', `/repos/${repo}`);
  if (info.status !== 200) throw new Error(`GitHub repo lookup failed (${info.status})`);
  const base = await gh(
    token,
    'GET',
    `/repos/${repo}/git/ref/heads/${info.json.default_branch}`,
  );
  if (base.status !== 200) throw new Error(`GitHub base lookup failed (${base.status})`);
  const made = await gh(token, 'POST', `/repos/${repo}/git/refs`, {
    ref: `refs/heads/${branch}`,
    sha: base.json.object.sha,
  });
  if (made.status !== 201 && made.status !== 422) {
    throw new Error(`GitHub branch create failed (${made.status})`);
  }
}

/** Stores a PNG on [branch]; returns {path, url}. */
async function putScreenshot(token, repo, branch, id, base64) {
  await ensureBranch(token, repo, branch);
  const path = `reports/${id}.png`;
  const res = await gh(token, 'PUT', `/repos/${repo}/contents/${path}`, {
    message: `flutterfix: screenshot for ${id}`,
    content: base64,
    branch,
  });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`GitHub screenshot upload failed (${res.status})`);
  }
  return { path, url: `https://github.com/${repo}/blob/${branch}/${path}?raw=true` };
}

async function createIssue(token, repo, { title, body, labels }) {
  const res = await gh(token, 'POST', `/repos/${repo}/issues`, { title, body, labels });
  if (res.status !== 201) throw new Error(`GitHub issue create failed (${res.status})`);
  return { number: res.json.number, url: res.json.html_url };
}

/**
 * Stores several files on [branch] in ONE commit with a single GraphQL call
 * (createCommitOnBranch): one lookup of the branch head plus one commit, instead
 * of a blob, tree, commit and ref call per step. [files] is [{ path, base64 }].
 * Returns [{ path, url }] in the same order. If another report moved the branch
 * between our lookup and our commit, it looks again and retries.
 */
async function putFiles(token, repo, branch, files, message) {
  const mutation = `mutation($input: CreateCommitOnBranchInput!) {
    createCommitOnBranch(input: $input) { commit { oid } }
  }`;
  for (let attempt = 0; attempt < 3; attempt++) {
    let ref = await gh(token, 'GET', `/repos/${repo}/git/ref/heads/${branch}`);
    if (ref.status === 404) {
      await ensureBranch(token, repo, branch); // first report ever: create the branch
      ref = await gh(token, 'GET', `/repos/${repo}/git/ref/heads/${branch}`);
    }
    if (ref.status !== 200) throw new Error(`GitHub ref lookup failed (${ref.status})`);

    const res = await gh(token, 'POST', '/graphql', {
      query: mutation,
      variables: {
        input: {
          branch: { repositoryNameWithOwner: repo, branchName: branch },
          message: { headline: message },
          expectedHeadOid: ref.json.object.sha,
          fileChanges: { additions: files.map((f) => ({ path: f.path, contents: f.base64 })) },
        },
      },
    });
    const errors = res.json && res.json.errors;
    if (res.status === 200 && !errors && res.json.data && res.json.data.createCommitOnBranch) {
      return files.map((f) => ({
        path: f.path,
        url: `https://github.com/${repo}/blob/${branch}/${f.path}?raw=true`,
      }));
    }
    const text = JSON.stringify(errors || res.json || {});
    // The branch moved under us (another report): go round again from the new head.
    if (/expected branch to point|expectedHeadOid|stale/i.test(text) && attempt < 2) continue;
    throw new Error(`GitHub commit failed (${res.status}) ${text.slice(0, 200)}`);
  }
  throw new Error('GitHub commit kept conflicting');
}

module.exports = { putScreenshot, putFiles, createIssue };
