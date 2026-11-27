const fs = require("node:fs");
const path = require("node:path");

const inputPath = path.join(__dirname, "three-character-ending-runs.json");
const outputPath = path.join(__dirname, "..", "outputs", "three-character-modular-validation.md");
const runs = JSON.parse(fs.readFileSync(inputPath, "utf8"));
const FOCUS = ["A", "B", "C"];
const GOAL_LINES = { "争取首发": "争取首发的目标仍在前方。", "带队争冠": "带队争冠的目标仍在前方。" };
const ATTRIBUTE_NAMES = { skill: "操作", collaboration: "团队默契", discipline: "训练稳定" };
const TEAM_NAMES = { G1: "星火战队", G2: "零度战队", G3: "赤曜战队", G4: "霜刃战队", G5: "远帆战队", G6: "山海战队", G7: "青云战队", G8: "白鹭战队", G9: "长夜战队", G10: "朝夕战队" };
const initialRelations = { AB: 25, BC: 3 };

function person(run, id) { return run.people.find(item => item.id === id); }
function lineup(personState) { return personState.lineup === "starter" ? "首发" : "替补"; }
function displayName(id) { return person({ people: runs[0].people }, id)?.name || id; }
function openingFragment(run) {
  const config = run.actualConfig;
  const target = person(run, config.entity);
  if (config.action === "chain") return "周屿签约加入星火。";
  if (config.action === "move") return `${target.name}在赛季开始前转入${teamNameFromConfig(run)}。`;
  if (config.action === "train") return `${target.name}把训练重点放在${ATTRIBUTE_NAMES[config.attribute]}上。`;
  if (config.action === "relation") {
    const partnerId = config.partner;
    const key = [config.entity, partnerId].sort().join("");
    const before = initialRelations[key];
    const after = run.relationships[key];
    return `${target.name}与${displayName(partnerId)}安排双排，关系值从 ${before} 变为 ${after}。`;
  }
  return "本赛季没有安排签约、训练或双排。";
}
function teamNameFromConfig(run) {
  return TEAM_NAMES[run.actualConfig.group] || run.actualConfig.group;
}
function eventFragment(event) {
  if (event.title === "首发位置调整") return `首发变动：${event.description}`;
  if (event.title === "替补选手为上场机会转会") return `转会连锁：${event.description}`;
  if (event.title === "队长主动带练队友") return `带练事件：${event.description}`;
  if (event.title === "默契搭档事件触发") return `搭档事件：${event.description}`;
  if (event.title === "首发竞争演变为队内摩擦") return `队内摩擦：${event.description}`;
  return `${event.title}：${event.description}`;
}
function stateFragment(run) {
  const rows = FOCUS.map(id => {
    const state = person(run, id);
    const mentorText = state.mentor ? `，导师为${state.mentor}` : "";
    const goalText = GOAL_LINES[state.goal] || "人物目标仍在前方。";
    let keyValue = "";
    if (run.actualConfig.action === "train" && run.actualConfig.entity === id) {
      keyValue = run.actualConfig.attribute === "skill"
        ? `，操作值 ${state.skill} / 成长上限 ${state.potential}`
        : `，${ATTRIBUTE_NAMES[run.actualConfig.attribute]}值 ${state[run.actualConfig.attribute]}`;
    }
    return `${state.name}在${state.team}${lineup(state)}${mentorText}${keyValue}。${goalText}`;
  });
  return `五季后：${rows.join("")}`;
}
function endingFragment(run) {
  if (run.actualConfig.action === "relation") {
    const key = [run.actualConfig.entity, run.actualConfig.partner].sort().join("");
    const relation = run.relationships[key];
    return relation >= 40 ? `关系达到固定搭档门槛40，固定搭档事件已触发。` : `关系尚未达到固定搭档门槛40，本轮没有形成固定搭档。`;
  }
  if (run.storyEvents.length) return "本轮结局由上列人物事件与五季末状态共同组成。";
  return "本轮没有触发三名主角之间新的搭档或导师事件，结局落在选择造成的状态变化上。";
}
function compose(run) {
  const chunks = [openingFragment(run), ...run.storyEvents.map(eventFragment), stateFragment(run), endingFragment(run)];
  return chunks.join("\n\n");
}

const outputs = runs.map(run => ({ ...run, modularText: compose(run) }));
const missingFocus = outputs.filter(run => FOCUS.some(id => !run.modularText.includes(person(run, id).name)));
const passedRuns = outputs.filter(run => run.allChecksPassed).length;
const uniqueTexts = new Set(outputs.map(run => run.modularText)).size;
const triggeredEvents = outputs.reduce((sum, run) => sum + run.storyEvents.length, 0);
function sourceFactsPresent(run) {
  const config = run.actualConfig;
  const text = run.modularText;
  const selected = run.chosenConfig;
  if (selected.action !== config.action) return false;
  if (config.action === "move" && (selected.entity !== config.entity || selected.group !== config.group)) return false;
  if (config.action === "train" && (selected.entity !== config.entity || selected.attribute !== config.attribute || selected.amount !== config.amount)) return false;
  if (config.action === "relation" && (selected.entity !== config.entity || selected.partner !== config.partner || selected.amount !== config.amount)) return false;
  if (config.action === "chain" && (!text.includes("周屿签约加入星火") || !text.includes("林澈"))) return false;
  if (config.action === "move" && !text.includes(`${person(run, config.entity).name}在赛季开始前转入${TEAM_NAMES[config.group]}`)) return false;
  if (config.action === "train" && !text.includes(`${person(run, config.entity).name}把训练重点放在${ATTRIBUTE_NAMES[config.attribute]}`)) return false;
  const relationKey = [config.entity, config.partner].sort().join("");
  if (config.action === "relation" && (!text.includes(person(run, config.entity).name) || !text.includes(person(run, config.partner).name) || !text.includes(String(run.relationships[relationKey])))) return false;
  if (!run.storyEvents.every(event => text.includes(event.description))) return false;
  return FOCUS.every(id => text.includes(`${person(run, id).name}在${person(run, id).team}${lineup(person(run, id))}`));
}
const factualRuns = outputs.filter(sourceFactsPresent).length;
const markdown = [
  "# 三人剧情的模块化文本验证",
  "",
  "本次使用同一组十个 Demo 结果：林澈、苏遥、周屿从相同初始状态出发，每轮推进五个赛季。底层运行结果保存在 `three-character-ending-comparison.md` 对应的十个编号中；本文件只更换结局表达方式。",
  "",
  "## 固定片段库与拼接规则",
  "",
  "每个结局由四类预先写定的片段组成：",
  "",
  "1. **选择开场**：按签约/转会、训练、双排三类选择调用固定句式，并填入角色、队伍、属性或关系值。",
  "2. **事件片段**：只在模拟器真实触发首发调整、转会、带练、搭档或摩擦事件时插入对应句子。",
  "3. **五季状态**：按林澈、苏遥、周屿的最终战队、位置、导师、目标和本轮相关属性填槽。",
  "4. **收尾片段**：关系达到或未达到40门槛时分别选择固定句；无主角事件时使用“状态变化型”收尾。",
  "",
  "这些句子写在固定片段库中；运行时只读结构化结果、选择适用片段并填入字段，不调用大模型。完整拼接器见 `work/modular-ending-composer.cjs`。",
  "",
  `## 执行检查：${passedRuns}/10 轮基础检查通过；${factualRuns}/10 段的选择、事件和人物状态都能对应到运行记录；${uniqueTexts}/10 段文本不同；共插入 ${triggeredEvents} 条与三名主角相关的实际剧情事件。`,
  "",
  "大模型版本与前一轮逐条对应，可在 [三人十种结局对照](three-character-ending-comparison.md) 中查看。",
  "",
  ...outputs.flatMap(run => [
    `## ${run.id}｜${run.choice}`,
    "",
    run.modularText,
    "",
    `实际赛果编号：${run.signature}。` ,
    ""
  ]),
  "## 对照观察",
  "",
  "- 模块化文本把每个结果都稳定呈现为“选择 → 实际事件 → 五季状态”，事实容易核对，也能明确表现关系未达门槛、没有触发事件等安静结局。",
  "- 这组片段库包含少量选择句式和事件句式；十条文本仍共享同一结构。变化主要来自名字、队伍、属性与事件槽位，语气和节奏的差别有限。",
  "- 大模型版本的语言更灵活；模板版本的事实边界更容易控制。要提高无大模型文本的戏剧性，需要继续投入角色专属对白、转折场景和多种收尾片段，而不是为每种状态组合各写一整篇。",
  "- 本次只验证了片段选择、事实填充和十种输出的完整性。文本是否足够精彩仍是设计评审问题，不应由脚本自判。",
  ""
].join("\n");

if (runs.length !== 10 || passedRuns !== 10 || factualRuns !== 10 || uniqueTexts !== 10 || missingFocus.length) {
  throw new Error(`Modular composition check failed: runs=${runs.length}, passed=${passedRuns}, factual=${factualRuns}, unique=${uniqueTexts}, missingFocus=${missingFocus.map(run => run.id).join(",")}`);
}
fs.writeFileSync(outputPath, markdown, "utf8");
console.log(JSON.stringify({ result: "PASS", runs: runs.length, passedRuns, factualRuns, uniqueTexts, triggeredEvents, missingFocus: missingFocus.length, outputPath }));
