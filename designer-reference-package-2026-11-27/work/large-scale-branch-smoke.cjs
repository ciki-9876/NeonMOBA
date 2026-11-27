const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { performance } = require("node:perf_hooks");

const root = path.join(__dirname, "..");
const html = fs.readFileSync(path.join(root, "outputs", "world-model-engineering-bench.html"), "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
if (!script) throw new Error("The experiment script was not found in the HTML page.");

class Element {
  constructor() { this.value = ""; this.innerHTML = ""; this.textContent = ""; this.hidden = false; this.disabled = false; this.style = {}; this.classList = { add() {}, remove() {}, toggle() {} }; }
  addEventListener() {}
}
const elements = new Map();
const document = { getElementById(id) { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); }, querySelectorAll() { return []; } };
const context = vm.createContext({ document, performance, setTimeout, clearTimeout, Date });
const api = vm.runInContext(`${script}\n;({runBatchValidation,runRuleFixtures,simulateSeededCampaign,runCampaign,validateWorldState,auditStoryEvents,signature,storyOutcomeSignature})`, context);

async function main() {
  const started = performance.now();
  const result = await api.runBatchValidation(1000);
  console.log(JSON.stringify({ sampleCount: result.sampleCount, uniqueOutcomes: result.uniqueOutcomes, invariantFailures: result.invariantFailures, causalFailures: result.causalFailures, storyEventCount: result.storyEventCount, causalEventCount: result.causalEventCount, maxCauseDepth: result.maxCauseDepth, replayed: result.replayed, replayFailures: result.replayFailures, paired: result.paired, counterfactualChanges: result.counterfactualChanges, ruleCounts: result.ruleCounts, ruleCoverage: result.ruleCoverage, fixtures: result.fixtures, elapsedMs: result.elapsedMs }, null, 2));
  const failures = result.fixtures.filter(fixture => !fixture.passed);
  const ensure = (condition, message) => { if (!condition) throw new Error(message); };
  ensure(result.sampleCount === 1000, "exactly 1,000 five-season campaigns should run");
  ensure(result.invariantFailures === 0, "all generated worlds should preserve the world rules");
  ensure(result.causalFailures === 0, "all generated story records should pass the cause audit");
  ensure(result.replayed === 64 && result.replayFailures === 0, "the replay samples should be deterministic");
  ensure(result.counterfactualChanges >= Math.ceil(result.paired / 2), "at least half of changed-choice pairs should have different later worlds");
  ensure(result.uniqueOutcomes >= 100, "generated choices should produce at least 100 distinct outcomes");
  ensure(result.ruleCoverage === 6, "all six story rules should be exercised by campaigns or boundary fixtures");
  ensure(failures.length === 0, `boundary fixtures failed: ${JSON.stringify(failures)}`);
  ensure(result.maxCauseDepth >= 3, "a causal story should connect at least three linked events");
  console.log(JSON.stringify({ result: "PASS", allGreen: result.allGreen, wallMs: Number((performance.now() - started).toFixed(1)) }));
}

main().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
