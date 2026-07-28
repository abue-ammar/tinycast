// Self-contained checks for the embedded runtime: each fixture is a tiny extension command compiled
// with esbuild exactly the way a real one is (CJS, JSX automatic, @raycast/api + react external).
//
//   node fixtures.mjs

import { transformSync } from "esbuild";
import { bootConfig, createHarness, describeTree } from "./test.mjs";

function compile(source) {
  return transformSync(source, { loader: "jsx", jsx: "automatic", format: "cjs", target: "es2022" }).code;
}

const wait = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));

let failures = 0;

function check(label, condition, detail) {
  if (condition) {
    console.log(`  ✓ ${label}`);
  } else {
    failures += 1;
    console.log(`  ✗ ${label}${detail ? ` — ${detail}` : ""}`);
  }
}

async function run(name, source, mode, body) {
  console.log(`\n▶ ${name}`);
  const harness = createHarness();
  harness.boot(bootConfig());
  harness.start("s1", compile(source), "/fixtures/cmd.js", "/fixtures", mode, {});
  await wait();
  if (harness.state.failures.length) {
    failures += 1;
    console.log(`  ✗ threw:\n${harness.state.failures.join("\n")}`);
  }
  await body(harness);
  harness.stop("s1");
}

// ─── Fixtures ───────────────────────────────────────────────────────

const listSource = `
import { List, ActionPanel, Action, Icon, Color } from "@raycast/api";
import { useState } from "react";

export default function Command() {
  const [count, setCount] = useState(0);
  return (
    <List navigationTitle="Fixtures" searchBarPlaceholder="Type to filter…" isLoading={false}
      searchBarAccessory={<List.Dropdown tooltip="Scope" value="all"><List.Dropdown.Item title="All" value="all" /></List.Dropdown>}>
      <List.Section title="Numbers" subtitle="two">
        <List.Item
          title={"Count is " + count}
          subtitle="tap to bump"
          icon={{ source: Icon.Circle, tintColor: Color.Green }}
          accessories={[{ text: String(count) }, { tag: { value: "live", color: Color.Blue } }]}
          actions={
            <ActionPanel title="Row">
              <Action title="Bump" onAction={() => setCount((value) => value + 1)} />
              <ActionPanel.Section title="More">
                <Action.CopyToClipboard title="Copy" content="hello" />
              </ActionPanel.Section>
            </ActionPanel>
          }
        />
        <List.Item title="Second" keywords={["two"]} />
      </List.Section>
    </List>
  );
}
`;

const detailSource = `
import { Detail, ActionPanel, Action } from "@raycast/api";

export default function Command() {
  return (
    <Detail
      markdown={"# Title\\n\\nSome **body** text."}
      navigationTitle="Doc"
      metadata={
        <Detail.Metadata>
          <Detail.Metadata.Label title="Author" text="Ada" />
          <Detail.Metadata.Separator />
          <Detail.Metadata.TagList title="Tags">
            <Detail.Metadata.TagList.Item text="swift" />
          </Detail.Metadata.TagList>
          <Detail.Metadata.Link title="Home" target="https://example.com" text="example.com" />
        </Detail.Metadata>
      }
      actions={<ActionPanel><Action.OpenInBrowser url="https://example.com" /></ActionPanel>}
    />
  );
}
`;

const formSource = `
import { Form, ActionPanel, Action } from "@raycast/api";

export default function Command() {
  return (
    <Form actions={<ActionPanel><Action.SubmitForm title="Save" onSubmit={(values) => { globalThis.__submitted = values; }} /></ActionPanel>}>
      <Form.TextField id="name" title="Name" defaultValue="Ada" />
      <Form.TextArea id="bio" title="Bio" />
      <Form.Checkbox id="agree" label="Agree" defaultValue={true} />
      <Form.Dropdown id="role" title="Role" defaultValue="dev">
        <Form.Dropdown.Item value="dev" title="Developer" />
        <Form.Dropdown.Item value="ops" title="Operator" />
      </Form.Dropdown>
      <Form.TagPicker id="tags" title="Tags" defaultValue={["a"]}>
        <Form.TagPicker.Item value="a" title="A" />
      </Form.TagPicker>
      <Form.DatePicker id="due" title="Due" />
      <Form.Separator />
      <Form.Description text="All fields optional." />
    </Form>
  );
}
`;

const navigationSource = `
import { List, Detail, ActionPanel, Action } from "@raycast/api";
import { useNavigation } from "@raycast/api";

function Second() {
  const { pop } = useNavigation();
  return <Detail markdown="second" actions={<ActionPanel><Action title="Back" onAction={pop} /></ActionPanel>} />;
}

export default function Command() {
  return (
    <List>
      <List.Item title="Go" actions={<ActionPanel><Action.Push title="Push" target={<Second />} /></ActionPanel>} />
    </List>
  );
}
`;

const nodeSource = `
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";
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
