// Build Test.IntegrationEnvironment with gopurs and set SPEC_TEST_APP to its
// executable. Tests invoke the native implementation, including Aff and FS.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const app = resolve(process.env.SPEC_TEST_APP ?? "output/integration_environment");
const run = promisify(execFile);

const fakeTool = `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");
const tool = path.basename(process.argv[1]);
fs.appendFileSync(process.env.SPEC_TEST_CALLS, tool + "\\n");
if (tool === "spago") {
  const started = path.join(process.env.SPEC_TEST_ROOT, "cancel-started");
  if (process.env.SPEC_TEST_CANCEL === "1" && !fs.existsSync(started)) {
    if (process.env.SPEC_TEST_DESCENDANT === "1") {
      const source = "const fs = require('node:fs'); process.stdout.write('ready'); setTimeout(() => fs.writeFileSync(process.env.SPEC_TEST_ROOT + '/cancel-late', JSON.stringify({ pid: process.pid, cwd: process.cwd(), program: fs.readFileSync('src/Main.purs', 'utf8') })), 500);";
      const descendant = spawn(process.execPath, ["-e", source], { stdio: ["ignore", "pipe", "inherit"] });
      descendant.stdout.once("data", () => fs.writeFileSync(started, JSON.stringify({ parent: process.pid, descendant: descendant.pid })));
    } else {
      fs.writeFileSync(started, String(process.pid));
      setTimeout(() => {
        fs.writeFileSync(path.join(process.env.SPEC_TEST_ROOT, "cancel-late"), JSON.stringify({ pid: process.pid, cwd: process.cwd(), program: fs.readFileSync("src/Main.purs", "utf8") }));
      }, 500);
    }
  }
  const config = fs.readFileSync("spago.yaml", "utf8");
  if (config.includes("SPEC_REPO_PATH") || !config.includes(process.env.SPEC_TEST_ROOT)) process.exit(41);
  fs.mkdirSync("output", { recursive: true });
} else if (tool === "go" && process.argv[2] === "build") {
  fs.writeFileSync("go_test_app", "#!/usr/bin/env bash\\nprintf 'fixture output\\\\n'\\nexit 1\\n", { mode: 0o755 });
} else if (tool === "npm" || tool === "npx") {
  throw new Error("integration must use the caller's tools, without npm installation");
}
`;

function fixture(t) {
  const base = mkdtempSync(join(tmpdir(), "spec-environment-contract-"));
  const root = join(base, "spec");
  const template = join(root, "integration-tests/env-template");
  const temporary = join(base, "tmp");
  const calls = join(base, "calls");
  for (const directory of [template, temporary, join(base, "bin"), join(base, "gopurs/bin")]) mkdirSync(directory, { recursive: true });
  for (const tool of ["spago", "go", "npm", "npx"]) writeFileSync(join(base, "bin", tool), fakeTool, { mode: 0o755 });
  writeFileSync(join(base, "gopurs/bin/gopurs"), fakeTool, { mode: 0o755 });
  const env = { ...process.env, TMPDIR: temporary, PATH: join(base, "bin") + ":" + process.env.PATH, SPEC_TEST_CALLS: calls, SPEC_TEST_ROOT: root };
  t.after(() => rmSync(base, { recursive: true, force: true }));
  const configure = () => writeFileSync(join(template, "spago.yaml"), "workspace:\n  extraPackages:\n    spec:\n      path: SPEC_REPO_PATH\n");
  return { template, temporary, calls, configure, run: (retry, cancel = false, descendant = false) => run(app, [], { cwd: root, env: { ...env, SPEC_TEST_RETRY: retry ? "1" : "0", SPEC_TEST_CANCEL: cancel ? "1" : "0", SPEC_TEST_DESCENDANT: descendant ? "1" : "0" }, timeout: 30_000 }) };
}

test("fresh integration uses the caller's tools and leaves its template untouched", async t => {
  const f = fixture(t);
  f.configure();
  const config = readFileSync(join(f.template, "spago.yaml"), "utf8");
  const result = await f.run(false);
  assert.match(result.stdout, /environment contract passed/);
  assert.match(result.stdout, /\[integration\] start prepare:purescript/);
  assert.match(result.stdout, /\[integration\] end runtime elapsedMs=.* success outputChars=/);
  assert.deepEqual(readdirSync(f.template), ["spago.yaml"]);
  assert.equal(readFileSync(join(f.template, "spago.yaml"), "utf8"), config);
  assert.deepEqual(readFileSync(f.calls, "utf8").trim().split("\n"), ["spago", "gopurs", "go", "go", "go"]);
  assert.deepEqual(readdirSync(f.temporary), []);
});

test("failed initialization is cleaned up and can be retried on the same environment", async t => {
  const f = fixture(t);
  const result = await f.run(true);
  assert.match(result.stdout, /environment contract passed/);
  assert.deepEqual(readdirSync(f.temporary), []);
});

test("canceling a case stops its child before the next case reuses the environment", async t => {
  const f = fixture(t);
  f.configure();
  const result = await f.run(false, true);
  assert.match(result.stdout, /canceled prepare:purescript; child group and pipes closed/);
  assert.deepEqual(readdirSync(f.temporary), []);
});

test("canceling a case also stops descendants before the environment is reused", async t => {
  const f = fixture(t);
  f.configure();
  await f.run(false, true, true);
  assert.deepEqual(readdirSync(f.temporary), []);
});
