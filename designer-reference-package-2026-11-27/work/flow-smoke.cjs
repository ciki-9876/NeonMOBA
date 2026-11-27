const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const htmlPath = path.join(__dirname, "..", "outputs", "world-model-engineering-bench.html");
const html = fs.readFileSync(htmlPath, "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

class Element {
  constructor(id) {
    this.id = id;
    this.value = ({ actionSelect: "move", entitySelect: "A", groupSelect: "G2", attributeSelect: "skill", deltaSelect: "5", partnerSelect: "B", horizonSelect: "5" })[id] || "";
    this.innerHTML = "";
    this.textContent = "";
    this.hidden = false;
    this.disabled = false;
    this.style = {};
    this.handlers = {};
    this.classes = new Set();
    this.classList = {
      add: name => this.classes.add(name),
      remove: name => this.classes.delete(name),
      toggle: (name, force) => {
        const enabled = force === undefined ? !this.classes.has(name) : force;
        if (enabled) this.classes.add(name);
        else this.classes.delete(name);
        return enabled;
      }
    };
  }

  addEventListener(name, handler) { this.handlers[name] = handler; }
}

const elements = new Map();
const document = {
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, new Element(id));
    return elements.get(id);
  },
  querySelectorAll() { return []; }
};
const context = vm.createContext({ document, setTimeout: () => 1, clearTimeout: () => {}, Date });
const api = vm.runInContext(script + "\n;({runExperiment,performRebirth,getWorld:()=>world,getChecks:()=>latestAssertions,getStep:()=>currentStep,getMaxStep:()=>maxReachedStep,signature})", context);
const ensure = (condition, message) => { if (!condition) throw new Error(message); };

function run(action, values = {}) {
  document.getElementById("actionSelect").value = action;
  for (const [id, value] of Object.entries(values)) document.getElementById(id).value = String(value);
  api.runExperiment();
  const failures = api.getChecks().filter(check => !check.passed);
  ensure(failures.length === 0, `${action} failures: ${JSON.stringify(failures)}`);
  ensure(document.getElementById("stepPane2").classes.has("active"), "running the choice reveals step two");
  return api.getChecks().length;
}

ensure(api.getStep() === 1 && api.getMaxStep() === 1, "initial wizard step");
ensure(document.getElementById("stepPane1").classes.has("active") && !document.getElementById("stepPane2").classes.has("active"), "only step one is initially visible");
ensure(document.getElementById("stepLink2").disabled && document.getElementById("stepLink3").disabled, "later steps start locked");
ensure(!document.getElementById("groupField").hidden && document.getElementById("attributeField").hidden && document.getElementById("deltaField").hidden && document.getElementById("partnerField").hidden, "transfer only shows transfer controls");
const initialWorld = api.getWorld();
ensure(initialWorld.entities.length === 50 && new Set(initialWorld.entities.map(entity => entity.id)).size === 50, "baseline contains 50 uniquely identified competitors");
ensure(Object.keys(initialWorld.relations).length === 1225 && new Set(initialWorld.entities.map(entity => entity.group)).size === 10, "baseline has all 1,225 relationships across 10 teams");
ensure(initialWorld.entities.every(entity => initialWorld.entities.filter(other => other.group === entity.group && other.lineup === "starter").length <= 5), "baseline roster capacity is valid");
ensure((document.getElementById("entitySelect").innerHTML.match(/<option/g) || []).length === 50, "all 50 competitors are selectable");
let scenarioAssertions = 0;
scenarioAssertions += run("move", { entitySelect: "A", groupSelect: "G2", horizonSelect: "5" });
const fullTeamTransfer = api.getWorld().entities.find(entity => entity.id === "A");
ensure(fullTeamTransfer.group === "G3" && fullTeamTransfer.lineup === "starter", "a benched player with a starting-role goal transfers to an open team next season");
ensure(api.getWorld().entities.every(entity => api.getWorld().entities.filter(other => other.group === entity.group && other.lineup === "starter").length <= 5), "ordinary transfers preserve roster capacity across all teams");
const firstReplay = api.signature(api.getWorld());
scenarioAssertions += run("move", { entitySelect: "A", groupSelect: "G2", horizonSelect: "5" });
ensure(api.signature(api.getWorld()) === firstReplay, "same choice replays deterministically");

document.getElementById("actionSelect").value = "train";
document.getElementById("actionSelect").handlers.change();
ensure(api.getStep() === 1 && api.getChecks().length === 0, "changing input returns to step one and clears stale results");
ensure(document.getElementById("groupField").hidden && !document.getElementById("attributeField").hidden && !document.getElementById("deltaField").hidden && document.getElementById("partnerField").hidden, "training only shows training controls");
scenarioAssertions += run("train", { entitySelect: "A", attributeSelect: "skill", deltaSelect: "5", horizonSelect: "3" });
scenarioAssertions += run("relation", { entitySelect: "A", partnerSelect: "B", deltaSelect: "20", horizonSelect: "2" });
ensure(api.getWorld().trace.some(item => item.rule === "R-04"), "relationship threshold triggers pair event");
ensure(document.getElementById("partnerField").hidden === false && document.getElementById("groupField").hidden, "pairing only shows partner control");
scenarioAssertions += run("none", { entitySelect: "A", horizonSelect: "1" });

document.getElementById("actionSelect").value = "chain";
document.getElementById("actionSelect").handlers.change();
ensure(document.getElementById("entitySelect").value === "C" && document.getElementById("entitySelect").disabled, "chain test fixes Zhou Yu as the signing target");
ensure(document.getElementById("groupSelect").value === "G1" && document.getElementById("groupSelect").disabled && !document.getElementById("groupField").hidden, "chain test fixes Starfire as the destination");
ensure(document.getElementById("expectedList").innerHTML.includes("首发竞争") && document.getElementById("expectedList").innerHTML.includes("新队友"), "chain preview shows the expected causal sequence");
scenarioAssertions += run("chain", { horizonSelect: "1" });
const chainWorld = api.getWorld();
const lin = chainWorld.entities.find(entity => entity.id === "A");
const zhou = chainWorld.entities.find(entity => entity.id === "C");
const gu = chainWorld.entities.find(entity => entity.id === "E");
ensure(lin.group === "G3" && lin.lineup === "starter" && zhou.group === "G1" && gu.group === "G3", "three character changes follow the expected chain");
ensure(chainWorld.entities.length === 50 && new Set(chainWorld.entities.map(entity => entity.id)).size === 50, "all 50 competitors retain separate state");
ensure(Object.keys(chainWorld.relations).length === 1225, "all 1,225 pair relationships are represented");
ensure(chainWorld.relations["A|E"] === 8, "new teammates gain the expected relationship increase");
ensure(chainWorld.trace.some(item => item.rule === "R-05") && chainWorld.trace.some(item => item.rule === "R-06"), "both lineup competition and transfer events are recorded");
const causalHtml = document.getElementById("causalList").innerHTML;
ensure(causalHtml.indexOf("周屿签入星火战队") < causalHtml.indexOf("首发位置调整") && causalHtml.indexOf("首发位置调整") < causalHtml.indexOf("替补选手为上场机会转会"), "visible causal history reads from cause to consequence");
const chainReplay = api.signature(chainWorld);
scenarioAssertions += run("chain", { horizonSelect: "1" });
ensure(api.signature(api.getWorld()) === chainReplay, "three character chain replays deterministically");
for (let horizon = 2; horizon <= 5; horizon++) {
  scenarioAssertions += run("chain", { horizonSelect: String(horizon) });
  ensure(api.getWorld().step === horizon, `chain keeps the selected ${horizon}-season horizon`);
}

document.getElementById("toCheckButton").handlers.click();
ensure(api.getStep() === 3 && document.getElementById("stepPane3").classes.has("active") && !document.getElementById("stepPane1").classes.has("active"), "step three unlocks after reviewing step two");
api.performRebirth();
ensure(api.getChecks().every(check => check.passed), "rebirth assertions pass");
ensure(api.getWorld().step === 0 && api.getWorld().entities[0].skill === 62 && api.getWorld().knowledge.length > 0, "rebirth resets state and retains memory");
ensure(api.getWorld().knowledge.some(item => item.includes("三人连锁测试")), "rebirth retains the latest chain experiment as memory");

console.log(JSON.stringify({ result: "PASS", scenarioAssertions, rebirthAssertions: api.getChecks().length, entities: api.getWorld().entities.length, relationships: Object.keys(api.getWorld().relations).length, stepFlow: "1 → 2 → 3", deterministicReplay: true }));
