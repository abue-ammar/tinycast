import { appendFile } from "node:fs/promises";

export async function isTrustedReportRun(run, repository, compareToMain) {
  const upstreamRepository = process.env.MIDSCENE_UPSTREAM_REPOSITORY;
  if (!upstreamRepository) throw new Error("MIDSCENE_UPSTREAM_REPOSITORY is required");
  if (
    run.repository?.full_name !== repository ||
    run.head_repository?.full_name !== repository ||
    run.path !== ".github/workflows/midscene.yml" ||
    run.status !== "completed" ||
    !/^[a-f0-9]{40}$/.test(run.head_sha ?? "")
  )
    return false;
  if (repository !== upstreamRepository) return run.event === "workflow_dispatch";
  if (
    run.head_branch !== "main" ||
    !["schedule", "push", "workflow_dispatch"].includes(run.event) ||
    !/^[a-f0-9]{40}$/.test(run.head_sha ?? "")
  )
    return false;
  // Dispatch metadata can also name a tag "main". Require commit ancestry.
  const comparison = await compareToMain(run.head_sha);
  return ["ahead", "identical"].includes(comparison.status);
}

export async function findReportHistory(
  getRuns,
  repository,
  getArtifacts,
  currentRunId,
  compareToMain,
) {
  for (let page = 1; ; page += 1) {
    const runs = await getRuns(page);
    for (const run of runs) {
      if (String(run.id) === String(currentRunId)) continue;
      try {
        if (!(await isTrustedReportRun(run, repository, compareToMain))) continue;
        const candidates = [];
        for (let artifactPage = 1; ; artifactPage += 1) {
          const artifacts = await getArtifacts(run.id, artifactPage);
          candidates.push(...artifacts.filter(
            (item) => !item.expired && /^midscene-e2e-report-pages-\d+$/.test(item.name),
          ));
          if (artifacts.length < 100) break;
        }
        const artifact = candidates.sort((a, b) => Number(b.name.split('-').at(-1)) - Number(a.name.split('-').at(-1)))[0];
        if (artifact) return { ...artifact, workflow_run: { id: run.id } };
      } catch (error) {
        process.stderr.write(`Skipping report history run ${run.id}: ${error.message}\n`);
      }
    }
    if (runs.length < 100) return null;
  }
}

async function main(mode) {
  if (!process.env.MIDSCENE_UPSTREAM_REPOSITORY) {
    throw new Error("MIDSCENE_UPSTREAM_REPOSITORY is required");
  }
  const repository = process.env.GITHUB_REPOSITORY;
  const get = async (resource) => {
    const response = await fetch(`${process.env.GITHUB_API_URL}/repos/${repository}/${resource}`, {
      headers: {
        Authorization: `Bearer ${process.env.GH_TOKEN}`,
        Accept: "application/vnd.github+json",
      },
    });
    if (!response.ok) throw new Error(`GitHub ${resource}: HTTP ${response.status}`);
    return response.json();
  };
  const getRun = (id) => get(`actions/runs/${id}`);
  let mainSha;
  const compareToMain = async (sha) => {
    mainSha ??= (await get("branches/main")).commit.sha;
    return get(`compare/${sha}...${mainSha}`);
  };
  if (mode === "validate-source") {
    const runId = process.env.REPORT_SOURCE_RUN_ID;
    if (!/^\d+$/.test(runId ?? "")) throw new Error("Report source run ID must be numeric");
    const run = await getRun(runId);
    if (!(await isTrustedReportRun(run, repository, compareToMain))) {
      throw new Error(
        "Report source must be a completed, same-repository Midscene run from a trusted event/ref",
      );
    }
    if (!Number.isSafeInteger(run.run_attempt) || run.run_attempt < 1) throw new Error('Invalid source run attempt');
    if (process.env.GITHUB_OUTPUT) await appendFile(process.env.GITHUB_OUTPUT, `source_attempt=${run.run_attempt}\n`);
  } else if (mode === "find-previous") {
    const filter =
      repository === process.env.MIDSCENE_UPSTREAM_REPOSITORY
        ? "branch=main"
        : "event=workflow_dispatch";
    const artifact = await findReportHistory(
      async (page) =>
        (
          await get(
            `actions/workflows/midscene.yml/runs?status=completed&${filter}&per_page=100&page=${page}`,
          )
        ).workflow_runs,
      repository,
      async (id, page) =>
        (await get(`actions/runs/${id}/artifacts?per_page=100&page=${page}`)).artifacts,
      process.env.GITHUB_RUN_ID,
      compareToMain,
    );
    if (artifact) {
      await appendFile(
        process.env.GITHUB_OUTPUT,
        `name=${artifact.name}\nrun_id=${artifact.workflow_run.id}\n`,
      );
    }
  } else {
    throw new Error(`Unknown mode: ${mode}`);
  }
}

if (import.meta.url === new URL(process.argv[1], "file:").href) {
  main(process.argv[2]).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
