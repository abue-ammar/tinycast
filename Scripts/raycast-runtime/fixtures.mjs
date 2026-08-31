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
import crypto from "node:crypto";
import { Buffer } from "node:buffer";
import { Detail } from "@raycast/api";

export default function Command() {
  const parts = [
    path.join("/a/b", "../c", "d.txt"),
    path.extname("x/y/file.tar.gz"),
    path.basename("/a/b/c.md", ".md"),
    os.platform(),
    new URL("/next?q=1", "https://example.com/base/page").href,
    new URLSearchParams({ a: "1", b: "two words" }).toString(),
    crypto.createHash("sha256").update("abc").digest("hex").slice(0, 8),
    Buffer.from("hello").toString("base64"),
    Buffer.from("aGVsbG8=", "base64").toString("utf8"),
    new TextDecoder().decode(new TextEncoder().encode("héllo")),
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
  globalThis.__response = {
    probe: [probe.status, probe.ok, probe.statusText, await probe.text()],
    readers: ["text", "arrayBuffer", "blob"].every((name) => typeof probe[name] === "function"),
    created: [created.status, created.statusText, created.headers.get("content-type"), (await created.json()).id],
    clone: [clone.status, clone.headers.get("content-type"), await clone.text()],
    bytes: Array.from(await new Response(new Uint8Array([104, 105])).bytes()),
    byteLength: (await new Response("héllo").arrayBuffer()).byteLength,
  };
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

  globalThis.__spawn = { iterated: iterated.join(""), late };
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
    createdAt: Date.now() - 30000,
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
      "https://example.com/next?q=1",
      "a=1&b=two+words",
      "ba7816bf",
      "aGVsbG8=",
      "hello",
      "héllo",
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
  });

  await run("spawn's stdout survives a late reader", spawnSource, "no-view", async (harness) => {
    const result = harness.call("globalThis.__spawn");
    check("async iteration collects stdout", result?.iterated === "hello\n", JSON.stringify(result?.iterated));
    check("a listener attached after exit still gets it", result?.late === "world\n", JSON.stringify(result?.late));
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
