import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID } from 'node:crypto';
import { states, defaultOutline, hash, parseCatalog, serializeCatalog, readScenarios, validate } from './catalog.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(here, '../..');
const docNames = {
  mechanics: 'docs/narrative-rebuild/decisions/033-Pibo情境闲聊与拍一拍调度机制.md',
  voice: 'docs/narrative-rebuild/decisions/034-Pibo恒定说话风格与中文首发.md',
  cooldown: 'docs/narrative-rebuild/decisions/044-拍一拍动作与文本冷却解耦.md',
};
const read = p => fs.readFileSync(p, 'utf8');
function atomic(p, contents) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const temp = `${p}.${randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temp, contents, { mode: fs.existsSync(p) ? fs.statSync(p).mode & 0o777 : 0o600 });
    fs.renameSync(temp, p);
  } finally { if (fs.existsSync(temp)) fs.unlinkSync(temp); }
}
const failure = (status, message) => Object.assign(new Error(message), { status });

export function createConsole(options = {}) {
  const root = options.root ?? defaultRoot;
  const harmony = options.harmony ?? path.resolve(root, '../HarmonyPibo');
  const dataDir = options.dataDir ?? path.join(here, '.local');
  const target = path.join(harmony, 'entry/src/main/resources/rawfile/pibo-home-pat.zh-Hans.jsonl');
  const ios = path.join(root, 'Pibo/Resources/pibo-home-pat.zh-Hans.jsonl');
  const scenarioPath = path.join(harmony, 'entry/src/main/ets/models/PiboPatDebugScenario.ets');
  const draftPath = path.join(dataDir, 'draft.json');
  const revisionDir = path.join(dataDir, 'revisions');
  const token = randomBytes(32).toString('hex');
  // Contract comes from the existing runtime resource and the exact debug scenario inventory.
  const scenarios = readScenarios(read(scenarioPath), parseCatalog(read(target)));
  const contractHash = hash(read(scenarioPath));
  const corePath = path.join(harmony, 'vendor/pibo-core/src/pat.rs');
  const core = read(corePath);
  const cargoPath = path.join(harmony, 'vendor/pibo-core/Cargo.toml');
  const coreSignature = () => hash(read(corePath) + read(cargoPath));
  const coreHash = coreSignature();
  const cooldown = Number(core.match(/PAT_SPEECH_COOLDOWN_DURATION_SECONDS: f64 = ([\d.]+)/)?.[1]);
  if (!Number.isFinite(cooldown)) throw new Error('无法读取 Core 文本冷却合同');
  const coreVersion = read(cargoPath).match(/^version = "([^"]+)"/m)?.[1];
  let draft = fs.existsSync(draftPath) ? JSON.parse(read(draftPath)) : {
    records: parseCatalog(read(target)), outline: structuredClone(defaultOutline),
    baseHash: hash(read(target)), savedAt: null,
  };
  let revision = hash(draft);
  const checked = (records, outline) => {
    const result = validate(records, scenarios, outline);
    if (result.errors.length) throw failure(422, result.errors.join('\n'));
    return result;
  };
  const history = () => fs.existsSync(revisionDir) ? fs.readdirSync(revisionDir).filter(n => n.endsWith('.json')).sort().reverse().map(n => {
    const r = JSON.parse(read(path.join(revisionDir, n)));
    return { id: n.slice(0, -5), at: r.at, kind: r.kind, hash: hash(serializeCatalog(r.records)), units: r.records.length };
  }) : [];
  function snapshot(kind, value) {
    const at = new Date().toISOString();
    const id = `${at.replace(/[:.]/g, '-')}-${randomUUID().slice(0, 8)}`;
    atomic(path.join(revisionDir, `${id}.json`), JSON.stringify({ ...value, kind, at }, null, 2));
    return id;
  }
  function save(value) {
    const nextDraft = { ...value, savedAt: new Date().toISOString() };
    atomic(draftPath, JSON.stringify(nextDraft, null, 2) + '\n');
    draft = nextDraft;
    revision = hash(draft);
  }
  function state() {
    if (fs.existsSync(draftPath)) { draft = JSON.parse(read(draftPath)); revision = hash(draft); }
    const source = read(target);
    const live = parseCatalog(source);
    const iosRecords = fs.existsSync(ios) ? parseCatalog(read(ios)) : null;
    return { token, revision, draft, live, scenarios, states, history: history(),
      validation: validate(draft.records, scenarios, draft.outline),
      runtime: { coreVersion, cooldown, target, ios, liveHash: hash(source),
        synced: serializeCatalog(draft.records) === serializeCatalog(live),
        conflict: draft.baseHash !== hash(source),
        iosAligned: iosRecords !== null && serializeCatalog(iosRecords) === serializeCatalog(live),
        contractChanged: contractHash !== hash(read(scenarioPath)) || coreHash !== coreSignature() },
    };
  }
  function checkRevision(body) {
    // Read disk as well: another running console may have saved to the same draft.
    if (fs.existsSync(draftPath)) {
      const disk = JSON.parse(read(draftPath));
      if (hash(disk) !== revision) { draft = disk; revision = hash(draft); }
    }
    if (body.revision !== revision) throw failure(409, '草稿已在其他窗口更新，请重新载入后合并修改。');
  }
  function mutate(route, body) {
    checkRevision(body);
    if (route === '/api/save') {
      checked(body.records, body.outline);
      snapshot('保存前草稿', draft);
      save({ records: body.records, outline: body.outline, baseHash: draft.baseHash });
    } else if (route === '/api/sync') {
      checked(draft.records, draft.outline);
      if (contractHash !== hash(read(scenarioPath)) || coreHash !== coreSignature()) throw failure(409, 'Core 或情境合同已更新，请重启控制台后重新核对。');
      const current = read(target);
      if (hash(current) !== draft.baseHash) throw failure(409, '鸿蒙正式文案已被外部修改，请先载入鸿蒙版本，避免覆盖他人修改。');
      const next = serializeCatalog(draft.records);
      if (next !== current) {
        snapshot('同步前鸿蒙版本', { records: parseCatalog(current), outline: draft.outline, baseHash: hash(current) });
        atomic(target, next);
      }
      save({ ...draft, baseHash: hash(next) });
    } else if (route === '/api/import-draft') {
      if (typeof body.source !== 'string' || body.source.length > 5_000_000) throw failure(422, '导入内容为空或超过 5 MB');
      let clean = body.source.replace(/^\uFEFF/, '').trim();
      clean = clean.replace(/^```(?:json|jsonl)?\s*/i, '').replace(/\s*```$/, '').trim();
      let imported;
      try { imported = parseCatalog(clean); } catch (error) { throw failure(422, `JSONL 解析失败：${error.message}`); }
      if (!imported.length) throw failure(422, '导入内容没有互动单元');
      const next = body.mode === 'replace' ? imported : [...draft.records, ...imported];
      checked(next, draft.outline);
      snapshot('导入前草稿', draft);
      save({ records: next, outline: draft.outline, baseHash: draft.baseHash });
    } else if (route === '/api/import-live') {
      snapshot('载入前草稿', draft);
      const source = read(target);
      const records = parseCatalog(source);
      checked(records, draft.outline);
      save({ records, outline: draft.outline, baseHash: hash(source) });
    } else if (route === '/api/restore') {
      if (!history().some(r => r.id === body.id)) throw failure(404, '找不到该历史版本');
      const prior = JSON.parse(read(path.join(revisionDir, `${body.id}.json`)));
      checked(prior.records, prior.outline);
      snapshot('恢复前草稿', draft);
      save({ records: prior.records, outline: prior.outline, baseHash: draft.baseHash });
    } else throw failure(404, '不存在的操作');
    return state();
  }
  const server = http.createServer(async (req, res) => {
    const send = (code, value, type = 'application/json; charset=utf-8') => {
      res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
        'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'" });
      res.end(type.startsWith('application/json') ? JSON.stringify(value) : value);
    };
    try {
      const addr = server.address();
      const allowedHosts = [`127.0.0.1:${addr.port}`, `localhost:${addr.port}`];
      if (!allowedHosts.includes(req.headers.host)) throw failure(403, '只允许本机访问');
      if (req.headers.origin && !allowedHosts.map(h => `http://${h}`).includes(req.headers.origin)) throw failure(403, '不允许跨站请求');
      if (req.headers['sec-fetch-site'] === 'cross-site') throw failure(403, '不允许跨站请求');
      const url = new URL(req.url, `http://${req.headers.host}`);
      if (req.method === 'GET') {
        if (url.pathname === '/api/state') return send(200, state());
        if (url.pathname === '/api/document') {
          const relative = docNames[url.searchParams.get('id')];
          if (!relative) throw failure(404, '找不到文档');
          return send(200, { path: relative, text: read(path.join(root, relative)) });
        }
        if (url.pathname === '/api/export') return send(200, serializeCatalog(draft.records), 'application/x-ndjson; charset=utf-8');
        const assets = { '/': ['index.html', 'text/html'], '/app.js': ['app.js', 'text/javascript'], '/style.css': ['style.css', 'text/css'] };
        const asset = assets[url.pathname];
        if (asset) return send(200, read(path.join(here, 'public', asset[0])), `${asset[1]}; charset=utf-8`);
        throw failure(404, '找不到页面');
      }
      if (req.method !== 'POST') throw failure(405, '不支持此方法');
      if (req.headers['x-console-token'] !== token) throw failure(403, '会话已失效，请刷新页面');
      if (!req.headers['content-type']?.startsWith('application/json')) throw failure(415, '仅支持 JSON');
      let body = '', bytes = 0;
      for await (const chunk of req) {
        bytes += chunk.length;
        if (bytes > 2_000_000) throw failure(413, '内容超过 2 MB');
        body += chunk;
      }
      let input;
      try { input = JSON.parse(body); } catch { throw failure(400, 'JSON 格式错误'); }
      if (!input || typeof input !== 'object') throw failure(400, '请求格式错误');
      return send(200, mutate(url.pathname, input));
    } catch (error) { send(error.status ?? 500, { error: error.message }); }
  });
  return server;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = createConsole({ harmony: process.env.PIBO_COPY_HARMONY_ROOT, dataDir: process.env.PIBO_COPY_DATA_DIR });
  const port = Number(process.env.PIBO_COPY_PORT ?? 4317);
  server.on('error', e => { console.error(`文案控制台启动失败：${e.message}`); process.exitCode = 1; });
  server.listen(port, '127.0.0.1', () => console.log(`Pibo 文案控制台 http://127.0.0.1:${server.address().port}`));
}
