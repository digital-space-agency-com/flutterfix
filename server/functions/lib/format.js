'use strict';

// Pure helpers: no Firebase, no network, so they can be unit tested.

const MAX_COMMENT = 2000;
const MAX_SCREENSHOT_BYTES = 6 * 1024 * 1024;

/**
 * Lower-cased list from "a@x.com, *@reelmatch.app". An entry is either one
 * address or `*@domain` to allow everyone at that domain.
 */
function parseAllowList(text) {
  return String(text || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
}

/**
 * Whether [email] may send reports. The address must be verified: Firebase
 * lets anyone sign up with an address they do not own, so an unverified
 * `x@reelmatch.app` proves nothing.
 */
function isAllowed(email, allowList, emailVerified) {
  if (!email || emailVerified !== true) return false;
  const e = String(email).trim().toLowerCase();
  const at = e.lastIndexOf('@');
  if (at < 1) return false;
  const domain = e.slice(at + 1);
  return allowList.some((entry) =>
    entry.startsWith('*@') ? entry.slice(2) === domain : entry === e,
  );
}

/** Returns a list of problems; empty means the body is usable. */
function validateReport(body) {
  const problems = [];
  if (!body || typeof body !== 'object') return ['body must be a JSON object'];
  if (typeof body.comment !== 'string' || !body.comment.trim()) {
    problems.push('comment is required');
  } else if (body.comment.length > MAX_COMMENT) {
    problems.push(`comment is longer than ${MAX_COMMENT} characters`);
  }
  if (body.screenshotPngBase64 != null) {
    if (typeof body.screenshotPngBase64 !== 'string') {
      problems.push('screenshotPngBase64 must be a string');
    } else if (body.screenshotPngBase64.length * 0.75 > MAX_SCREENSHOT_BYTES) {
      problems.push('screenshot is too large');
    }
  }
  if (body.element != null && typeof body.element !== 'object') {
    problems.push('element must be an object');
  }
  return problems;
}

function clean(text, max = 200) {
  return String(text ?? '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function list(items, max = 8) {
  return (Array.isArray(items) ? items : [])
    .slice(0, max)
    .map((t) => `\`${clean(t, 80).replace(/`/g, "'")}\``)
    .join(', ');
}

/** Issue title and body for a report. [shot] is {path, url} when a screenshot was stored. */
function buildIssue(report, { id, shot, repo, branch }) {
  const el = report.element || {};
  const comment = String(report.comment).trim();
  const label = el.name || (Array.isArray(el.texts) && el.texts[0]) || el.kind || 'element';

  const lines = [];
  lines.push(comment, '');
  lines.push('### Where');
  if (el.name) lines.push(`- **Marked element:** \`${clean(el.name)}\``);
  if (el.location) lines.push(`- **Source:** \`${clean(el.location)}\``);
  if (el.kind) lines.push(`- **Render object:** \`${clean(el.kind)}\``);
  if (el.creatorChain) lines.push(`- **Widgets:** ${clean(el.creatorChain, 400)}`);
  if (el.texts && el.texts.length) lines.push(`- **Text on it:** ${list(el.texts)}`);
  if (el.nearbyTexts && el.nearbyTexts.length) {
    lines.push(`- **Text nearby:** ${list(el.nearbyTexts)}`);
  }
  if (report.screenName) lines.push(`- **Screen:** ${clean(report.screenName)}`);
  lines.push('', '### Build');
  lines.push(`- **App version:** ${clean(report.appVersion) || 'unknown'}`);
  lines.push(`- **Platform:** ${clean(report.platform) || 'unknown'}`);
  if (Array.isArray(report.screenSize)) {
    lines.push(`- **Screen size:** ${report.screenSize.map((n) => Math.round(n)).join(' x ')}`);
  }
  const extra = report.extra && typeof report.extra === 'object' ? report.extra : {};
  for (const [k, v] of Object.entries(extra).slice(0, 8)) {
    lines.push(`- **${clean(k, 40)}:** ${clean(v, 120)}`);
  }
  if (shot) {
    lines.push('', '### Screenshot (the element is outlined in red)');
    lines.push(`![screenshot](${shot.url})`);
    lines.push('', `File: \`${shot.path}\` on branch \`${branch}\` of \`${repo}\`.`);
  }
  lines.push('', `<!-- flutterfix:v1 report=${id} -->`);

  return {
    title: `[flutterfix] ${clean(comment, 70)} (${clean(label, 40)})`,
    body: lines.join('\n'),
  };
}

module.exports = {
  MAX_COMMENT,
  MAX_SCREENSHOT_BYTES,
  parseAllowList,
  isAllowed,
  validateReport,
  buildIssue,
};
