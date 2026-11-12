// Exercise the real auxiliary FFI with this compiler's runtime and JavaScript's
// upstream number/string dispatch. This is not a complete node-child-process port.
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const work = mkdtempSync(join(tmpdir(), "gopurs-child-process-values-"));
console.log(`Workspace: ${work}`);
mkdirSync(join(work, "output/gopurs_runtime"), { recursive: true });
for (const folder of ["childprocess", "types"]) mkdirSync(join(work, folder));
writeFileSync(join(work, "go.mod"), "module gopurs\n\ngo 1.27.0\n");
writeFileSync(join(work, "output/gopurs_runtime/runtime.go"), readFileSync(resolve(root, "../gopurs/runtime/runtime.go")));
for (const [source, target] of [
 ["src/Node/ChildProcess.go", "childprocess/ffi.go"],
 ["src/Node/ChildProcess/Types.go", "types/ffi.go"],
 ["test/native-child-process-values/undefined_test.go", "childprocess/ffi_test.go"],
 ["test/native-child-process-values/types_test.go", "types/ffi_test.go"],
]) writeFileSync(join(work, target), readFileSync(join(root, source)));
const dependencies = readdirSync(join(root, ".spago/p")).filter(name => name.startsWith("node-child-process-"));
if (dependencies.length !== 1) throw new Error("Expected one node-child-process dependency after spago build");
writeFileSync(join(work, "oracle.mjs"), readFileSync(join(root, ".spago/p", dependencies[0], "src/Node/ChildProcess/Types.js")));
const { fromKillSignalImpl } = await import(pathToFileURL(join(work, "oracle.mjs")));
const cases = [
 ...[0, 15, -15, 2147483648, 4294967297, -4294967297].map(number => ({ name: `integer ${number}`, kind: "int", number })),
 ...[0, 1.75, -1.75, 2147483648, 4294967297, -4294967297].map(number => ({ name: `number ${number}`, kind: "number", number })),
 ...["NaN", "Infinity", "-Infinity"].map(special => ({ name: special, kind: "number", special })),
 ...["SIGTERM", ""].map(text => ({ name: `string ${text}`, kind: "string", text })),
 ...["boolean", "null", "undefined"].map(kind => ({ name: kind, kind })),
];
for (const c of cases) {
 const value = c.kind === "int" || c.kind === "number" ? c.special ? Number(c.special) : c.number
  : c.kind === "string" ? c.text : c.kind === "boolean" ? true : c.kind === "null" ? null : undefined;
 try {
  Object.assign(c, fromKillSignalImpl(expected => ({ branch: "int", expected }), () => ({ branch: "string" }), value));
 } catch { c.branch = "error"; }
}
writeFileSync(join(work, "types/reference.json"), JSON.stringify(cases));
const result = spawnSync("go", ["test", "-count=1", "-v", "./childprocess", "./types"], {
 cwd: work, encoding: "utf8", env: { ...process.env, GOWORK: "off", GOPROXY: "off", GOSUMDB: "off" }, timeout: 120000,
});
writeFileSync(join(work, "test.log"), (result.stdout ?? "") + (result.stderr ?? ""));
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
if (result.error) throw result.error;
if (result.status === 0) rmSync(work, { recursive: true, force: true });
process.exitCode = result.status ?? 1;
