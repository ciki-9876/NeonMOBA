const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const html = fs.readFileSync(path.join(root, "outputs", "world-model-engineering-bench.html"), "utf8");
const chrome = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const previewPath = path.join(__dirname, "browser-batch-smoke.html");
const profile = path.join(__dirname, "browser-batch-smoke-profile");
const script = String.raw`<script>
(async()=>{
  try {
    document.getElementById("actionSelect").value="chain";
    document.getElementById("actionSelect").dispatchEvent(new Event("change",{bubbles:true}));
    document.getElementById("horizonSelect").value="5";
    document.getElementById("runButton").click();
    document.getElementById("toCheckButton").click();
    const result=await startBatchValidation();
    const summary={result:result.allGreen?"PASS":"FAIL",sampleCount:result.sampleCount,uniqueOutcomes:result.uniqueOutcomes,invariantFailures:result.invariantFailures,causalFailures:result.causalFailures,replayFailures:result.replayFailures,counterfactualChanges:result.counterfactualChanges,ruleCoverage:result.ruleCoverage,maxCauseDepth:result.maxCauseDepth,fixtures:result.fixtures.filter(item=>item.passed).length,batchRows:document.querySelectorAll("#batchResult tbody tr").length,fixtureRows:document.querySelectorAll("#batchChecks .batch-fixture").length,assertionRows:document.querySelectorAll("#assertionWrap tbody tr").length,currentStep,progress:document.getElementById("batchProgress").style.width,status:document.getElementById("batchStatus").textContent,buttonEnabled:!document.getElementById("runBatchButton").disabled,profileGoal:document.querySelector("#entityRows tr:first-child td:nth-child(4)")?.textContent.trim()};
    const marker=document.createElement("pre");marker.id="browser-batch-result";marker.textContent=JSON.stringify(summary);document.body.append(marker);
  } catch(error) { const marker=document.createElement("pre");marker.id="browser-batch-result";marker.textContent=JSON.stringify({result:"FAIL",error:String(error&&error.stack||error)});document.body.append(marker); }
})();
</script>`;
fs.writeFileSync(previewPath, html.replace("</body>", `${script}</body>`));

const run = spawnSync(chrome, [
  "--headless=new", "--disable-gpu", "--disable-extensions", "--no-first-run", "--no-default-browser-check",
  `--user-data-dir=${profile}`, "--virtual-time-budget=120000", "--dump-dom", pathToFileURL(previewPath).href
], { encoding: "utf8", timeout: 90000 });
if (run.error) throw run.error;
const marker = run.stdout.match(/<pre id="browser-batch-result">([\s\S]*?)<\/pre>/)?.[1];
if (run.status !== 0 || !marker) throw new Error(`Browser run failed: ${run.stderr || run.stdout}`);
const result = JSON.parse(marker.replaceAll("&quot;", '"').replaceAll("&amp;", "&").replaceAll("&lt;", "<").replaceAll("&gt;", ">"));
console.log(JSON.stringify(result));
if (result.result !== "PASS" || result.sampleCount !== 1000 || result.invariantFailures !== 0 || result.causalFailures !== 0 || result.replayFailures !== 0 || result.counterfactualChanges < 64 || result.ruleCoverage !== 6 || result.maxCauseDepth < 3 || result.fixtures !== 9 || result.batchRows !== 8 || result.fixtureRows !== 9 || result.assertionRows !== 18 || result.currentStep !== 3 || result.progress !== "100%" || !result.buttonEnabled || !result.status.includes("所有自动检查符合预期") || !result.profileGoal) process.exitCode = 1;
