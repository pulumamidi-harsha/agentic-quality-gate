/**
 * Compact PR summary for the Sonar-replacement quality gate (no AI).
 * Details live on peer-style line comments only — no duplicate issues table.
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
const n = inlineComments.length;

const body = [
  COMMENT_MARKER,
  n > 0
    ? `Quality gate posted **${n}** line comment(s). Details are on the exact lines in **Files changed**.`
    : 'Quality gate posted **0** line comment(s).',
  '',
  qualityGateMd || '_No quality-gate.md produced._',
]
  .filter((line, i, arr) => !(line === '' && arr[i - 1] === ''))
  .join('\n');

module.exports = {
  body,
  COMMENT_MARKER,
  FINDING_MARKER,
  inlineComments,
  gateFindings,
  gateResult,
};
