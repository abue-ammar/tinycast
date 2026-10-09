import assert from "node:assert/strict";
import test from "node:test";
import { findReportHistory, isTrustedReportRun } from "./trusted-report-runs.mjs";

process.env.MIDSCENE_UPSTREAM_REPOSITORY = "abue-ammar/tinycast";

const upstream = {
  repository: { full_name: "abue-ammar/tinycast" },
  head_repository: { full_name: "abue-ammar/tinycast" },
  path: ".github/workflows/midscene.yml",
  status: "completed",
  head_branch: "main",
  event: "push",
  head_sha: "a".repeat(40),
};

const compareToMain = async () => ({ status: "ahead" });
const trusted = (run, repository) => isTrustedReportRun(run, repository, compareToMain);

test("repository policy follows the configured upstream and rejects missing configuration", async () => {
  try {
    process.env.MIDSCENE_UPSTREAM_REPOSITORY = "new-owner/tinycast";
    const renamed = {
      ...upstream,
      repository: { full_name: "new-owner/tinycast" },
      head_repository: { full_name: "new-owner/tinycast" },
    };
    assert.equal(await trusted(renamed, "new-owner/tinycast"), true);
    assert.equal(await trusted(upstream, "abue-ammar/tinycast"), false);
    delete process.env.MIDSCENE_UPSTREAM_REPOSITORY;
    await assert.rejects(trusted(renamed, "new-owner/tinycast"), /is required/);
  } finally {
    process.env.MIDSCENE_UPSTREAM_REPOSITORY = "abue-ammar/tinycast";
  }
});

test("report sources reject PR artifacts, other workflows, and untrusted refs", async () => {
  assert.equal(await trusted(upstream, "abue-ammar/tinycast"), true);
  assert.equal(await trusted({ ...upstream, event: "schedule" }, "abue-ammar/tinycast"), true);
  assert.equal(await trusted({ ...upstream, event: "workflow_dispatch" }, "abue-ammar/tinycast"), true);
  for (const change of [
    { event: "pull_request" },
    { event: "pull_request_target" },
    { head_repository: { full_name: "attacker/tinycast" } },
    { repository: { full_name: "other/tinycast" } },
    { head_repository: null },
    { head_branch: "feature" },
    { path: ".github/workflows/other.yml" },
    { status: "in_progress" },
  ])
    assert.equal(await trusted({ ...upstream, ...change }, "abue-ammar/tinycast"), false);
});

test("fork reports require a same-repository manual dispatch", async () => {
  const fork = {
    ...upstream,
    repository: { full_name: "example/tinycast" },
    head_repository: { full_name: "example/tinycast" },
    event: "workflow_dispatch",
    head_branch: "feature",
  };
  assert.equal(await trusted(fork, "example/tinycast"), true);
  assert.equal(await trusted({ ...fork, event: "pull_request" }, "example/tinycast"), false);
  assert.equal(await trusted({ ...fork, event: "push" }, "example/tinycast"), false);
});

test("an upstream tag named main must still point to a protected-main commit", async () => {
  for (const status of ["behind", "diverged"]) {
    assert.equal(
      await isTrustedReportRun(
        { ...upstream, event: "workflow_dispatch" },
        "abue-ammar/tinycast",
        async () => ({ status }),
      ),
      false,
    );
  }
  assert.equal(
    await isTrustedReportRun(upstream, "abue-ammar/tinycast", async () => ({ status: "identical" })),
    true,
  );
});

test("history paginates workflow runs and artifacts without trusting PRs", async () => {
  const pages = [];
  const downloads = [];
  const result = await findReportHistory(
    async (page) => {
      pages.push(page);
      return page === 1
        ? Array.from({ length: 100 }, (_, i) => ({ ...upstream, id: i + 1, event: "pull_request" }))
        : [{ ...upstream, id: 101 }];
    },
    "abue-ammar/tinycast",
    async (id, page) => {
      downloads.push([id, page]);
      return page === 1
        ? Array.from({ length: 100 }, () => ({ name: "unrelated" }))
        : [{ name: "midscene-e2e-report-pages-2" }];
    },
    "102",
    compareToMain,
  );
  assert.equal(result.workflow_run.id, 101);
  assert.deepEqual(pages, [1, 2]);
  assert.deepEqual(downloads, [
    [101, 1],
    [101, 2],
  ]);
});

test("history skips current runs, expired artifacts, and unavailable candidates", async () => {
  const downloads = [];
  const result = await findReportHistory(
    async () => [1, 2, 3, 4].map((id) => ({ ...upstream, id })),
    "abue-ammar/tinycast",
    async (id) => {
      downloads.push(id);
      if (id === 2) throw new Error("HTTP 404");
      return [{ name: "midscene-e2e-report-pages-1", expired: id === 3 }];
    },
    "1",
    compareToMain,
  );
  assert.deepEqual(downloads, [2, 3, 4]);
  assert.equal(result.workflow_run.id, 4);
  assert.equal(
    await findReportHistory(
      async () => [],
      "abue-ammar/tinycast",
      async () => [],
      "1",
      compareToMain,
    ),
    null,
  );
});

test("explicit source validation propagates a failed trust lookup", async () => {
  await assert.rejects(
    isTrustedReportRun(upstream, "abue-ammar/tinycast", async () => {
      throw new Error("HTTP 404");
    }),
    /HTTP 404/,
  );
});
test('history picks the latest attempt across artifact pages instead of retaining stale rerun content', async () => {
  const selected = await findReportHistory(async () => [{ ...upstream, id: 10 }], 'abue-ammar/tinycast', async (_, page) => page === 1
    ? [{ name: 'midscene-e2e-report-pages-1' }, ...Array.from({ length: 99 }, () => ({ name: 'other' }))]
    : [{ name: 'midscene-e2e-report-pages-3' }], 11, compareToMain);
  assert.equal(selected.name, 'midscene-e2e-report-pages-3');
});
