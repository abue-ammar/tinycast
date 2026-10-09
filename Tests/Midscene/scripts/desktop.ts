import { spawn, execFileSync } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { access, cp, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { waitForOwnedWindow } from './startup.mjs';
import { agentForComputer } from '@midscene/computer';
import { stopOwnedProcess } from './process.ts';
export type DesktopAgent = Awaited<ReturnType<typeof agentForComputer>>;

export async function openCase(id: string, onTeardown: (cleanup: () => Promise<void>) => void, signal: AbortSignal): Promise<DesktopAgent> {
  if (process.platform !== 'darwin') throw new Error('Tinycast E2E requires macOS 26');
  if (process.env.MIDSCENE_DESKTOP_ENABLED !== '1') throw new Error('Set MIDSCENE_DESKTOP_ENABLED=1 on a dedicated test desktop');
  for (const key of ['MIDSCENE_MODEL_API_KEY', 'MIDSCENE_MODEL_NAME', 'MIDSCENE_MODEL_BASE_URL', 'MIDSCENE_MODEL_FAMILY']) {
    if (!process.env[key]) throw new Error(`Missing ${key}`);
  }
  const app = path.resolve(process.env.TINYCAST_APP_PATH ?? '../../build/Build/Products/Debug/Tinycast Dev.app');
  const sourcePlist = path.join(app, 'Contents/Info.plist');
  await access(sourcePlist);
  const executable = execFileSync('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleExecutable', sourcePlist], { encoding: 'utf8' }).trim();
  if (!executable || path.basename(executable) !== executable) throw new Error('Invalid app executable');
  const out = path.resolve('midscene_run');
  await mkdir(out, { recursive: true });
  const world = `midscene-${randomUUID().replaceAll('-', '').slice(0, 16)}`;
  const bundle = `com.tinycast.app.midscene.${world}`;
  const fixtureBundle = `com.tinycast.fixture.${world}`;
  const support = path.join(homedir(), 'Library/Application Support', bundle);
  const work = await mkdtemp(path.join(tmpdir(), 'tinycast-midscene-'));
  const copy = path.join(work, 'Tinycast E2E.app');
  const fixture = path.join(work, 'Applications/E2E Lantern.app');
  const ownerTool = path.join(work, 'owned-application');
  let ownerToolReady = false;
  let child: ReturnType<typeof spawn> | undefined;
  let agent: DesktopAgent | undefined;
  let startup: Record<string, unknown> = {};
  const launchLog = createWriteStream(path.join(out, `${id}-launch.log`));
  const ownedFixturePids = () => ownerToolReady
    ? JSON.parse(execFileSync(ownerTool, ['inspect', fixtureBundle, fixture], { encoding: 'utf8', timeout: 10_000 })) as number[]
    : [];

  onTeardown(async () => {
    try {
      const publicationErrors: unknown[] = [];
      try {
        await writeFile(path.join(out, `${id}-startup.json`), JSON.stringify(startup, null, 2));
        await writeFile(path.join(out, `${id}-runtime.json`), JSON.stringify({
          world, bundle, pid: child?.pid, fixtureBundle, fixturePids: ownedFixturePids(),
          support, searchScopes: [path.dirname(fixture)], startup,
        }, null, 2));
      } catch (error) { publicationErrors.push(error); }
      if (agent) {
        try {
          await writeFile(path.join(out, `${id}.png`), Buffer.from((await agent.interface.screenshotBase64()).replace(/^data:image\/\w+;base64,/, ''), 'base64'));
        } catch (error) { publicationErrors.push(error); }
        try {
          await writeFile(path.join(out, `${id}.html`), agent.reportHTMLString({ inlineScreenshots: true }));
        } catch (error) { publicationErrors.push(error); }
      }
      if (publicationErrors.length) throw new AggregateError(publicationErrors, 'Case artifact publication failed');
    } finally {
      await agent?.destroy().catch(() => undefined);
      await stopOwnedProcess(child);
      await new Promise<void>(resolve => launchLog.end(resolve));
      if (ownerToolReady) execFileSync(ownerTool, ['stop', fixtureBundle, fixture], { timeout: 15_000 });
      await rm(work, { recursive: true, force: true });
      for (const domain of [bundle, fixtureBundle]) {
        for (const folder of ['Application Support', 'Caches', 'WebKit', 'HTTPStorages']) {
          await rm(path.join(homedir(), 'Library', folder, domain), { recursive: true, force: true });
        }
        await rm(path.join(homedir(), 'Library/Saved Application State', `${domain}.savedState`), { recursive: true, force: true });
        try { execFileSync('defaults', ['delete', domain], { stdio: 'ignore' }); } catch {}
      }
      await rm(path.join(homedir(), '.config', `tinycast-midscene.${world}`), { recursive: true, force: true });
    }
  });

  await cp(app, copy, { recursive: true });
  execFileSync('/usr/libexec/PlistBuddy', ['-c', `Set :CFBundleIdentifier ${bundle}`, path.join(copy, 'Contents/Info.plist')]);
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', copy], { stdio: 'pipe' });
  await mkdir(path.join(fixture, 'Contents/MacOS'), { recursive: true });
  await writeFile(path.join(fixture, 'Contents/Info.plist'), `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>${fixtureBundle}</string><key>CFBundleName</key><string>E2E Lantern</string><key>CFBundleDisplayName</key><string>E2E Lantern</string><key>CFBundleExecutable</key><string>Lantern</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>`);
  execFileSync('xcrun', ['swiftc', '-swift-version', '6', 'fixtures/Lantern.swift', '-o', path.join(fixture, 'Contents/MacOS/Lantern')], { stdio: 'pipe' });
  execFileSync('xcrun', ['swiftc', '-swift-version', '6', 'fixtures/OwnedApplication.swift', '-o', ownerTool], { stdio: 'pipe' });
  ownerToolReady = true;
  execFileSync('codesign', ['--force', '--sign', '-', fixture], { stdio: 'pipe' });
  await mkdir(support, { recursive: true });
  await writeFile(path.join(support, 'onboarded'), '');
  for (const key of ['clipboardEnabled', 'clipboardTextSearchEnabled', 'calendarEnabled', 'snippetsEnabled', 'supportReminders', 'settingsFileEnabled', 'extensionsEnabled', 'appleShortcutsEnabled', 'aiEnabled', 'mcpEnabled', 'fileSearchEnabled', 'showInMenuBar', 'launcherShowsSuggestions']) {
    execFileSync('defaults', ['write', bundle, key, '-bool', 'false']);
  }
  execFileSync('defaults', ['write', bundle, 'launcherSearchScopes', '-array', path.dirname(fixture)]);
  execFileSync('defaults', ['write', bundle, 'appearance', '-string', 'dark']);
  const focusSource = path.join(work, 'focus.swift');
  const focusTool = path.join(work, 'focus');
  await writeFile(focusSource, `import AppKit
import ApplicationServices
import Foundation
let args = CommandLine.arguments
if args.count != 4 { exit(2) }
let pid = pid_t(args[1])!
guard let app = NSRunningApplication(processIdentifier: pid),
    app.bundleIdentifier == args[2],
    app.bundleURL?.resolvingSymlinksInPath() == URL(fileURLWithPath: args[3]).resolvingSymlinksInPath()
else { print("{}"); exit(1) }
let element = AXUIElementCreateApplication(pid)
func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
let windows = value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
var focusedPID: pid_t = 0
if let focused = value(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute),
    CFGetTypeID(focused) == AXUIElementGetTypeID() {
    AXUIElementGetPid(unsafeDowncast(focused, to: AXUIElement.self), &focusedPID)
}
let result: [String: Any] = [
    "pid": Int(pid), "active": app.isActive,
    "terminated": app.isTerminated, "windowCount": windows.count, "focusedApplicationPID": Int(focusedPID),
    "windows": windows.map { window in [
        "title": value(window, kAXTitleAttribute) as? String ?? "",
        "role": value(window, kAXRoleAttribute) as? String ?? "",
        "focused": value(window, kAXFocusedAttribute) as? Bool ?? false
    ] as [String: Any] }
]
let data = try JSONSerialization.data(withJSONObject: result)
print(String(decoding: data, as: UTF8.self))
`);
  execFileSync('xcrun', ['swiftc', '-swift-version', '6', focusSource, '-o', focusTool], { stdio: 'pipe' });
  agent = await agentForComputer({
    generateReport: true, reportFileName: id, autoPrintReportMsg: false, replanningCycleLimit: 12,
    aiContexts: { default: 'You are testing an isolated Tinycast native macOS launcher palette with English text. Operate only the visible Tinycast palette and its E2E Lantern fixture application. Never use Dock, Spotlight, global hotkeys, external websites, clipboard copy/paste, or any other app. Do not quit or relaunch Tinycast. If the test palette is unavailable, report failure.' },
  });
  const appEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('MIDSCENE_')));
  child = spawn(path.join(copy, 'Contents/MacOS', executable), ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US'], {
    env: { ...appEnv, TINYCAST_E2E_VISIBLE: '1' }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout?.pipe(launchLog, { end: false });
  child.stderr?.pipe(launchLog, { end: false });
  let launchError: Error | undefined;
  child.on('error', error => { launchError = error; });
  startup = await waitForOwnedWindow({
    pid: child.pid!,
    inspect: () => {
      if (launchError) throw launchError;
      if (child!.exitCode !== null || child!.signalCode !== null || signal.aborted) throw new Error('Tinycast exited before readiness');
      return JSON.parse(execFileSync(focusTool, [String(child!.pid), bundle, copy], {
        encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'pipe'],
      })) as Record<string, unknown>;
    },
    raise: () => {
      execFileSync('osascript', ['-e', `tell application "System Events"
        tell (first process whose unix id is ${child!.pid})
          set frontmost to true
          if (count of windows) > 0 then
            perform action "AXRaise" of window 1
          end if
        end tell
      end tell`], { encoding: 'utf8', timeout: 3000, stdio: ['ignore', 'pipe', 'pipe'] });
    },
  });
  await writeFile(path.join(out, `${id}-startup.json`), JSON.stringify(startup, null, 2));
  if (!startup.ready) {
    if (child.pid && child.exitCode === null && child.signalCode === null) {
      try {
        execFileSync('/usr/bin/sample', [String(child.pid), '2', '-file', path.join(out, `${id}-startup-sample.txt`)], {
          timeout: 8000, stdio: ['ignore', 'pipe', 'pipe'],
        });
      } catch (error) { startup.sampleError = String(error); }
    }
    throw new Error('Could not confirm the owned Tinycast palette has a visible window and keyboard focus; see startup diagnostics');
  }
  return agent;
}
