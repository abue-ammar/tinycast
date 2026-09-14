// Self-contained checks for the embedded runtime: each fixture is a tiny extension command compiled
// with esbuild exactly the way a real one is (CJS, JSX automatic, @raycast/api + react external).
//
//   node fixtures.mjs

import { createHarness, bootConfig, describeTree } from "./test.mjs";
import { transformSync } from "esbuild";

let passes = 0;
let failures = 0;

function check(label, condition, extra = "") {
  if (condition) {
    passes++;
    console.log(`  ✓ ${label}`);
  } else {
    failures++;
    console.log(`  ✗ ${label}${extra ? ` — ${extra}` : ""}`);
  }
}

function compile(source) {
  const { code } = transformSync(source, {
    loader: "jsx",
    jsx: "automatic",
    jsxImportSource: "react",
    format: "cjs",
    target: "es2022",
  });
  return code;
}

const wait = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));

async function run(name, source, mode, verify, options) {
  console.log(`\n▶ ${name}`);
  const harness = createHarness(options);
  harness.boot(bootConfig());
  const code = compile(source);
  harness.start("s1", code, "/fixtures/cmd.js", "/fixtures", mode, {});
  await wait();
  await verify(harness);
  harness.stop("s1");
}

// ─── Fixtures ────────────────────────────────────────────────────────

const listSource = `
import { List, ActionPanel, Action, Icon } from "@raycast/api";
import { useState } from "react";

export default function Command() {
  const [count, setCount] = useState(0);
  return (
    <List
      searchBarPlaceholder="Search…"
      searchBarAccessory={
        <List.Dropdown tooltip="Filter" onChange={() => {}}>
          <List.Dropdown.Item title="All" value="all" />
          <List.Dropdown.Item title="Active" value="active" />
        </List.Dropdown>
      }
    >
      <List.Section title="Main">
        <List.Item
          id="item-1"
          title={"Count is " + count}
          accessories={[{ text: "Tag" }, { icon: Icon.Star }]}
          actions={
            <ActionPanel>
              <Action title="Bump" onAction={() => setCount((c) => c + 1)} />
            </ActionPanel>
          }
        />
      </List.Section>
    </List>
  );
}
`;

const detailSource = `
import { Detail } from "@raycast/api";

export default function Command() {
  return (
    <Detail
      markdown="# Hello world"
      metadata={
        <Detail.Metadata>
          <Detail.Metadata.Label title="Author" text="Ada" />
          <Detail.Metadata.Separator />
          <Detail.Metadata.TagList title="Tags">
            <Detail.Metadata.TagList.Item text="fast" color="#00ff00" />
          </Detail.Metadata.TagList>
          <Detail.Metadata.Link title="Link" target="https://example.com" text="Home" />
        </Detail.Metadata>
      }
    />
  );
}
`;

const fragmentDetailSource = `
import { List } from "@raycast/api";

export default function Command() {
  return (
    <List>
      <List.Item
        title="TOTP"
        detail={
          <>
            <List.Item.Detail markdown="30s remaining" />
            <List.Item.Detail metadata={<List.Item.Detail.Metadata><List.Item.Detail.Metadata.Label title="Code" text="123456" /></List.Item.Detail.Metadata>} />
          </>
        }
      />
    </List>
  );
}
`;

const formSource = `
import { Form, ActionPanel, Action } from "@raycast/api";

export default function Command() {
  return (
    <Form actions={<ActionPanel><Action.SubmitForm title="Save" onSubmit={(values) => { globalThis.__submitted = values; }} /></ActionPanel>}>
      <Form.TextField id="name" title="Name" defaultValue="Ada" />
      <Form.TextArea id="bio" title="Bio" defaultValue="" />
      <Form.Checkbox id="agree" label="I agree" defaultValue={true} />
      <Form.Dropdown id="role" title="Role" defaultValue="dev">
        <Form.Dropdown.Item value="dev" title="Developer" />
      </Form.Dropdown>
      <Form.TagPicker id="tags" title="Tags" defaultValue={["swift"]}>
        <Form.TagPicker.Item value="swift" title="Swift" />
      </Form.TagPicker>
      <Form.DatePicker id="when" title="When" defaultValue={new Date("2026-04-18T10:00:00Z")} />
      <Form.Separator />
      <Form.Description title="Info" text="All fields are saved locally." />
    </Form>
  );
}
`;

const navigationSource = `
import { List, ActionPanel, Action, useNavigation, Detail } from "@raycast/api";

function Subscreen() {
  return <Detail markdown="# Subscreen" />;
}

export default function Command() {
  const { push } = useNavigation();
  return (
    <List>
      <List.Item
        title="Push"
        actions={
          <ActionPanel>
            <Action title="Open subscreen" onAction={() => push(<Subscreen />)} />
          </ActionPanel>
        }
      />
    </List>
  );
}
`;

const nodeSource = `
import path from "node:path";
import os from "node:os";
import fs from "node:fs";
import crypto from "node:crypto";
import { Buffer } from "node:buffer";
import { fileURLToPath, pathToFileURL } from "node:url";
import { Detail } from "@raycast/api";

export default function Command() {
  const errorCode = (fn) => {
    try {
      fn();
      return "none";
    } catch (error) {
      return error.code ?? error.name;
    }
  };
  const cpu = os.cpus()[0];
  const parts = [
    path.join("/a/b", "../c", "d.txt"),
    path.extname("x/y/file.tar.gz"),
    path.basename("/a/b/c.md", ".md"),
    os.platform(),
    Object.keys(cpu.times).sort().join(","),
    String(Object.values(cpu.times).every(Number.isFinite)),
    String(os.freemem() > 0),
    String(os.uptime() > 0),
    String(os.loadavg().length === 3 && os.loadavg().every(Number.isFinite)),
    new URL("/next?q=1", "https://example.com/base/page").href,
    new URLSearchParams({ a: "1", b: "two words" }).toString(),
    crypto.createHash("sha256").update("abc").digest("hex").slice(0, 8),
    Buffer.from("hello").toString("base64"),
    Buffer.from("aGVsbG8=", "base64").toString("utf8"),
    new TextDecoder().decode(new TextEncoder().encode("héllo")),
    fileURLToPath("file:///Applications/Tinycast%20Beta.app"),
    fileURLToPath(new URL("file:///tmp/%ED%95%9C%EA%B8%80.txt")),
    fileURLToPath("file://localhost/tmp/a?query=ignored#fragment"),
    fileURLToPath("file:///tmp/a%5Cb"),
    fileURLToPath("file:tmp/a"),
    fileURLToPath("file:///tmp/%2e%2e/a"),
    fileURLToPath("file://%6cocalhost/tmp/a"),
    fileURLToPath("file:///tmp//a"),
    fileURLToPath(new URL("file:///tmp/a///b")),
    fileURLToPath("file:///tmp/a//../b"),
    fileURLToPath("file:///C:/.."),
    new URL(
      "file:///tmp/a?query=" +
        String.fromCharCode(92) +
        "keep#fragment=" +
        String.fromCharCode(92) +
        "keep",
    ).href,
    new URL("https://example.com/C:/..").href,
    fileURLToPath("file:///a:folder/.."),
    new URL("..", "file:///a:folder/child").href,
    new URL("..", "https://example.com/C:/child").href,
    pathToFileURL("/tmp/My Image.png").href,
    pathToFileURL("/tmp/a#b.png").href,
    fileURLToPath(pathToFileURL("/tmp/a#b.png")),
    fileURLToPath(pathToFileURL("/tmp/a?b.png")),
    fileURLToPath(pathToFileURL("/Applications/Tinycast Beta.app")),
    errorCode(() => fileURLToPath("file:///tmp/a%2Fb")),
    errorCode(() => fileURLToPath("file://a%2Fb/tmp/a")),
    errorCode(() => fileURLToPath("file://example.com/tmp/a")),
    errorCode(() => fileURLToPath("https://example.com/a")),
    errorCode(() => fileURLToPath({})),
    errorCode(() => fileURLToPath("file://user@localhost/tmp/a")),
    errorCode(() => fileURLToPath("file://localhost:/tmp/a")),
    errorCode(() => fileURLToPath("file:///C:/a", { windows: true })),
    // fs validates URL schemes the way Node does: a vscode-remote:// workspace URI whose stripped
    // pathname exists locally ("/" always does) must not pass existsSync — Raycast's Search Recent
    // Projects relies on that guard before handing the URI to fileURLToPath.
    String(fs.existsSync(new URL("vscode-remote://ssh-remote%2Bucg/"))),
    String(fs.existsSync(new URL("vscode-remote://ssh-remote%2Bserver/etc/docker/daemon.json"))),
    String(fs.existsSync(new URL("file:///etc/hosts"))),
    String(fs.existsSync("/etc/hosts")),
    errorCode(() => fs.statSync(new URL("https://example.com/a"))),
    errorCode(() => fs.readFileSync(new URL("https://example.com/a"))),
  ];
  return <Detail markdown={parts.join("\\n")} />;
}
`;

// Bundled HTTP clients (axios) construct and probe a Response at module scope, before any component
// mounts — a host-shaped constructor took the whole command down with them.
const responseSource = `
export default async function Command() {
  const probe = new Response();
  const created = new Response(JSON.stringify({ id: 7 }), {
    status: 201,
    statusText: "Created",
    headers: { "Content-Type": "application/json" },
  });
  const clone = created.clone();
  const abort = new DOMException("stopped", "AbortError");
  const blob = new Blob(["hello", new Uint8Array([33])], { type: "Text/Plain" });
  const slice = blob.slice(1, 4, "Application/Test");
  const responseBlob = await new Response("hi", { headers: { "Content-Type": "text/custom" } }).blob();
  globalThis.__response = {
    probe: [probe.status, probe.ok, probe.statusText, await probe.text()],
    readers: ["text", "arrayBuffer", "blob"].every((name) => typeof probe[name] === "function"),
    created: [created.status, created.statusText, created.headers.get("content-type"), (await created.json()).id],
    clone: [clone.status, clone.headers.get("content-type"), await clone.text()],
    bytes: Array.from(await new Response(new Uint8Array([104, 105])).bytes()),
    byteLength: (await new Response("héllo").arrayBuffer()).byteLength,
    blob: [blob.size, blob.type, await blob.text(), Array.from(await blob.bytes()).join(",")],
    slice: [slice.size, slice.type, await slice.text(), await new Response(blob).text()],
    responseBlob: [responseBlob.size, responseBlob.type, await responseBlob.text()],
    domException: [abort.name, abort.message, abort instanceof Error, abort instanceof DOMException, new DOMException().name],
  };
}
`;

// gaxios reaches for `FormData` on every request, so it has to exist; and a form that exists but
// serialises to nothing would be worse than one that is absent, so the body has to be real too.
const formDataSource = `
export default async function Command() {
  const form = new FormData();
  form.append("name", "Ada");
  form.append("tag", "one");
  form.append("tag", "two");
  form.append("file", new Blob(["hi"], { type: "Text/Plain" }), "note.txt");
  form.append("blobless", new Blob(["x"]));
  const shape = {
    get: form.get("tag"),
    getAll: form.getAll("tag"),
    has: [form.has("name"), form.has("missing")],
    entryNames: Array.from(form.keys()),
    file: [form.get("file").name, form.get("file").type, await form.get("file").text()],
    defaultName: form.get("blobless").name,
    isFile: form.get("file") instanceof File,
  };
  form.set("tag", "only");
  form.delete("blobless");
  shape.afterSet = Array.from(form.keys());
  shape.afterSetValue = form.getAll("tag");

  await fetch("https://example.test/upload", { method: "POST", body: form });
  const explicit = new FormData();
  explicit.append("a", "1");
  await fetch("https://example.test/upload", { method: "POST", body: explicit, headers: { "Content-Type": "text/custom" } });
  globalThis.__form = shape;
}
`;

// A URLSearchParams body sets no header of its own, so the spec's derived Content-Type is the only
// thing an OAuth token endpoint has: without it Google reads the form body as JSON and rejects it.
const contentTypeSource = `
export default async function Command() {
  const url = "https://example.test/token";
  const send = (init) => fetch(url, { method: "POST", ...init });
  await send({ body: new URLSearchParams({ client_id: "abc" }) });
  await send({ body: "ping" });
  await send({ body: new Blob(["z"], { type: "Application/Zip" }) });
  await send({ body: new Blob(["z"]) });
  await send({ body: new URLSearchParams({ client_id: "abc" }), headers: { "Content-Type": "application/json" } });
  await send({});
  const request = new Request(url, { method: "POST", body: new URLSearchParams({ a: "1" }) });
  globalThis.__contentType = request.headers.get("content-type");
}
`;

// A child's output arrives in one go once the process has already exited, so both ways of reading a
// stream have to work after the fact: `execa` async-iterates stdout, others attach a `data` listener.
const spawnSource = `
import { spawn } from "node:child_process";

export default async function Command() {
  const iterated = [];
  const child = spawn("/bin/echo", ["hello"]);
  for await (const chunk of child.stdout) iterated.push(chunk.toString());

  const late = await new Promise((resolve) => {
    const other = spawn("/bin/echo", ["world"]);
    other.on("close", () => {
      const chunks = [];
      other.stdout.on("data", (chunk) => chunks.push(chunk.toString()));
      other.stdout.on("end", () => resolve(chunks.join("")));
    });
  });

  // Port Manager detaches lsof to get a killable process group, then reads its output.
  const grouped = await new Promise((resolve) => {
    const child = spawn("/bin/echo", ["group"], { detached: true, stdio: ["ignore", "pipe", "pipe"] });
    const chunks = [];
    child.stdout.on("data", (chunk) => chunks.push(chunk.toString()));
    child.on("close", () => resolve(chunks.join("")));
  });

  globalThis.__spawn = { iterated: iterated.join(""), late, grouped };
}
`;

// node-fetch travels inside `@raycast/utils` and drives `http.request` rather than global `fetch`,
// then reads the response back by async-iterating a stream it pipes through a `PassThrough`.
const httpSource = `
import http from "node:http";
import stream, { PassThrough, pipeline } from "node:stream";

export default async function Command() {
  globalThis.__http = await new Promise((resolve, reject) => {
    const request = http.request(
      "https://example.test/data",
      { method: "post", headers: { "X-Probe": ["one", "two"], "Accept-Encoding": "gzip, deflate, br" } },
      async (response) => {
        const body = pipeline(response, new PassThrough(), () => {});
        const chunks = [];
        for await (const chunk of body) chunks.push(chunk.toString());
        resolve({
          status: response.statusCode,
          statusText: response.statusMessage,
          contentType: response.headers["content-type"],
          decoding: [response.headers["content-encoding"], response.headers["content-length"]],
          isStream: body instanceof stream,
          text: chunks.join(""),
        });
      },
    );
    request.on("error", reject);
    request.end("ping");
  });
}
`;

// Hide My Email hands axios a cookie jar through axios-cookiejar-support, whose http-cookie-agent
// extends `http.Agent` at load time and hooks each request in `addRequest` — the same way this does.
const cookieAgentSource = `
import * as http from "node:http";
import * as url from "node:url";

class CookieAgent extends http.Agent {
  constructor(options) {
    super(options);
    this.jar = new Map();
  }

  addRequest(request, options) {
    const target = url.format({ host: request.host, pathname: request.path, protocol: request.protocol });
    const implicitHeader = request._implicitHeader.bind(request);
    request._implicitHeader = () => {
      if (this.jar.size) request.setHeader("Cookie", [...this.jar].map(([k, v]) => k + "=" + v).join("; "));
      implicitHeader();
    };
    const emit = request.emit.bind(request);
    request.emit = (event, ...args) => {
      if (event === "response") {
        for (const line of args[0].headers["set-cookie"] ?? []) {
          const [pair] = line.split(";");
          const [name, value] = pair.split("=");
          this.jar.set(name, value);
        }
        this.urls.push(target);
      }
      return emit(event, ...args);
    };
    super.addRequest(request, options);
  }
}

const send = (agent, path) =>
  new Promise((resolve, reject) => {
    const request = http.request("https://example.test" + path, { agent }, (response) => {
      response.resume();
      response.on("end", () => resolve(response));
    });
    request.on("error", reject);
    request.end();
  });

export default async function Command() {
  const agent = new CookieAgent({ keepAlive: true });
  agent.urls = [];
  const first = await send(agent, "/signin?step=1");
  await send(agent, "/account");
  globalThis.__cookieAgent = {
    isAgent: agent instanceof http.Agent,
    setCookie: first.headers["set-cookie"],
    rawHeaders: first.rawHeaders,
    urls: agent.urls,
  };
}
`;

// The Homebrew extension streams its package index to disk rather than buffering it: it guards on
// `response.body`, counts bytes through a `TransformStream`, and pipes the result into a file — then
// reads it back through a `Transform`. Issue #429: `Response` had no `body`, so it failed at "HTTP 200".
const streamSource = `
import fs from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable, Transform, Writable } from "node:stream";
import { pipeline } from "node:stream/promises";

export default async function Command() {
  const target = join(tmpdir(), "tinycast-fixture-index.json");
  const response = await fetch("https://example.test/index.json");
  if (!response.ok || !response.body) throw new Error(\`HTTP \${response.status}: \${response.statusText}\`);

  let observed = 0;
  const counter = new TransformStream({
    transform(chunk, controller) {
      observed += chunk.length;
      controller.enqueue(chunk);
    },
  });
  const sink = fs.createWriteStream(target);
  await pipeline(Readable.fromWeb(response.body.pipeThrough(counter)), sink);

  const upper = new Transform({
    transform(chunk, encoding, done) {
      done(null, chunk.toString().toUpperCase());
    },
  });
  const read = [];
  const collect = new Writable({
    write(chunk, encoding, done) {
      read.push(chunk.toString());
      done(null);
    },
  });
  await pipeline(fs.createReadStream(target), upper, collect);

  globalThis.__stream = {
    observed,
    bytesWritten: sink.bytesWritten,
    onDisk: fs.readFileSync(target, "utf8"),
    piped: read.join(""),
  };
  fs.unlinkSync(target);
}
`;

const oauthSource = `
import { OAuth } from "@raycast/api";

export default async function Command() {
  const client = new OAuth.PKCEClient({
    redirectMethod: OAuth.RedirectMethod.Web,
    providerName: "GitHub",
    providerId: "github",
    description: "Connect your GitHub account",
  });

  const req = await client.authorizationRequest({
    endpoint: "https://github.com/login/oauth/authorize",
    clientId: "client-123",
    scope: "repo read:user",
  });

  const authRes = await client.authorize(req);

  const tokenSet = new OAuth.TokenSet({
    accessToken: "gho_secret123",
    refreshToken: "ghr_secret456",
    expiresIn: 3600,
  });

  await client.setTokens(tokenSet);
  const retrieved = await client.getTokens();

  const expiredToken = new OAuth.TokenSet({
    accessToken: "expired_token",
    expiresIn: 20,
    updatedAt: new Date(Date.now() - 30000),
  });

  globalThis.__oauthTest = {
    verifierLen: req.codeVerifier.length,
    challengeLen: req.codeChallenge.length,
    stateLen: req.state.length,
    url: req.toURL(),
    authCode: authRes.authorizationCode,
    retrievedAccessToken: retrieved?.accessToken,
    retrievedRefreshToken: retrieved?.refreshToken,
    isExpiredLive: tokenSet.isExpired(),
    isExpiredOld: expiredToken.isExpired(),
  };

  await client.removeTokens();
  const afterRemove = await client.getTokens();
  globalThis.__oauthTest.afterRemove = afterRemove;
}
`;

// `@raycast/utils` stores the provider's raw token response, which carries no timestamp, so the
// stored time is the only thing `isExpired()` can count from; without it a token never expired.
const tokenExpirySource = `
import { OAuth } from "@raycast/api";

export default async function Command() {
  const client = new OAuth.PKCEClient({ redirectMethod: OAuth.RedirectMethod.Web, providerName: "Google", providerId: "google" });
  await client.setTokens({ access_token: "ya29.a", refresh_token: "1//r", expires_in: 3599, token_type: "Bearer" });
  const fresh = await client.getTokens();
  const realNow = Date.now;
  Date.now = () => realNow() + 2 * 3600 * 1000;
  const laterExpired = (await client.getTokens()).isExpired();
  Date.now = realNow;
  const unstamped = new OAuth.PKCEClient({ redirectMethod: OAuth.RedirectMethod.Web, providerName: "Old", providerId: "unstamped" });
  const legacy = await unstamped.getTokens();
  globalThis.__expiry = {
    freshExpired: fresh.isExpired(),
    freshStampedNow: fresh.updatedAt instanceof Date && Math.abs(fresh.updatedAt.getTime() - realNow()) < 5000,
    laterExpired,
    unstampedExpired: legacy.isExpired(),
  };
}
`;

const noViewSource = `
import { Clipboard, showHUD } from "@raycast/api";

export default async function Command() {
  await Clipboard.copy("from no-view");
  await showHUD("done");
  globalThis.__ranNoView = true;
}
`;

const asyncSource = `
import { List } from "@raycast/api";
import { useEffect, useState } from "react";

export default function Command() {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    const timer = setTimeout(() => {
      setItems(["alpha", "beta"]);
      setLoading(false);
    }, 20);
    return () => clearTimeout(timer);
  }, []);
  return (
    <List isLoading={loading}>
      {items.map((item) => <List.Item key={item} title={item} />)}
    </List>
  );
}
`;

const errorSource = `
export default function Command() {
  throw new Error("kaboom");
}
`;

// ─── Runner ─────────────────────────────────────────────────────────

export async function runFixtures() {
  await run("List with sections, actions and a dropdown", listSource, "view", async (harness) => {
    const tree = harness.state.trees.at(-1);
    const dump = tree ? describeTree(tree) : "";
    check("renders a screen", dump.includes("<__screen active=true>"));
    check("renders the List", dump.includes("<List"));
    check("keeps searchBarAccessory as a prop", dump.includes("searchBarAccessory=<List.Dropdown>"));
    check("renders a section with items", dump.includes("<List.Section") && dump.includes("<List.Item"));
    check("serializes accessories", dump.includes("accessories=[2]"));
    check("hoists actions into a prop", dump.includes("actions=<ActionPanel>"));
    check("defaults filtering to true", dump.includes("filtering=true"));

    // Bump the counter through the action's handler and confirm the re-render.
    const item = findNode(tree, "List.Item");
    const panel = item.props.actions;
    const bump = panel.children.find((child) => child.type === "Action");
    check("action carries a dispatchable handler", !!bump?.props?.onAction?.$fn, JSON.stringify(bump?.props));
    harness.dispatch("s1", bump.props.onAction.$fn);
    await wait();
    check("re-renders after the action", describeTree(harness.state.trees.at(-1)).includes("Count is 1"));
  });

  await run("Detail with metadata", detailSource, "view", async (harness) => {
    const dump = describeTree(harness.state.trees.at(-1));
    check("renders Detail", dump.includes("<Detail"));
    check("hoists metadata", dump.includes("metadata=<Detail.Metadata>"));
    const metadata = findNode(harness.state.trees.at(-1), "Detail").props.metadata;
    const kinds = metadata.children.map((child) => child.type);
    check(
      "metadata children in order",
      JSON.stringify(kinds) ===
        JSON.stringify([
          "Detail.Metadata.Label",
          "Detail.Metadata.Separator",
          "Detail.Metadata.TagList",
          "Detail.Metadata.Link",
        ]),
      JSON.stringify(kinds),
    );
  });

  await run("List.Item.Detail split across a Fragment", fragmentDetailSource, "view", async (harness) => {
    const detail = findNode(harness.state.trees.at(-1), "List.Item").props.detail;
    check("keeps the markdown from the first sibling", detail.props.markdown === "30s remaining", JSON.stringify(detail.props));
    check("keeps the metadata from the second sibling", detail.props.metadata?.type === "Detail.Metadata", JSON.stringify(detail.props));
  });

  await run("Form fields and submit", formSource, "view", async (harness) => {
    const tree = harness.state.trees.at(-1);
    const form = findNode(tree, "Form");
    const types = form.children.map((child) => child.type);
    check(
      "all field types render",
      ["Form.TextField", "Form.TextArea", "Form.Checkbox", "Form.Dropdown", "Form.TagPicker", "Form.DatePicker", "Form.Separator", "Form.Description"].every(
        (type) => types.includes(type),
      ),
      JSON.stringify(types),
    );
    const field = form.children.find((child) => child.type === "Form.TextField");
    check("field exposes its value", field.props.value === "Ada", JSON.stringify(field.props));
    check("field has a change handler", !!field.props.onTinycastChange?.$fn);

    harness.dispatch("s1", field.props.onTinycastChange.$fn, ["Grace"]);
    await wait();
    const submit = findNode(harness.state.trees.at(-1), "Action");
    harness.dispatch("s1", submit.props.onAction.$fn);
    await wait();
    const values = harness.call("globalThis.__submitted");
    check(
      "submit collects every field value",
      values?.name === "Grace" && values.agree === true && values.role === "dev" && Array.isArray(values.tags),
      JSON.stringify(values),
    );
  });

  await run("Navigation push and pop", navigationSource, "view", async (harness) => {
    const push = findNode(harness.state.trees.at(-1), "Action");
    harness.dispatch("s1", push.props.onAction.$fn);
    await wait();
    let screens = harness.state.trees.at(-1).children.filter((child) => child.type === "__screen");
    check("two screens after push", screens.length === 2, String(screens.length));
    check("the pushed screen is active", screens[1].props.active === true);
    check("the first screen is inactive but mounted", screens[0].props.active === false);
    check("navigation depth reported", harness.state.navigationDepth === 2, String(harness.state.navigationDepth));

    harness.call('__tinycast.popNavigation("s1")');
    await wait();
    screens = harness.state.trees.at(-1).children.filter((child) => child.type === "__screen");
    check("one screen after pop", screens.length === 1, String(screens.length));
  });

  await run("Node shims and web globals", nodeSource, "view", async (harness) => {
    const markdown = findNode(harness.state.trees.at(-1), "Detail").props.markdown.split("\n");
    const expected = [
      "/a/c/d.txt",
      ".gz",
      "c",
      "darwin",
      "idle,irq,nice,sys,user",
      "true",
      "true",
      "true",
      "true",
      "https://example.com/next?q=1",
      "a=1&b=two+words",
      "ba7816bf",
      "aGVsbG8=",
      "hello",
      "héllo",
      "/Applications/Tinycast Beta.app",
      "/tmp/한글.txt",
      "/tmp/a",
      "/tmp/a\\b",
      "/tmp/a",
      "/a",
      "/tmp/a",
      "/tmp//a",
      "/tmp/a///b",
      "/tmp/a/b",
      "/C:/",
      String.raw`file:///tmp/a?query=\keep#fragment=\keep`,
      "https://example.com/",
      "/a:folder/",
      "file:///a:folder/",
      "https://example.com/",
      "file:///tmp/My%20Image.png",
      "file:///tmp/a%23b.png",
      "/tmp/a#b.png",
      "/tmp/a?b.png",
      "/Applications/Tinycast Beta.app",
      "ERR_INVALID_FILE_URL_PATH",
      "ERR_INVALID_URL",
      "ERR_INVALID_FILE_URL_HOST",
      "ERR_INVALID_URL_SCHEME",
      "ERR_INVALID_ARG_TYPE",
      "ERR_INVALID_URL",
      "ERR_INVALID_URL",
      "Error",
      "false",
      "false",
      "true",
      "true",
      "ERR_INVALID_URL_SCHEME",
      "ERR_INVALID_URL_SCHEME",
    ];
    expected.forEach((value, index) => check(`shim ${index}: ${value}`, markdown[index] === value, markdown[index]));
  });

  await run("Response takes the Web spec's constructor", responseSource, "no-view", async (harness) => {
    const result = harness.call("globalThis.__response");
    const equals = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected);
    check("a zero-arg Response is a 200 with an empty body", equals(result.probe, [200, true, "", ""]), JSON.stringify(result.probe));
    check("exposes the body readers a feature probe looks for", result.readers === true);
    check("reads status, headers and JSON back", equals(result.created, [201, "Created", "application/json", 7]), JSON.stringify(result.created));
    check("clone carries status, headers and body", equals(result.clone, [201, "application/json", '{"id":7}']), JSON.stringify(result.clone));
    check("keeps a binary body intact", equals(result.bytes, [104, 105]), JSON.stringify(result.bytes));
    check("encodes a text body as UTF-8", result.byteLength === 6, String(result.byteLength));
    check(
      "provides Blob bytes and text semantics",
      equals(result.blob, [6, "text/plain", "hello!", "104,101,108,108,111,33"]),
      JSON.stringify(result.blob),
    );
    check("slices Blob data and accepts it as a Response body", equals(result.slice, [3, "application/test", "ell", "hello!"]), JSON.stringify(result.slice));
    check("creates a typed Blob from Response.blob", equals(result.responseBlob, [2, "text/custom", "hi"]), JSON.stringify(result.responseBlob));
    check("DOMException is an Error carrying its name", equals(result.domException, ["AbortError", "stopped", true, true, "Error"]), JSON.stringify(result.domException));
  });

  const sentTypes = [];
  await run(
    "fetch derives Content-Type from the body",
    contentTypeSource,
    "no-view",
    async (harness) => {
      check("sends every request", sentTypes.length === 6, String(sentTypes.length));
      check("URLSearchParams implies form encoding", sentTypes[0] === "application/x-www-form-urlencoded;charset=UTF-8", String(sentTypes[0]));
      check("a string implies text/plain", sentTypes[1] === "text/plain;charset=UTF-8", String(sentTypes[1]));
      check("a Blob carries its own type", sentTypes[2] === "application/zip", String(sentTypes[2]));
      check("an untyped Blob implies nothing", sentTypes[3] === undefined, String(sentTypes[3]));
      check("an explicit header wins", sentTypes[4] === "application/json", String(sentTypes[4]));
      check("a bodiless request implies nothing", sentTypes[5] === undefined, String(sentTypes[5]));
      check("Request exposes the derived header", harness.call("globalThis.__contentType") === "application/x-www-form-urlencoded;charset=UTF-8");
    },
    {
      stubs: {
        "fetch.request": (args) => {
          sentTypes.push(args[0].headers["content-type"]);
          return { status: 200, statusText: "OK", headers: {}, url: "https://example.test/token", bodyBase64: "" };
        },
      },
    },
  );

  const formPosts = [];
  await run(
    "FormData holds entries and serialises as multipart",
    formDataSource,
    "no-view",
    async (harness) => {
      const equals = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected);
      const shape = harness.call("globalThis.__form");
      check("get returns the first value", shape.get === "one", JSON.stringify(shape.get));
      check("getAll returns every value", equals(shape.getAll, ["one", "two"]), JSON.stringify(shape.getAll));
      check("has distinguishes present from absent", equals(shape.has, [true, false]), JSON.stringify(shape.has));
      check("keys preserve insertion order", equals(shape.entryNames, ["name", "tag", "tag", "file", "blobless"]), JSON.stringify(shape.entryNames));
      check("a Blob entry becomes a named File", equals(shape.file, ["note.txt", "text/plain", "hi"]), JSON.stringify(shape.file));
      check("an unnamed Blob entry defaults to \"blob\"", shape.defaultName === "blob", String(shape.defaultName));
      check("a Blob entry is a File instance", shape.isFile === true, String(shape.isFile));
      check("set replaces every value in place", equals(shape.afterSet, ["name", "tag", "file"]), JSON.stringify(shape.afterSet));
      check("set collapses duplicates to one", equals(shape.afterSetValue, ["only"]), JSON.stringify(shape.afterSetValue));

      const [posted, explicit] = formPosts;
      const boundary = (posted.type ?? "").split("boundary=")[1];
      check("derives multipart with a boundary", !!boundary && posted.type.startsWith("multipart/form-data; boundary="), String(posted.type));
      check("the body uses the header's boundary", posted.body.startsWith(`--${boundary}\r\n`), posted.body.slice(0, 60));
      check("a string part carries only its name", posted.body.includes(`Content-Disposition: form-data; name="name"\r\n\r\nAda`), posted.body.slice(0, 200));
      check("a File part carries filename and type", posted.body.includes(`name="file"; filename="note.txt"\r\nContent-Type: text/plain`), posted.body);
      check("the body ends with the closing boundary", posted.body.endsWith(`--${boundary}--\r\n`), posted.body.slice(-40));
      check("an explicit Content-Type still wins", explicit.type === "text/custom", String(explicit.type));
    },
    {
      stubs: {
        "fetch.request": (args) => {
          formPosts.push({ type: args[0].headers["content-type"], body: Buffer.from(args[0].bodyBase64 ?? "", "base64").toString() });
          return { status: 200, statusText: "OK", headers: {}, url: "https://example.test/upload", bodyBase64: "" };
        },
      },
    },
  );

  await run("spawn's stdout survives a late reader", spawnSource, "no-view", async (harness) => {
    const result = harness.call("globalThis.__spawn");
    check("async iteration collects stdout", result?.iterated === "hello\n", JSON.stringify(result?.iterated));
    check("a listener attached after exit still gets it", result?.late === "world\n", JSON.stringify(result?.late));
    check("a detached child that pipes stdout is still awaited", result?.grouped === "group\n", JSON.stringify(result?.grouped));
  });

  const httpSpecs = [];
  await run(
    "http.request rides the same bridge as fetch",
    httpSource,
    "no-view",
    async (harness) => {
      const result = harness.call("globalThis.__http");
      const spec = httpSpecs[0] ?? {};
      check("sends one request over the fetch bridge", httpSpecs.length === 1, String(httpSpecs.length));
      check("uppercases the method", spec.method === "POST", String(spec.method));
      check("joins a multi-valued header", spec.headers?.["x-probe"] === "one, two", JSON.stringify(spec.headers));
      check("leaves content negotiation to the transport", spec.headers?.["accept-encoding"] === undefined);
      check("forwards the written body", Buffer.from(spec.bodyBase64 ?? "", "base64").toString() === "ping");
      check("reports status and message", result.status === 201 && result.statusText === "Created");
      check("keeps the other headers", result.contentType === "application/json", String(result.contentType));
      check("drops headers describing bytes the bridge already decoded", JSON.stringify(result.decoding) === "[null,null]", JSON.stringify(result.decoding));
      check("the body is a Stream", result.isStream === true);
      check("delivers the body to a late reader", result.text === '{"ok":true}', result.text);
    },
    {
      stubs: {
        "fetch.request": (args) => {
          httpSpecs.push(args[0]);
          return {
            status: 201,
            statusText: "Created",
            headers: { "content-type": "application/json", "content-encoding": "gzip", "content-length": "31" },
            url: "https://example.test/data",
            bodyBase64: Buffer.from('{"ok":true}').toString("base64"),
          };
        },
      },
    },
  );

  const cookieSpecs = [];
  const cookies = ["a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/", "b=2; Path=/"];
  await run(
    "an http.Agent subclass carries cookies between requests",
    cookieAgentSource,
    "no-view",
    async (harness) => {
      const result = harness.call("globalThis.__cookieAgent");
      const setCookie = JSON.stringify(result?.setCookie);
      const rawHeaders = JSON.stringify(result?.rawHeaders);
      const urls = JSON.stringify(result?.urls);
      const sent = cookieSpecs[1]?.headers;
      check("http.Agent survives esbuild's namespace import", result?.isAgent === true, JSON.stringify(result));
      check("splits a folded Set-Cookie without cutting its Expires date", setCookie === JSON.stringify(cookies), setCookie);
      check("rawHeaders repeats the name per cookie", rawHeaders === JSON.stringify(cookies.flatMap((c) => ["set-cookie", c])), rawHeaders);
      check("url.format builds the request URL from its parts", result?.urls?.[0] === "https://example.test/signin%3Fstep=1", urls);
      check("the second request sends every cookie the first received", sent?.cookie === "a=1; b=2", JSON.stringify(sent));
    },
    {
      stubs: {
        "fetch.request": (args) => {
          cookieSpecs.push(args[0]);
          const headers = cookieSpecs.length === 1 ? { "set-cookie": cookies.join(", ") } : {};
          return { status: 200, statusText: "OK", headers, url: args[0].url, bodyBase64: "" };
        },
      },
    },
  );

  const indexBody = JSON.stringify(Array.from({ length: 4000 }, (_, index) => ({ name: `pkg-${index}` })));
  await run(
    "a fetch body streams through a transform onto disk",
    streamSource,
    "no-view",
    async (harness) => {
      const result = harness.call("globalThis.__stream");
      check("the response exposes a body stream", result !== undefined && result.observed > 0, JSON.stringify(result));
      check("every byte reaches the transform", result?.observed === indexBody.length, `${result?.observed} of ${indexBody.length}`);
      check("every byte reaches the file", result?.bytesWritten === indexBody.length, String(result?.bytesWritten));
      check("the file matches the response", result?.onDisk === indexBody);
      check("reading it back through a Transform preserves it", result?.piped === indexBody.toUpperCase());
    },
    {
      stubs: {
        "fetch.request": () => ({
          status: 200,
          statusText: "OK",
          headers: { "content-type": "application/json", "content-length": String(indexBody.length) },
          url: "https://example.test/index.json",
          bodyBase64: Buffer.from(indexBody).toString("base64"),
        }),
      },
    },
  );

  await run("OAuth PKCEClient and TokenSet", oauthSource, "no-view", async (harness) => {
    const result = harness.call("globalThis.__oauthTest");
    check("generates PKCE codeVerifier and challenge", result?.verifierLen >= 43 && result?.challengeLen >= 43, JSON.stringify(result));
    check("generates OAuth state", result?.stateLen >= 20);
    check("builds correct authorization URL with redirect_uri", new URL(result.url).searchParams.get("redirect_uri") === "https://raycast.com/redirect?packageName=Extension" && new URL(result.url).searchParams.get("client_id") === "client-123");
    check("authorize returns authorization code", result?.authCode === "auth-code-12345");
    check("stores and retrieves TokenSet with tokens", result?.retrievedAccessToken === "gho_secret123" && result?.retrievedRefreshToken === "ghr_secret456");
    check("TokenSet isExpired calculation works", result?.isExpiredLive === false && result?.isExpiredOld === true);
    check("removeTokens cleans up tokens", result?.afterRemove === undefined || result?.afterRemove === null);
  });

  const storedTokens = new Map([["unstamped", JSON.stringify({ access_token: "ya29.old", expires_in: 3599 })]]);
  await run(
    "a stored token expires from the time it was stored",
    tokenExpirySource,
    "no-view",
    async (harness) => {
      const result = harness.call("globalThis.__expiry");
      check("a just-stored token is not expired", result?.freshExpired === false, JSON.stringify(result));
      check("setTokens stamps updatedAt with the storage time", result?.freshStampedNow === true, JSON.stringify(result));
      check("the same token two hours later is expired", result?.laterExpired === true, JSON.stringify(result));
      check("a stored token with no timestamp counts as expired", result?.unstampedExpired === true, JSON.stringify(result));
    },
    {
      stubs: {
        "oauth.setTokens": (args) => {
          storedTokens.set(args[0], args[1]);
          return null;
        },
        "oauth.getTokens": (args) => storedTokens.get(args[0]) ?? null,
      },
    },
  );

  await run("no-view command", noViewSource, "no-view", async (harness) => {
    check("ran to completion", harness.state.finished === true);
    check("ran the body", harness.call("globalThis.__ranNoView") === true);
    check(
      "used the clipboard and HUD host calls",
      harness.state.hostCalls.includes("clipboard.copy") && harness.state.hostCalls.includes("feedback.showHUD"),
      harness.state.hostCalls.join(", "),
    );
  });

  await run("timers drive an async render", asyncSource, "view", async (harness) => {
    check("starts loading", describeTree(harness.state.trees[0]).includes("isLoading=true"));
    await wait(120);
    const dump = describeTree(harness.state.trees.at(-1));
    check("finishes loading", dump.includes("isLoading=false"), dump);
    check("renders the resolved items", dump.includes("alpha") && dump.includes("beta"));
  });

  console.log("\n▶ Errors surface instead of crashing");
  const harness = createHarness();
  harness.boot(bootConfig());
  harness.start("s1", compile(errorSource), "/fixtures/cmd.js", "/fixtures", "view", {});
  await wait();
  check("a throwing component reports a failure", harness.state.failures.some((message) => message.includes("kaboom")), harness.state.failures.join("|"));
  harness.stop("s1");

  console.log(failures === 0 ? "\nAll runtime fixtures passed." : `\n${failures} check(s) failed.`);
  if (import.meta.url === `file://${process.argv[1]}`) process.exit(failures === 0 ? 0 : 1);
  return failures;
}

function findNode(tree, type) {
  const stack = [...(tree?.children ?? [])];
  while (stack.length) {
    const node = stack.shift();
    if (node.type === type) return node;
    stack.push(...(node.children ?? []));
    // Slot props hold real nodes too (actions, metadata, detail).
    for (const value of Object.values(node.props ?? {})) {
      if (value && typeof value === "object" && value.type) stack.push(value);
      else if (Array.isArray(value)) stack.push(...value.filter((entry) => entry && entry.type));
    }
  }
  return undefined;
}

if (import.meta.url === `file://${process.argv[1]}`) await runFixtures();
