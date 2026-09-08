const $ = s => document.querySelector(s);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let data, records, outline, dirty = false, view = 'catalog', state = 'stable', selected = 'stable.idle', chapter = 0, query = '', previewLine = 0;
let sample = { steps: '8246', sleepDuration: '7小时48分', stage: 'unresponded' };
const keyOf = r => `${r.state}.${r.context}`;
const pool = () => records.map((r, index) => ({ ...r, index })).filter(r => keyOf(r) === selected);
const current = () => pool()[chapter];
const scenario = () => data.scenarios.find(s => s.id === selected);
const label = id => data.states.find(s => s.id === id)?.title ?? id;
function notice(text, error = false) { const n = $('#notice'); n.textContent = text; n.className = error ? 'shown error' : 'shown'; }
async function api(route, body) {
  const res = await fetch(route, body ? { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Console-Token': data.token }, body: JSON.stringify({ ...body, revision: data.revision }) } : {});
  const result = await res.json();
  if (!res.ok) throw new Error(result.error ?? `请求失败 ${res.status}`);
  return result;
}
function accept(next) { data = next; records = structuredClone(data.draft.records); outline = structuredClone(data.draft.outline); dirty = false; chapter = Math.min(chapter, pool().length - 1); if(chapter < 0) chapter=0; render(); }
function markDirty() { dirty = true; $('#save').disabled = false; $('#save-status').textContent = '有未保存修改'; renderPreview(); }
function modal(title, body) { $('#dialog-content').innerHTML = `<h2>${esc(title)}</h2>${body}`; $('#dialog').showModal(); }
function nav() {
  return `<aside class="sidebar"><a class="brand" href="/">pibo<span>文案工作台</span></a><div class="workspace-tag">本机工作区 <i></i></div><div class="nav-label">内容管理</div><button class="nav ${view==='catalog'?'active':''}" data-view="catalog">拍一拍文案 <span>${records.length}</span></button><button class="nav ${view==='outline'?'active':''}" data-view="outline">文案大纲</button><button class="nav ${view==='publish'?'active':''}" data-view="publish">同步与版本 ${data.runtime.conflict?'!':''}</button><div class="nav-label">六种主状态</div>${data.states.map(s=>`<button class="state-nav ${view==='catalog'&&state===s.id?'active':''}" data-state="${s.id}"><span class="dot ${s.id}"></span>${s.title}<small>${records.filter(r=>r.state===s.id).length}</small></button>`).join('')}<div class="sidebar-bottom">HarmonyOS 优先<br><small>中文 · Core ${esc(data.runtime.coreVersion)}</small></div></aside>`;
}
function render() {
  $('#app').innerHTML = `${nav()}<div class="workspace"><header class="topbar"><div><span class="eyebrow">PIBO / CONTENT STUDIO</span><span class="top-context">${view==='catalog'?'拍一拍 / '+label(state):view==='outline'?'文案大纲':'同步与版本'}</span></div><div class="top-actions"><span id="save-status">${dirty?'有未保存修改':data.draft.savedAt?'草稿已保存':'已载入鸿蒙版本'}</span><button id="save" ${dirty?'':'disabled'}>保存草稿</button><button class="secondary" id="go-publish">同步鸿蒙 ↗</button></div></header><main>${view==='catalog'?catalogView():view==='outline'?outlineView():publishView()}</main></div>`;
  bind();
  if(view==='catalog') renderPreview();
}
function catalogView() {
  const s = scenario();
  const visible = data.scenarios.filter(s=>s.state===state).filter(s=>`${s.title} ${s.id} ${s.trigger} ${records.filter(r=>keyOf(r)===s.id).map(r=>r.lines.map(l=>l.text).join(' ')).join(' ')}`.toLowerCase().includes(query.toLowerCase()));
  const p = pool(), c=current();
  return `<section class="page-heading"><div><h1>${label(state)}时，Pibo 会说什么</h1><p>${esc(outline.stateNotes[state])}</p></div><div class="metric"><label class="mobile-state">主状态 <select id="mobile-state">${data.states.map(st=>`<option value="${st.id}" ${st.id===state?'selected':''}>${st.title}</option>`).join('')}</select></label><b>${data.scenarios.filter(s=>s.state===state).length}</b> 个情境 <b>${records.filter(r=>r.state===state).length}</b> 个单元</div></section><div class="studio-grid"><section class="scene-list"><label class="search-label" for="search">查找当前状态文案</label><input id="search" type="search" placeholder="搜索情境、触发条件、台词" value="${esc(query)}"><div class="list-caption">情境 / 按运行时分类</div>${visible.length?visible.map(s=>`<button class="scene ${selected===s.id?'selected':''}" data-scene="${s.id}"><span class="scene-top"><strong>${esc(s.title)}</strong><small>${records.filter(r=>keyOf(r)===s.id).length} 单元</small></span><span class="scene-category">${esc(s.category)}</span><span class="scene-excerpt">${esc(records.find(r=>keyOf(r)===s.id)?.lines[0]?.text)}</span></button>`).join(''):'<p class="empty">没有匹配的情境。试试其他词语。</p>'}</section><section class="editor"><div class="editor-heading"><div><span class="pill">${esc(s.category)}</span><h2>${esc(s.title)}</h2></div><code>${esc(s.id)}</code></div><div class="trigger"><span class="small-label">什么时候说</span><p>${esc(s.trigger)}</p><span class="small-label">说完之后</span><p>${esc(s.lifecycle)}</p></div><div class="chapter-header"><h3>互动单元</h3><span>${p.length} 个 · 固定顺序</span><button class="text-button" id="add-chapter" ${selected==='stable.touchDiscovery'?'disabled':''}>＋ 新增</button></div><div class="chapter-tabs">${p.map((r,i)=>`<button class="${chapter===i?'chosen':''}" data-chapter="${i}">${String(i+1).padStart(2,'0')} <small>${r.lines.length}句</small></button>`).join('')}</div><div class="unit-meta"><span>说话者 ${esc(c.speaker==='pibo'?'Pibo':'系统')}</span><span>语义动作 <code>${esc(c.action)}</code></span></div><div id="lines">${c.lines.map((line,i)=>`<div class="line-editor"><div class="line-heading"><label for="line-${i}">第 ${i+1} 句</label><div><button class="icon-button" data-up="${i}" ${i===0?'disabled':''} aria-label="第 ${i+1} 句上移">↑</button><button class="icon-button" data-down="${i}" ${i===c.lines.length-1?'disabled':''} aria-label="第 ${i+1} 句下移">↓</button><button class="icon-button" data-remove-line="${i}" ${c.lines.length===1?'disabled':''} aria-label="删除第 ${i+1} 句">×</button></div></div><textarea id="line-${i}" data-line="${i}" rows="3" maxlength="1000">${esc(line.text)}</textarea><div class="line-footer"><label>适用阶段 <select data-stages="${i}" aria-label="第 ${i+1} 句适用故事阶段"><option value="" ${!line.stages?.length?'selected':''}>所有阶段</option>${['unresponded','event01','event02','event03'].map((st,k)=>`<option value="${st}" ${line.stages?.length===1&&line.stages[0]===st?'selected':''}>${['尚未回应','故事事件 01 完成','故事事件 02 完成','故事事件 03 完成'][k]}</option>`).join('')}${line.stages?.length>1?`<option value="__keep" selected>保留当前多阶段限制</option>`:''}</select></label><small id="count-${i}">${line.text.length} 字</small></div></div>`).join('')}</div><button class="add-line" id="add-line">＋ 添加下一句</button><div class="unit-tools"><button class="text-button" id="unit-up" ${chapter===0?'disabled':''}>单元前移</button><button class="text-button" id="unit-down" ${chapter===p.length-1?'disabled':''}>单元后移</button><button class="text-button danger" id="remove-unit" ${p.length===1||selected==='stable.touchDiscovery'?'disabled':''}>删除此单元</button></div><p class="editor-footnote">一条单元表达一个完整事项。单元内逐句推进，讲完后才轮到下一个单元。</p></section><aside class="preview-column"><div class="preview-heading"><h3>气泡预览</h3><span class="pill">审稿模式</span></div><div class="phone"><div class="phone-top">PIBO<span>${label(state)}</span></div><div class="phone-content"><span class="preview-speaker">Pibo</span><div class="bubble" id="bubble"></div><div id="preview-progress"></div></div><button id="next-line" class="preview-pat">下一句 →</button></div><button class="text-button" id="restart-preview">从第一句预览</button><details class="sample-values"><summary>预览用示例值</summary><label>今日步数<input id="sample-steps" value="${esc(sample.steps)}"></label><label>睡眠时长<input id="sample-sleep" value="${esc(sample.sleepDuration)}"></label><label>故事阶段<select id="sample-stage">${['unresponded','event01','event02','event03'].map(st=>`<option ${sample.stage===st?'selected':''}>${st}</option>`).join('')}</select></label></details><p class="preview-note">只预览所选单元，不推断健康状态或模拟真实调度。App 中需双击身体，文本冷却为 ${data.runtime.cooldown} 秒。</p><button class="text-button" id="device-help">在鸿蒙上验收这个情境 ↗</button></aside></div>`;
}
function renderPreview() {
  if (view!=='catalog'||!$('#bubble')) return;
  const lines = current().lines.filter(l=>!l.stages?.length||l.stages.includes(sample.stage));
  previewLine = Math.max(0,Math.min(previewLine,lines.length-1));
  const line = lines[previewLine];
  $('#bubble').textContent = line ? line.text.replace(/\{(steps|sleepDuration)\}/g,(_,k)=>sample[k]) : '当前故事阶段没有可预览的台词';
  $('#preview-progress').textContent = lines.length ? `${previewLine+1} / ${lines.length} · ${previewLine<lines.length-1?'还有下句':'本单元结束'}` : '请切换阶段';
  $('#next-line').disabled = previewLine>=lines.length-1;
}
function outlineView() {
  return `<section class="page-heading"><div><h1>文案大纲</h1><p>从同一个角色出发，让六种状态改变注意力，而不是改变人格。</p></div><span class="pill">可编辑写作纲要</span></section><div class="outline-grid"><section class="outline-editor">${[['voice','恒定说话风格'],['structure','单句与微章节结构'],['boundaries','表达边界']].map(([key,title])=>`<label class="outline-field"><h2>${title}</h2><textarea data-outline="${key}" rows="4">${esc(outline[key])}</textarea></label>`).join('')}<h2>六种状态的写作方向</h2>${data.states.map(s=>`<label class="outline-field"><h3><span class="dot ${s.id}"></span>${s.title} <code>${s.id}</code></h3><textarea data-state-note="${s.id}" rows="2">${esc(outline.stateNotes[s.id])}</textarea></label>`).join('')}</section><aside class="outline-reference"><h2>现行机制</h2><ol class="flow"><li>真实健康事实决定主状态</li><li>身体双击产生文本机会</li><li>继续未完成微章节</li><li>否则选择事件、关系发现或行为情境</li><li>情境内顺序选单元，逐句呈现</li></ol><p>文本冷却内仍有动作和触觉，不推进台词。状态变化或离开首页中止微章节；同页 Sheet 不重置进度。</p><h3>决策原文</h3><button class="document-link" data-doc="mechanics">033 · 情境与调度 ↗</button><button class="document-link" data-doc="voice">034 · 角色声音 ↗</button><button class="document-link" data-doc="cooldown">044 · 动作与冷却 ↗</button><p class="muted">大纲随草稿保存在本机，供后续写作参考。修改大纲不会改动 Core 规则或自动改写台词。</p><h3>本版管理范围</h3><p>完整管理主页拍一拍：6 个状态、27 个情境。环境低语、界面文案、散步涂鸦和后端生成的食物观察仍由各自资源管理，不会混入拍一拍目录。</p></aside></div>`;
}
function diffRows() {
  return data.scenarios.map(s=>({s,before:data.live.filter(r=>keyOf(r)===s.id),after:records.filter(r=>keyOf(r)===s.id)})).filter(d=>JSON.stringify(d.before)!==JSON.stringify(d.after));
}
function publishView() {
  const changes=diffRows();
  return `<section class="page-heading"><div><h1>把文案带回 Pibo</h1><p>先检查变化，再写入鸿蒙工程。已安装的 App 需要重新构建安装才会更新。</p></div><span class="pill">${data.runtime.synced&&!dirty?'与鸿蒙资源一致':'待同步'}</span></section><div class="publish-grid"><section><div class="publish-card"><h2>鸿蒙正式资源</h2><p class="file-path">${esc(data.runtime.target)}</p><div class="sync-stats"><div><b>${records.length}</b><span>互动单元</span></div><div><b>${records.reduce((n,r)=>n+r.lines.length,0)}</b><span>句台词</span></div><div><b>${changes.length}</b><span>变化情境</span></div></div>${data.runtime.conflict?'<p class="alert">正式资源被外部修改。先导出草稿留底，再载入鸿蒙版本合并。</p>':''}${data.runtime.contractChanged?'<p class="alert">Core 或情境合同已更新，需要重启控制台。</p>':''}${dirty?'<p class="alert">有未保存修改，请先保存草稿。</p>':''}<div class="publish-actions"><button id="sync" ${dirty||data.runtime.conflict||data.runtime.contractChanged||!changes.length?'disabled':''}>确认差异并同步鸿蒙</button><a class="button secondary" href="/api/export" download="pibo-home-pat.zh-Hans.jsonl">导出已保存 JSONL</a><button class="text-button" id="import-live">载入鸿蒙版本</button></div><p class="muted">同步前自动备份正式资源；不自动提交、构建或安装。iOS ${data.runtime.iosAligned?'目前与鸿蒙一致':'与鸿蒙已有差异，尚未同步'}。</p></div><h2 class="section-title">与鸿蒙版本的差异</h2>${changes.length?changes.map(d=>`<article class="diff-card"><h3>${label(d.s.state)} / ${esc(d.s.title)}</h3><div class="diff-grid"><div><span class="small-label">当前鸿蒙</span>${d.before.map((r,i)=>`<pre>${i+1}. ${esc(r.lines.map(l=>l.text+(l.stages?.length?` [${l.stages.join(', ')}]`:'')).join('\n   '))}</pre>`).join('')}</div><div><span class="small-label">准备同步</span>${d.after.map((r,i)=>`<pre>${i+1}. ${esc(r.lines.map(l=>l.text+(l.stages?.length?` [${l.stages.join(', ')}]`:'')).join('\n   '))}</pre>`).join('')}</div></div></article>`).join(''):'<div class="empty-card">没有台词差异。可以回到拍一拍文案开始编辑。</div>'}<h2 class="section-title">本机版本记录</h2>${data.history.length?data.history.map(r=>`<div class="version-row"><div><strong>${esc(r.kind)}</strong><small>${new Date(r.at).toLocaleString('zh-CN')} · ${r.units} 单元 · ${r.hash.slice(0,8)}</small></div><button class="secondary" data-restore="${esc(r.id)}">恢复为草稿</button></div>`).join(''):'<p class="muted">首次保存或同步后，这里会出现备份。</p>'}</section><aside class="publish-guide"><h2>鸿蒙验收路径</h2><ol class="flow"><li>同步到工程资源</li><li>使用 DevEco 构建并安装手机 Debug 包</li><li>设置 → 拍一拍场景验收（27 个上下文）</li><li>选择对应主状态和情境</li><li>双击 Pibo 身体，等冷却结束再继续</li></ol><p>验收会话与正式健康数据、事件记录和台词游标隔离。日常模式仍需满足真实状态和事件条件。</p><h3>校验结果</h3><div class="validation">${data.validation.errors.length?data.validation.errors.map(e=>`<p class="alert">${esc(e)}</p>`).join(''):'<p>✓ 状态、情境与动作匹配<br>✓ 场景覆盖与动态值合法<br>✓ 故事阶段均有可用内容</p>'}${data.validation.warnings.map(w=>`<p class="muted">${esc(w)}</p>`).join('')}</div></aside></div>`;
}
function editStructure(fn) { fn(); dirty = true; previewLine = 0; render(); }
function bind() {
  document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>{view=b.dataset.view;render();});
  document.querySelectorAll('[data-state]').forEach(b=>b.onclick=()=>{state=b.dataset.state;view='catalog';selected=data.scenarios.find(s=>s.state===state).id;chapter=0;previewLine=0;query='';render();});
  document.querySelectorAll('[data-scene]').forEach(b=>b.onclick=()=>{selected=b.dataset.scene;chapter=0;previewLine=0;render();});
  document.querySelectorAll('[data-chapter]').forEach(b=>b.onclick=()=>{chapter=+b.dataset.chapter;previewLine=0;render();});
  $('#go-publish').onclick=()=>{view='publish';render();};
  $('#save').onclick=()=>run(async()=>{accept(await api('/api/save',{records,outline}));notice('草稿已保存到本机；尚未同步鸿蒙。');});
  if($('#mobile-state')) $('#mobile-state').onchange=e=>{state=e.target.value;selected=data.scenarios.find(s=>s.state===state).id;chapter=0;previewLine=0;query='';render();};
  if($('#search')) $('#search').oninput=e=>{query=e.target.value;const pos=e.target.selectionStart;render();$('#search').focus();try{$('#search').setSelectionRange(pos,pos);}catch{}};
  document.querySelectorAll('[data-line]').forEach(t=>t.oninput=()=>{const i=+t.dataset.line;records[current().index].lines[i].text=t.value;$('#count-'+i).textContent=t.value.length+' 字';markDirty();});
  document.querySelectorAll('[data-stages]').forEach(t=>t.onchange=()=>{if(t.value==='__keep')return;const line=records[current().index].lines[+t.dataset.stages];if(t.value)line.stages=[t.value];else delete line.stages;markDirty();});
  document.querySelectorAll('[data-up],[data-down]').forEach(b=>b.onclick=()=>editStructure(()=>{const up=b.dataset.up!==undefined,i=+(up?b.dataset.up:b.dataset.down),j=i+(up?-1:1),ls=records[current().index].lines;[ls[i],ls[j]]=[ls[j],ls[i]];}));
  document.querySelectorAll('[data-remove-line]').forEach(b=>b.onclick=()=>{if(confirm('删除这一句？保存前可通过刷新放弃修改。'))editStructure(()=>records[current().index].lines.splice(+b.dataset.removeLine,1));});
  if($('#add-line')) $('#add-line').onclick=()=>editStructure(()=>records[current().index].lines.push({text:''}));
  if($('#add-chapter')) $('#add-chapter').onclick=()=>editStructure(()=>{const p=pool(),last=p.at(-1);records.splice(last.index+1,0,{state:last.state,context:last.context,action:last.action,speaker:last.speaker,lines:[{text:''}]});chapter=p.length;});
  if($('#remove-unit')) $('#remove-unit').onclick=()=>{if(confirm('删除整个互动单元？'))editStructure(()=>{records.splice(current().index,1);chapter=Math.max(0,chapter-1);});};
  for(const [id,delta] of [['unit-up',-1],['unit-down',1]]) if($('#'+id)) $('#'+id).onclick=()=>editStructure(()=>{const p=pool(),a=p[chapter].index,b=p[chapter+delta].index;[records[a],records[b]]=[records[b],records[a]];chapter+=delta;});
  if($('#next-line')) $('#next-line').onclick=()=>{previewLine++;renderPreview();};
  if($('#restart-preview')) $('#restart-preview').onclick=()=>{previewLine=0;renderPreview();};
  for(const [id,key] of [['sample-steps','steps'],['sample-sleep','sleepDuration'],['sample-stage','stage']]) if($('#'+id)) $('#'+id).oninput=e=>{sample[key]=e.target.value;renderPreview();};
  if($('#device-help')) $('#device-help').onclick=()=>modal('验收：'+scenario().title,`<p>先保存并同步鸿蒙，重新构建安装 Debug 手机包。</p><p>设置 → 拍一拍场景验收（27 个上下文）→ <b>${label(state)} / ${esc(scenario().title)}</b></p><p>双击 Pibo 身体。每隔 ${data.runtime.cooldown} 秒推进一句；可重开情境检查整个池。</p><p class="muted">${esc(scenario().debugDetail)}。这些是隔离验收输入，不会写入正式健康记录。</p>`);
  document.querySelectorAll('[data-outline]').forEach(t=>t.oninput=()=>{outline[t.dataset.outline]=t.value;markDirty();});
  document.querySelectorAll('[data-state-note]').forEach(t=>t.oninput=()=>{outline.stateNotes[t.dataset.stateNote]=t.value;markDirty();});
  document.querySelectorAll('[data-doc]').forEach(b=>b.onclick=()=>run(async()=>{const d=await api('/api/document?id='+b.dataset.doc);modal(d.path.split('/').at(-1),`<pre class="document-text">${esc(d.text)}</pre>`);}));
  if($('#sync')) $('#sync').onclick=()=>run(async()=>{accept(await api('/api/sync',{}));notice('已写入鸿蒙资源并备份旧版。重新构建安装后生效。');});
  if($('#import-live')) $('#import-live').onclick=()=>{if(confirm('用鸿蒙正式资源替换当前草稿？已保存草稿会备份，未保存修改将丢弃。'))run(async()=>{accept(await api('/api/import-live',{}));notice('已载入鸿蒙正式资源。');});};
  document.querySelectorAll('[data-restore]').forEach(b=>b.onclick=()=>{if(confirm('恢复此版本为草稿？未保存修改将丢弃；不会直接修改鸿蒙资源。'))run(async()=>{accept(await api('/api/restore',{id:b.dataset.restore}));notice('历史版本已恢复为草稿。检查差异后再同步。');});});
}
let busy=false;
async function run(fn) { if(busy)return;busy=true;document.body.classList.add('busy');try{await fn();}catch(e){notice(e.message,true);}finally{busy=false;document.body.classList.remove('busy');} }
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
try { accept(await api('/api/state')); } catch(e) { $('#app').innerHTML=`<div class="startup-error"><h1>暂时无法读取文案</h1><p>${esc(e.message)}</p><p>确认鸿蒙工程位置和控制台服务后刷新页面。</p></div>`; }

// Optional imperative surface; edits stage the same unsaved draft as the UI.
if (data && document.modelContext?.registerTool) {
  const lifecycle = new AbortController();
  const tools = [{
    name: 'inspect_pat_catalog',
    description: '读取当前拍一拍草稿、触发情境与写作大纲，不保存或同步。',
    inputSchema: {type:'object',properties:{},additionalProperties:false},
    annotations: {readOnlyHint:true,untrustedContentHint:true},
    execute: () => ({records:structuredClone(records),scenarios:data.scenarios,outline:structuredClone(outline),unsaved:dirty}),
  }, {
    name: 'stage_pat_line_edits',
    description: '批量暂存现有台词修改并更新编辑器。不会保存到磁盘或同步鸿蒙；需随后在 UI 审核保存。索引从 0 开始。',
    inputSchema: {type:'object',properties:{edits:{type:'array',minItems:1,items:{type:'object',properties:{recordIndex:{type:'integer',minimum:0},lineIndex:{type:'integer',minimum:0},text:{type:'string',minLength:1,maxLength:1000}},required:['recordIndex','lineIndex','text'],additionalProperties:false}}},required:['edits'],additionalProperties:false},
    annotations: {readOnlyHint:false,untrustedContentHint:true},
    execute: input => {
      if(busy) throw new Error('正在保存，请稍后再修改');
      if(!Array.isArray(input?.edits)||!input.edits.length)throw new Error('需要 edits 列表');
      for(const e of input.edits)if(!Number.isInteger(e.recordIndex)||!Number.isInteger(e.lineIndex)||!records[e.recordIndex]?.lines[e.lineIndex]||typeof e.text!=='string'||!e.text.trim()||e.text.length>1000)throw new Error('台词索引或文本不合法');
      for(const e of input.edits)records[e.recordIndex].lines[e.lineIndex].text=e.text;
      const r=records[input.edits[0].recordIndex];selected=keyOf(r);state=r.state;view='catalog';chapter=pool().findIndex(p=>p.index===input.edits[0].recordIndex);previewLine=0;dirty=true;render();
      return {staged:input.edits.length,saved:false,synced:false};
    },
  }];
  for(const tool of tools)try{Promise.resolve(document.modelContext.registerTool(tool,{signal:lifecycle.signal})).catch(()=>{});}catch{}
  window.addEventListener('pagehide',()=>lifecycle.abort(),{once:true});
}
