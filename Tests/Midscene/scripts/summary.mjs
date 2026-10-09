import { readFile, access } from 'node:fs/promises';
import path from 'node:path';

const cell = value => String(value ?? '').replaceAll('\\', '\\\\').replaceAll('|', '\\|').replaceAll('[', '\\[').replaceAll(']', '\\]').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replace(/[\r\n]+/g, ' ');
const html = value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;').replaceAll('|', '&#124;').replace(/[\r\n]+/g, ' ');
const duration = milliseconds => {
  if (!Number.isFinite(milliseconds) || milliseconds < 0) return '—';
  const seconds = Math.round(milliseconds / 1000);
  return seconds >= 60 ? `${Math.floor(seconds / 60)}m ${seconds % 60}s` : `${seconds}s`;
};
export const safeReason = value => String(value ?? '').replace(/Bearer\s+[^\s"']+/gi, 'Bearer [redacted]').replace(/((?:api[_-]?key|authorization)\s*[:=]\s*)[^\s,;]+/gi, '$1[redacted]').replace(/[\r\n]+/g, ' ').slice(0, 320);
export const artifactUrl = (baseUrl, directory, file) => `${baseUrl.replace(/\/$/, '')}/${path.relative(directory, file).split(path.sep).map(encodeURIComponent).join('/')}`;
export function nativeDumps(source, type) {
  const dumps = [];
  const expression = new RegExp(`<script\\s+[^>]*\\btype=["']${type}["'][^>]*>\\s*(\\{[\\s\\S]*?)<\\/script>`, 'g');
  for (const match of source.matchAll(expression)) {
    let inside = false, escaped = false, normalized = '';
    for (const character of match[1]) {
      if (!inside) { normalized += character; if (character === '"') inside = true; }
      else if (escaped) { normalized += character; escaped = false; }
      else if (character === '\\') { normalized += character; escaped = true; }
      else if (character === '"') { normalized += character; inside = false; }
      else normalized += character.charCodeAt(0) <= 0x1f ? `\\u${character.charCodeAt(0).toString(16).padStart(4, '0')}` : character;
    }
    dumps.push(JSON.parse(normalized));
  }
  return dumps;
}
export async function evidenceFor(file, id, passed, directory) {
  const source = await readFile(file, 'utf8');
  const runs = nativeDumps(source, 'midscene_test_run_dump');
  const testCase = runs.flatMap(run => run.projects ?? []).flatMap(project => project.documents ?? []).flatMap(document => document.cases ?? []).find(c => c.name === id);
  if (!testCase) return null;
  const attempt = testCase.attempts?.at(-1);
  const steps = [...(attempt?.beforeEach ?? []), ...(attempt?.steps ?? []), ...(attempt?.afterEach ?? [])];
  const hasDetails = step => step.agentDetails?.length;
  const step = passed ? steps.findLast(hasDetails) : steps.find(item => item.status === 'failed' && hasDetails(item)) ?? steps.find(item => item.status === 'failed') ?? steps.findLast(hasDetails);
  const failed = steps.findLast(item => item.status === 'failed') ?? attempt;
  const reason = safeReason(failed?.error?.message ?? failed?.error ?? failed?.output?.summary);
  const dumps = nativeDumps(source, 'midscene_web_dump');
  let screenshot;
  for (const detail of [...(step?.agentDetails ?? [])].reverse()) {
    for (const dump of dumps) {
      const execution = dump.executions?.find(item => item.id === detail.executionId);
      const reference = execution?.tasks?.findLast(task => task.uiContext?.screenshot?.path)?.uiContext.screenshot;
      if (!reference?.path) continue;
      const candidate = path.resolve(path.dirname(file), reference.path);
      const relative = path.relative(directory, candidate);
      if (relative.startsWith('..') || path.isAbsolute(relative)) continue;
      try { await access(candidate); screenshot = candidate; } catch {}
      if (screenshot) break;
    }
    if (screenshot) break;
  }
  return { report: file, stepId: step?.id, screenshot, reason, durationMs: attempt?.durationMs, status: testCase.status };
}
export function renderSummary({ product = 'Tinycast', cases, models = [], runUrl = '', nativeReportUrl, nativeReportAvailable = Boolean(nativeReportUrl), issues = [], producerResult = 'success', reportResult, publicationResult, sourceRunId }) {
  const failures = cases.filter(c => c.status !== 'passed');
  const passed = cases.filter(c => c.status === 'passed');
  const infrastructure = [...issues];
  if (!cases.length) infrastructure.push('No cases were reported');
  if (producerResult !== 'success' && !failures.length) infrastructure.push(`Workflow ${producerResult}; inspect shard job logs`);
  const attention = failures.length + infrastructure.length;
  const complete = cases.length > 0 && attention === 0;
  const row = c => {
    const reportAvailable = Boolean(c.reportUrl);
    const name = reportAvailable ? `[${cell(c.title)}](${c.reportUrl})` : cell(c.title);
    const screenshot = reportAvailable && c.screenshotUrl ? `<a href="${html(c.reportUrl)}"><img src="${html(c.screenshotUrl)}" alt="${html(c.title)}" width="160"></a>` : '—';
    const status = c.status === 'passed' ? '✅ Passed' : c.status === 'not-run' ? '⏭️ Not run' : c.status === 'missing' ? '⚠️ Missing' : c.status === 'incomplete' ? '⚠️ Incomplete' : '❌ Failed';
    return `| ${cell(c.shard)} | ${name} | ${reportAvailable ? `[Report](${c.reportUrl})` : '—'} | ${screenshot} | ${cell(`${status}${c.reason ? `: ${safeReason(c.reason)}` : ''}`)} | ${duration(c.durationMs)} |`;
  };
  const lines = [`## ${product} × Midscene · ${complete ? 'passed' : 'failure captured'}`, '', `**${complete ? '✅ ' : ''}${attention} need attention · ${passed.length} passed**`, '', `**Models:** ${models.length ? models.map(cell).join(', ') : 'not recorded'}`, ''];
  const nativeLink = nativeReportUrl ? `**[Open the Midscene Test report](${nativeReportUrl})**` : nativeReportAvailable ? 'Native Midscene Test report included in the artifact.' : 'Native Midscene report unavailable; individual case reports remain available.';
  lines.push(`${nativeLink}${runUrl ? ` · [Download the artifact](${runUrl}#artifacts)` : ''}`, '');
  if (sourceRunId && /^\d+$/.test(sourceRunId)) {
    const sourceUrl = runUrl.replace(/\/\d+$/, `/${sourceRunId}`);
    lines.push(`Report source: [run ${sourceRunId}](${sourceUrl}). This run makes no new model calls. [Source-run artifacts](${sourceUrl}#artifacts).`, '');
  }
  if (reportResult) lines.push(`Report aggregation: **${cell(reportResult)}**.`, '');
  if (publicationResult) lines.push(`Pages publication: **${cell(publicationResult)}**.${nativeReportUrl ? '' : ' Web report links are unavailable; download the available artifacts.'}`, '');
  if (!cases.some(c => c.reportUrl)) {
    lines.push('Download the report artifact to inspect native HTML reports and screenshots.', '');
    for (const issue of infrastructure) lines.push(`- ${cell(safeReason(issue))}`);
    for (const failure of failures) lines.push(`- ${cell(failure.title)}: ${cell(failure.status === 'missing' ? 'Missing' : failure.status)}${failure.reason ? `: ${cell(safeReason(failure.reason))}` : ''}`);
    return lines.join('\n');
  }
  const shards = [...new Set(cases.map(c => c.shard))];
  lines.push('### Shard results', '', '| Shard | Passed | Needs attention |', '|:--|--:|--:|', ...shards.map(shard => {
    const results = cases.filter(c => c.shard === shard);
    return `| ${cell(shard)} | ${results.filter(c => c.status === 'passed').length} | ${results.filter(c => c.status !== 'passed').length} |`;
  }), '');
  if (attention) {
    lines.push('### Needs attention', '', '| Shard | Case | Report | Screenshot | Status / reason | Duration |', '|:--|:--|:--|:--|:--|--:|', ...infrastructure.map(issue => `| Workflow | — | — | — | ❌ ${cell(safeReason(issue))} | — |`), ...failures.sort((a, b) => Number(a.status === 'not-run') - Number(b.status === 'not-run')).map(row), '');
  } else lines.push(`🎉 All ${passed.length} cases passed.`, '');
  lines.push('<details>', `<summary>Appendix: passed cases (${passed.length})</summary>`, '', '| Shard | Case | Report | Screenshot | Status | Duration |', '|:--|:--|:--|:--|:--|--:|', ...passed.map(row), '', '</details>', '', 'Click a screenshot or case name to open its native report; framework reports open the recorded step.', '');
  return lines.join('\n');
}
