import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createConsole } from '../server.mjs';
import { parseCatalog, readScenarios, validate, defaultOutline, serializeCatalog } from '../catalog.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const harmony = path.resolve(root, '../HarmonyPibo');
const resource = 'entry/src/main/resources/rawfile/pibo-home-pat.zh-Hans.jsonl';
const scenarioFile = 'entry/src/main/ets/models/PiboPatDebugScenario.ets';
const original = fs.readFileSync(path.join(harmony, resource), 'utf8');
const records = parseCatalog(original);
const scenarios = readScenarios(fs.readFileSync(path.join(harmony, scenarioFile), 'utf8'), records);
const clone = () => structuredClone(records);

test('the live catalog and all 27 debug scenarios agree', () => {
  assert.equal(scenarios.length, 27);
  assert.deepEqual(validate(records, scenarios, defaultOutline).errors, []);
  assert.equal(serializeCatalog(records), original);
});
test('rejects unsupported triggers, semantic side effects and missing coverage', () => {
  const r = clone(); r[0].action = 'rest'; r[1].context = 'invented';
  const errors = validate(r, scenarios).errors.join(' ');
  assert.match(errors, /动作/); assert.match(errors, /Core/); assert.match(errors, /3 个单元/);
  assert.match(validate(r.filter(r => r.state !== 'sleeping'), scenarios).errors.join(), /全部/);
});
test('validates runtime-specific placeholders, braces and stage reachability', () => {
  const r = clone(); r[0].lines[0].text = '{steps}';
  assert.match(validate(r, scenarios).errors.join(), /运行时值/);
  r[0].lines[0].text = 'hello {';
  assert.match(validate(r, scenarios).errors.join(), /大括号/);
  for (const row of r.filter(r => r.state === 'sleeping')) row.lines.forEach(l=>l.stages=['event03']);
  assert.match(validate(r, scenarios).errors.join(), /没有可用台词/);
});
test('permits growing authored pools without changing Core scenarios', () => {
  const r = clone(); r.push({...r.find(r=>r.context==='idle'),lines:[{text:'测试内容'}]});
  assert.deepEqual(validate(r, scenarios).errors, []);
  r.at(-1).lines[0].text = '';
  assert.match(validate(r, scenarios).errors.join(), /为空/);
});

test('HTTP save → sync → restore, durable storage, conflicts and local-only security', async t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pibo-copy-test-'));
  const h = path.join(temp, 'HarmonyPibo'), dataDir = path.join(temp, 'drafts');
  for (const file of [resource,scenarioFile,'vendor/pibo-core/src/pat.rs','vendor/pibo-core/Cargo.toml']) {
    fs.mkdirSync(path.dirname(path.join(h,file)),{recursive:true});
    fs.copyFileSync(path.join(harmony,file),path.join(h,file));
  }
  const server = createConsole({root,harmony:h,dataDir});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(async()=>{await new Promise(resolve=>server.close(resolve));fs.rmSync(temp,{recursive:true,force:true});});
  const base = `http://127.0.0.1:${server.address().port}`;
  let s = await (await fetch(base+'/api/state')).json();
  const post = (route,body,extra={}) => fetch(base+route,{method:'POST',headers:{'Content-Type':'application/json','X-Console-Token':s.token,...extra},body:JSON.stringify({revision:s.revision,...body})});
  const edited = clone(); edited[3].lines[0].text = '这是一次隔离的同步测试。';
  const res = await post('/api/save',{records:edited,outline:defaultOutline});
  assert.equal(res.status,200); s=await res.json();
  assert.equal(fs.readFileSync(path.join(h,resource),'utf8'),original,'saving a draft must not edit runtime');
  assert.equal(JSON.parse(fs.readFileSync(path.join(dataDir,'draft.json'))).records[3].lines[0].text,edited[3].lines[0].text);
  const reopened = createConsole({root,harmony:h,dataDir});
  await new Promise(resolve=>reopened.listen(0,'127.0.0.1',resolve));
  try {
    const persisted = await (await fetch(`http://127.0.0.1:${reopened.address().port}/api/state`)).json();
    assert.equal(persisted.draft.records[3].lines[0].text, edited[3].lines[0].text, 'a new server must recover the saved draft');
  } finally { await new Promise(resolve=>reopened.close(resolve)); }
  const stale = await post('/api/save',{revision:'old',records:edited,outline:defaultOutline});
  assert.equal(stale.status,409);
  const bad = clone(); bad[3].lines=[];
  assert.equal((await post('/api/save',{records:bad,outline:defaultOutline})).status,422);
  assert.equal((await post('/api/sync',{}, {Origin:'https://evil.example'})).status,403);
  assert.equal((await post('/api/sync',{}, {'X-Console-Token':'wrong'})).status,403);
  const forbiddenHost = await new Promise((resolve,reject)=>{http.get(base+'/api/state',{headers:{Host:'evil.example'}},res=>{res.resume();resolve(res.statusCode);}).on('error',reject);});
  assert.equal(forbiddenHost,403);
  s=await (await post('/api/sync',{})).json();
  assert.equal(parseCatalog(fs.readFileSync(path.join(h,resource),'utf8'))[3].lines[0].text,edited[3].lines[0].text);
  assert.equal(s.runtime.synced,true);
  const backup=s.history.find(r=>r.kind==='同步前鸿蒙版本');
  assert.ok(backup);
  s=await (await post('/api/restore',{id:backup.id})).json();
  assert.equal(s.draft.records[3].lines[0].text,records[3].lines[0].text);
  assert.equal(s.live[3].lines[0].text,edited[3].lines[0].text,'restoration must only stage a draft');
  s=await (await post('/api/sync',{})).json();
  assert.equal(fs.readFileSync(path.join(h,resource),'utf8'),original);
  fs.appendFileSync(path.join(h,resource),'\n');
  assert.equal((await post('/api/sync',{})).status,409,'external edits may not be overwritten');
  s=await (await post('/api/import-live',{})).json();
  assert.equal(s.runtime.conflict,false);
  assert.equal((await post('/api/restore',{id:'../../somefile'})).status,404);
  fs.appendFileSync(path.join(h,'vendor/pibo-core/src/pat.rs'),'\n');
  assert.equal((await post('/api/sync',{})).status,409,'changed Core requires restart');
  assert.equal(fs.readFileSync(path.join(harmony,resource),'utf8'),original,'tests never modify actual app resource');
});
