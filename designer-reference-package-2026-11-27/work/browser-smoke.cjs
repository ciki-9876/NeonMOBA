const { spawnSync } = require("node:child_process");

const chrome = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const file = "file:///C:/Users/CIKI/Documents/Codex/2026-11-27/referenced-chatgpt-conversation-this-is-an/outputs/world-model-engineering-bench.html";
const profile = "C:\\Users\\CIKI\\Documents\\Codex\\2026-11-27\\referenced-chatgpt-conversation-this-is-an\\work\\chrome-smoke-profile";
const result = spawnSync(chrome, [
  "--headless=new",
  "--disable-gpu",
  "--disable-extensions",
  "--no-first-run",
  "--no-default-browser-check",
  `--user-data-dir=${profile}`,
  "--virtual-time-budget=2500",
  "--dump-dom",
  file
], { encoding: "utf8", timeout: 20000 });

if (result.error) throw result.error;
const html = result.stdout || "";
const rendered = html.replace(/<script\b[\s\S]*?<\/script>/gi, "");
const entityTable = rendered.match(/<tbody id="entityRows">([\s\S]*?)<\/tbody>/)?.[1] || "";
const entitySelector = rendered.match(/<select id="entitySelect">([\s\S]*?)<\/select>/)?.[1] || "";
const checks = {
  exitCode: result.status,
  title: rendered.includes("<title>生涯模拟｜选择测试</title>"),
  entities: (entityTable.match(/<tr>/g) || []).length,
  selectableEntities: (entitySelector.match(/<option\b/g) || []).length,
  chainScenario: rendered.includes("测试三人连锁：签入周屿"),
  teams: (rendered.match(/战队 \/ 10/g) || []).length,
  interventionControl: rendered.includes("你要做什么"),
  expectedAssertions: rendered.includes("预期会发生什么"),
  causalTrace: rendered.includes("赛季里发生的事"),
  stateSnapshot: rendered.includes("选手状态"),
  startsAtStepOne: /class="wizard-pane active" id="stepPane1"/.test(rendered),
  laterStepsLocked: /id="stepLink2" disabled/.test(rendered) && /id="stepLink3" disabled/.test(rendered),
  noRuntimeException: !/(Uncaught|TypeError|SyntaxError)/.test(result.stderr + html)
};

console.log(JSON.stringify(checks));
if (checks.exitCode !== 0 || !checks.title || checks.entities !== 50 || checks.selectableEntities !== 50 || !checks.chainScenario || checks.teams !== 1 || !checks.interventionControl || !checks.expectedAssertions || !checks.causalTrace || !checks.stateSnapshot || !checks.startsAtStepOne || !checks.laterStepsLocked || !checks.noRuntimeException) {
  process.exitCode = 1;
}
