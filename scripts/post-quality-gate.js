/**
 * PR summary comment for the Sonar-replacement quality gate (no AI).
 */
const fs = require('fs');
const path = require('path');

const AGENTIC_TMP = process.env.AGENTIC_TMP || '/tmp/agentic-quality-gate';
const COMMENT_MARKER = '<!-- agentic-quality-gate:comment -->';

function read(filePath, fallback = '') {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return fallback;
  }
}

const qualityGateMd = read(`${AGENTIC_TMP}/quality-gate.md`).trim();
let gateResult = {};
try {
  gateResult = JSON.parse(read(`${AGENTIC_TMP}/gate-result.json`, '{}'));
} catch {
  gateResult = {};
}

let buildInlineComments = () => [];
let loadFindingsBundle = () => [];
let FINDING_MARKER = '<!-- agentic-review:finding -->';
try {
  const peer = require(path.join(__dirname, 'peer-findings.js'));
  buildInlineComments = peer.buildInlineComments;
  loadFindingsBundle = peer.loadFindingsBundle;
  FINDING_MARKER = peer.FINDING_MARKER;
} catch (e) {
  console.log('peer-findings unavailable:', e.message);
}

const gateFindings = loadFindingsBundle(AGENTIC_TMP);
const inlineComments = buildInlineComments(gateFindings);

const status = gateResult.status || 'n/a';
const mode = gateResult.mode || 'advisory';
const emoji = { pass: '✅', warn: '⚠️', fail: '❌' }[status] || 'ℹ️';
const runUrl =
  process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
    : null;

const body = [
  COMMENT_MARKER,
  `## ${emoji} PR Quality Gate — \`${status}\``,
  '',
  `**Mode:** \`${mode}\` · **Blocking:** \`${gateResult.blocking ? 'yes' : 'no'}\``,
  runUrl ? `**Workflow:** [View run](${runUrl})` : '',
  '',
  qualityGateMd || '_No quality-gate.md produced._',
  '',
  '---',
  '<sub><a href="https://github.com/pulumamidi-harsha/agentic-quality-gate">agentic-quality-gate</a> · Sonar-replacement metrics (no AI)</sub>',
]
  .filter(Boolean)
  .join('\n');

module.exports = {
  body,
  COMMENT_MARKER,
  FINDING_MARKER,
  inlineComments,
  gateFindings,
  gateResult,
};
