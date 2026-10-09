import { ComputerDevice, checkComputerEnvironment, checkAccessibilityPermission, checkScreenRecordingPermission } from '@midscene/computer';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';

// No model credentials: establish whether a hosted runner can drive a desktop.
const out = 'desktop-health';
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
const checks: Record<string, unknown> = {};
const device = new ComputerDevice();
let failed = false;
for (const [name, check] of Object.entries({
  environment: () => checkComputerEnvironment(),
  accessibility: () => checkAccessibilityPermission(false),
  screenRecording: () => checkScreenRecordingPermission(false),
})) {
  try { checks[name] = await check(); }
  catch (error) { checks[name] = String(error); failed = true; }
}
try {
  execFileSync('osascript', ['-e', 'tell application "System Events" to get count of processes'], { timeout: 15000 });
  checks.systemEvents = 'passed';
} catch (error) {
  checks.systemEvents = String(error);
  failed = true;
}
try {
  // connect() performs the SDK screenshot and pointer movement health check.
  await device.connect();
  checks.sdkHealth = 'passed';
  checks.size = await device.size();
  await writeFile(`${out}/desktop.png`, Buffer.from((await device.screenshotBase64()).replace(/^data:image\/\w+;base64,/, ''), 'base64'));
} catch (error) {
  checks.sdkHealth = String(error);
  failed = true;
} finally {
  await device.destroy();
  await writeFile(`${out}/checks.json`, JSON.stringify(checks, null, 2));
  await writeFile(`${out}/summary.md`, `### Hosted macOS desktop capability\n\n\`\`\`json\n${JSON.stringify(checks, null, 2)}\n\`\`\`\n`);
  console.log(JSON.stringify(checks, null, 2));
}
if (failed) process.exitCode = 1;
