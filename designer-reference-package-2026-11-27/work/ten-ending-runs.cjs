const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const source = fs.readFileSync(path.join(root, "outputs", "world-model-engineering-bench.html"), "utf8");
const chrome = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const previewPath = path.join(__dirname, "ten-ending-runs.html");
const profile = path.join(__dirname, "ten-ending-runs-profile");
const runner = String.raw`<script>
try {
  const scenarios = [
    {id:"01",title:"签下周屿加入星火",action:"chain",entity:"C",group:"G1"},
    {id:"02",title:"林澈转入零度",action:"move",entity:"A",group:"G2"},
    {id:"03",title:"唐可转入赤曜",action:"move",entity:"D",group:"G3"},
    {id:"04",title:"顾临转入星火",action:"move",entity:"E",group:"G1"},
    {id:"05",title:"林澈专练操作 +10",action:"train",entity:"A",attribute:"skill",amount:"10"},
    {id:"06",title:"周屿专练操作 +10",action:"train",entity:"C",attribute:"skill",amount:"10"},
    {id:"07",title:"林澈专练默契 +10",action:"train",entity:"A",attribute:"collaboration",amount:"10"},
    {id:"08",title:"林澈与苏遥双排 +10",action:"relation",entity:"A",partner:"B",amount:"10"},
    {id:"09",title:"周屿与唐可双排 +10",action:"relation",entity:"C",partner:"D",amount:"10"},
    {id:"10",title:"不作赛前干预",action:"none",entity:"A"}
  ];
  const setValue=(id,value)=>{const control=document.getElementById(id);if(value!==undefined&&value!==null){control.value=String(value);control.dispatchEvent(new Event("change",{bubbles:true}));}};
  const results=[];
  for(const scenario of scenarios){
    setValue("actionSelect",scenario.action);
    setValue("entitySelect",scenario.entity);
    setValue("groupSelect",scenario.group);
    setValue("attributeSelect",scenario.attribute);
    setValue("partnerSelect",scenario.partner);
    setValue("deltaSelect",scenario.amount);
    setValue("horizonSelect",5);
    const chosenConfig=readConfig();
    document.getElementById("runButton").click();
    const state=JSON.parse(JSON.stringify(world));
    const entity=id=>state.entities.find(person=>person.id===id);
    const events=state.trace.slice().sort((a,b)=>Number(a.id.slice(2))-Number(b.id.slice(2))).map(event=>({id:event.id,season:event.step,rule:event.rule,title:event.title,description:event.description,chain:event.chain,actors:event.actors||[],intent:event.intent||"",preconditions:event.preconditions||[],effects:event.effects||[],causeEventIds:event.causeEventIds||[]}));
    const plotEvents=events.filter(event=>["R-04","R-05","R-06","R-07","R-08","R-09"].includes(event.rule));
    results.push({id:scenario.id,choice:scenario.title,chosenConfig,actualConfig:latestAction,seasonCount:state.step,allChecksPassed:latestAssertions.every(assertion=>assertion.passed),keyPeople:["A","B","C","D","E"].map(id=>{const p=entity(id);return {id,name:entityName(id),team:teamName(p.group),lineup:p.lineup,morale:p.morale,goal:goalName(p.careerGoal),mentor:p.mentorId?entityName(p.mentorId):null,skill:p.skill,collaboration:p.collaboration,discipline:p.discipline};}),relations:{AB:relationValue(state,"A","B"),CD:relationValue(state,"C","D"),AE:relationValue(state,"A","E")},storyEvents:plotEvents.filter(event=>event.actors.some(id=>["A","B","C","D","E"].includes(id))).map(event=>({season:event.season,title:event.title,characters:event.actors.map(id=>entityName(id)),description:event.description,effects:event.effects,causes:event.causeEventIds})),backgroundPlotEvents:plotEvents.length-plotEvents.filter(event=>event.actors.some(id=>["A","B","C","D","E"].includes(id))).length,eventCount:state.trace.length,signature:signature(state)});
  }
  const output=document.createElement("pre");output.id="ten-ending-result";output.textContent=JSON.stringify(results);document.body.append(output);
} catch(error) {const output=document.createElement("pre");output.id="ten-ending-result";output.textContent=JSON.stringify({error:String(error&&error.stack||error)});document.body.append(output);}
</script>`;
fs.writeFileSync(previewPath, source.replace("</body>", `${runner}</body>`));
const run=spawnSync(chrome,["--headless=new","--disable-gpu","--disable-extensions","--no-first-run","--no-default-browser-check",`--user-data-dir=${profile}`,"--virtual-time-budget=20000","--dump-dom",pathToFileURL(previewPath).href],{encoding:"utf8",timeout:30000});
if(run.error)throw run.error;
const match=run.stdout.match(/<pre id="ten-ending-result">([\s\S]*?)<\/pre>/)?.[1];
if(run.status!==0||!match)throw new Error(`Browser run failed: ${run.stderr||run.stdout}`);
const result=JSON.parse(match.replaceAll("&quot;",'"').replaceAll("&amp;","&").replaceAll("&lt;","<").replaceAll("&gt;",">"));
if(!Array.isArray(result))throw new Error(JSON.stringify(result));
fs.writeFileSync(path.join(__dirname,"ten-ending-runs.json"),JSON.stringify(result,null,2),"utf8");
console.log(JSON.stringify(result.map(item=>({id:item.id,choice:item.choice,chosenConfig:item.chosenConfig,actualConfig:item.actualConfig,seasonCount:item.seasonCount,allChecksPassed:item.allChecksPassed,people:item.keyPeople.map(({name,team,lineup,morale,mentor,skill,collaboration,discipline})=>({name,team,lineup,morale,mentor,skill,collaboration,discipline})),relations:item.relations,storyEvents:item.storyEvents,signature:item.signature})),null,2));
const mismatchedChoice=result.some(item=>item.chosenConfig.action!==item.actualConfig.action||(item.chosenConfig.action==="move"&&item.chosenConfig.group!==item.actualConfig.group)||(item.chosenConfig.action==="relation"&&item.chosenConfig.partner!==item.actualConfig.partner));
if(result.length!==10||mismatchedChoice||result.some(item=>item.seasonCount!==5||!item.allChecksPassed)||new Set(result.map(item=>item.signature)).size!==10)process.exitCode=1;
