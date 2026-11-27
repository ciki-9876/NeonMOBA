const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const htmlPath = path.join(root, "outputs", "world-model-engineering-bench.html");
const html = fs.readFileSync(htmlPath, "utf8");
const chrome = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const previewPath = path.join(__dirname, "browser-chain-smoke.html");
const profile = path.join(__dirname, "browser-chain-smoke-profile");
const script = String.raw`<script>
try {
  const action = document.getElementById("actionSelect");
  action.value = "chain";
  action.dispatchEvent(new Event("change", { bubbles: true }));
  document.getElementById("horizonSelect").value = "5";
  const started = performance.now();
  document.getElementById("runButton").click();
  const runMs = Number((performance.now() - started).toFixed(2));
  const lin = world.entities.find(entity => entity.id === "A");
  const zhou = world.entities.find(entity => entity.id === "C");
  const gu = world.entities.find(entity => entity.id === "E");
  const chainState = lin.group === "G3" && lin.lineup === "starter" && zhou.group === "G1" && gu.group === "G3" && world.relations["A|E"] === 8;
  const checksPassed = latestAssertions.length === 18 && latestAssertions.every(item => item.passed);
  const rosterValid = world.entities.every(entity => world.entities.filter(other => other.group === entity.group && other.lineup === "starter").length <= STARTER_CAPACITY);
  const entityCount = world.entities.length;
  const relationCount = Object.keys(world.relations).length;
  const history = document.getElementById("causalList").innerHTML;
  const causalOrder = history.indexOf("周屿签入星火战队") < history.indexOf("首发位置调整") && history.indexOf("首发位置调整") < history.indexOf("替补选手为上场机会转会");
  document.getElementById("detailsPanel").open = true;
  renderState();
  const stateRows = document.querySelectorAll("#entityRows tr").length;
  const displayNames = Array.from(document.querySelectorAll("#entityRows tr td:first-child"), cell => cell.textContent.trim());
  const uniqueNames = new Set(displayNames).size === 50;
  const relationshipRows = document.querySelectorAll("#edgeRows tr").length;
  const teamCards = document.querySelectorAll("#groupCards .group-chip").length;
  document.getElementById("toCheckButton").click();
  const checkScreen = currentStep === 3 && document.querySelectorAll("#assertionWrap tbody tr").length === 18;
  document.getElementById("rebirthButton").click();
  const rebirthPassed = latestAssertions.length === 3 && latestAssertions.every(item => item.passed);
  const resetState = world.step === 0 && world.entities.length === 50 && JSON.stringify(world.entities) === JSON.stringify(BASE_ENTITIES) && world.relations["A|E"] === 0;
  const memoryKept = world.knowledge.some(item => item.includes("三人连锁测试"));
  const result = { result: "PASS", runMs, entities: entityCount, relations: relationCount, chainState, checksPassed, rosterValid, causalOrder, stateRows, uniqueNames, relationshipRows, teamCards, checkScreen, rebirthPassed, resetState, memoryKept };
  const marker = document.createElement("pre");
  marker.id = "browser-e2e-result";
  marker.textContent = JSON.stringify(result);
  document.body.append(marker);
} catch (error) {
  const marker = document.createElement("pre");
  marker.id = "browser-e2e-result";
  marker.textContent = JSON.stringify({ result: "FAIL", error: String(error && error.stack || error) });
  document.body.append(marker);
}
</script>`;
fs.writeFileSync(previewPath, html.replace("</body>", `${script}</body>`));

const run = spawnSync(chrome, [
  "--headless=new",
  "--disable-gpu",
  "--disable-extensions",
  "--no-first-run",
  "--no-default-browser-check",
  `--user-data-dir=${profile}`,
  "--virtual-time-budget=5000",
  "--dump-dom",
  pathToFileURL(previewPath).href
], { encoding: "utf8", timeout: 30000 });

if (run.error) throw run.error;
const marker = run.stdout.match(/<pre id="browser-e2e-result">([\s\S]*?)<\/pre>/)?.[1];
if (run.status !== 0 || !marker) throw new Error(`Browser run failed: ${run.stderr || run.stdout}`);
const result = JSON.parse(marker.replaceAll("&quot;", '"').replaceAll("&amp;", "&").replaceAll("&lt;", "<").replaceAll("&gt;", ">"));
console.log(JSON.stringify(result));
if (result.result !== "PASS" || !result.chainState || !result.checksPassed || !result.rosterValid || !result.causalOrder || result.entities !== 50 || result.relations !== 1225 || result.stateRows !== 50 || !result.uniqueNames || result.relationshipRows < 50 || result.relationshipRows > 1225 || result.teamCards !== 10 || !result.checkScreen || !result.rebirthPassed || !result.resetState || !result.memoryKept) {
  process.exitCode = 1;
}
