import { createHash } from 'node:crypto';

export const states = [
  ['stable', '安稳', '对触碰作出直接回应，偶尔显露自己的注意力。'],
  ['energetic', '活跃', '把真实运动和好睡眠，转成 Pibo 自己的小念头。'],
  ['tired', '疲倦', '承认困意，采取休息行动，不向用户索取补偿。'],
  ['waking', '初醒', '先打招呼，再表达刚醒来的身体感受。'],
  ['sleeping', '睡眠', '保持睡眠，用短回应表达当下，不被拍醒。'],
  ['dataUnknown', '数据未知', '承认不知道，具体权限与恢复操作交给系统。'],
].map(([id, title, outline]) => ({ id, title, outline }));

const descriptions = {
  'stable.touchDiscovery': ['关系发现', '安稳状态，尚未完成最初三次接触认识，且没有优先健康事件。', '三次依序完成后不再循环，转入日常回应。'],
  'stable.idle': ['日常', '安稳状态，没有未回应健康事件；初次接触已完成，当前不在思考。', '按情境内单元顺序循环。'],
  'stable.thinking': ['行为', '安稳状态，连续空闲进入 thinking；没有更高优先级事件。', '回应后回到 idle；再次空闲才重新进入。'],
  'stable.steps': ['健康事件', '安稳状态，收到尚未回应的新步数事实。', '完成后消费这次事件；数字由运行时填入。'],
  'stable.sleep': ['健康事件', '安稳状态，收到新睡眠记录，未确认 Pibo 同期也在睡。', '完成后消费这次睡眠事件。'],
  'stable.sleepTogether': ['健康事件', '安稳状态，新睡眠记录覆盖 Pibo 的睡眠时段。', '只有运行时确认共同睡眠才有资格。'],
  'energetic.ready': ['日常', '活跃状态，没有待回应的运动、里程碑或好睡眠事件。', '按情境内单元顺序循环。'],
  'energetic.activityMilestone': ['健康事件', '活跃状态，收到尚未回应的当日活动里程碑。', '确认已发生的成果，不要求下一步。'],
  'energetic.goodSleep': ['健康事件', '活跃状态，收到尚未回应的良好睡眠结果。', '说完整个微章节后消费事件。'],
  'tired.insufficientSleep': ['健康事件', '疲倦状态，本回合尚未坐下，且存在尚未回应的睡眠不足事件。', '首句开始休息，当前微章节继续；说完才消费事件。'],
  'tired.awake': ['行为', '疲倦状态，无待回应的睡眠不足事件，本回合尚未坐下。', '首句开始时即标记 resting；当前微章节继续，后续选句使用休息情境。'],
  'tired.resting': ['行为', '疲倦状态，本回合已开始安顿；未完微章节优先继续，随后使用休息情境。', '保持休息；不会通过拍一拍恢复健康。'],
  'waking.orienting': ['行为', '初醒状态，本回合尚未问候，且无睡眠不足背景。', '完成后标记本回合已问候。'],
  'waking.recovering': ['行为', '初醒状态，本回合尚未问候，且有睡眠不足背景。', '完成后进入 greeted。'],
  'waking.greeted': ['行为', '初醒状态，本清醒回合已经完成首次问候。', '同回合后续回应，不重开首次问候副作用。'],
  'sleeping.asleep': ['日常', 'Core 当前选择 sleeping 状态，用户双击身体。', '顺序回应，保持睡眠；不会被拍醒。'],
  'dataUnknown.authorization': ['数据状态', '无可信主状态，健康授权尚未建立。', 'Pibo 说明观察边界；系统提供授权入口。'],
  'dataUnknown.waitingData': ['数据状态', '已授权，但还没有足够可读数据建立可信主状态。', '不猜测身体状态；系统显示等待数据。'],
  'dataUnknown.unavailable': ['数据状态', '缺少可信主状态，设备或平台健康服务暂时不可用。', '具体恢复操作由系统提供。'],
  'dataUnknown.interruptedNoTrustedState': ['数据状态', '数据中断，且没有可信旧状态可以继续保留。', '已有可信旧状态时不会仅因中断进入此情境。'],
};

export const defaultOutline = {
  voice: '认真、好奇、直接的宠物伙伴。普通口语，按字面能听懂；先回应此时此地，再表达自己的理解和行动。幽默来自具体情境，不靠抽象隐喻或强行段子。',
  structure: '短回应与长度开放的微章节并存。一个互动单元表达一个完整事项；多句时依次展开眼前事实、自己的念头、具体疑问、行动变化或收尾。句数不设固定句数上限，只要每句都有递进。一个情境可以包含多个顺序轮换的单元。',
  boundaries: '不伪造健康事实；不因用户缺席或未授权而责备；不评价用户身材；不提出需要用户输入答案才能继续的问题。当前只审核简体中文。',
  stateNotes: Object.fromEntries(states.map(s => [s.id, s.outline])),
};
export const hash = value => createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
export const parseCatalog = source => source.split(/\r?\n/).filter(s => s.trim()).map((line, i) => {
  try { return JSON.parse(line); } catch { throw new Error(`第 ${i + 1} 行不是合法 JSON`); }
});
export const serializeCatalog = records => records.map(r => JSON.stringify(r)).join('\n') + '\n';
export const keyOf = r => `${r.state}.${r.context}`;

export function readScenarios(source, records) {
  const matches = [...source.matchAll(/scenario\('([^']+)',\s*'([^']+)',\s*'([^']+)'/g)];
  const contracts = new Map();
  for (const record of records) {
    const key = keyOf(record);
    const existing = contracts.get(key);
    if (existing && (existing.action !== record.action || existing.speaker !== record.speaker)) {
      throw new Error(`情境 ${key} 有不同动作或说话者，需要升级控制台合同`);
    }
    contracts.set(key, { action: record.action, speaker: record.speaker });
  }
  const scenarios = matches.map(([, id, title, debugDetail]) => {
    const description = descriptions[id] ?? (id.startsWith('energetic.workout.') ?
      ['健康事件', `活跃状态，收到尚未回应的${title.replace('刚', '')}完成事件。`, '依序说完整个微章节后消费事件，不重新念同一事件。'] : null);
    if (!description || !contracts.has(id)) throw new Error(`未支持的情境 ${id}，请先对齐合同`);
    return { id, title, debugDetail, state: id.split('.')[0], category: description[0], trigger: description[1], lifecycle: description[2], ...contracts.get(id) };
  });
  if (scenarios.length !== contracts.size) throw new Error('鸿蒙调试情境与正式文案不匹配');
  return scenarios;
}

export function validate(records, scenarios, outline) {
  const errors = [], warnings = [];
  if (!Array.isArray(records) || records.length === 0 || records.length > 2000) return { errors: ['互动单元数量必须在 1–2000 之间'], warnings };
  const allowed = new Map(scenarios.map(s => [s.id, s]));
  const counts = new Map();
  const stages = new Set(['unresponded', 'event01', 'event02', 'event03']);
  records.forEach((r, i) => {
    const at = `单元 ${i + 1}`;
    if (!r || typeof r !== 'object') { errors.push(`${at} 格式错误`); return; }
    const scenario = allowed.get(keyOf(r));
    if (!scenario) errors.push(`${at} 的状态或情境不受当前 Core 支持`);
    else if (r.action !== scenario.action || r.speaker !== scenario.speaker) errors.push(`${at} 不得改变已有情境的动作或说话者`);
    if (Object.keys(r).sort().join() !== 'action,context,lines,speaker,state') errors.push(`${at} 包含不支持的字段`);
    counts.set(keyOf(r), (counts.get(keyOf(r)) ?? 0) + 1);
    if (!Array.isArray(r.lines) || r.lines.length === 0 || r.lines.length > 30) { errors.push(`${at} 需要 1–30 句台词`); return; }
    r.lines.forEach((line, j) => {
      if (!line || typeof line.text !== 'string' || !line.text.trim() || line.text.length > 1000) { errors.push(`${at} 第 ${j + 1} 句为空或超过 1000 字`); return; }
      if (Object.keys(line).some(k => !['text', 'stages'].includes(k))) errors.push(`${at} 台词含未知字段`);
      if (line.stages !== undefined && (!Array.isArray(line.stages) || line.stages.some(s => !stages.has(s)))) errors.push(`${at} 包含未知故事阶段`);
      const validParams = r.context === 'steps' ? ['steps'] : ['sleep', 'sleepTogether'].includes(r.context) ? ['sleepDuration'] : [];
      const rest = line.text.replace(/\{([^{}]+)\}/g, (full, param) => {
        if (!validParams.includes(param)) errors.push(`${at} 的 {${param}} 在此情境没有运行时值`);
        return '';
      });
      if (/[{}]/.test(rest)) errors.push(`${at} 存在未配对的大括号`);
      if (line.text.length > 40) warnings.push(`${at} 第 ${j + 1} 句有 ${line.text.length} 字，请在三秒气泡中检查可读性`);
    });
  });
  for (const scenario of scenarios) {
    if (!counts.get(scenario.id)) errors.push(`不能移除 ${scenario.title} 的全部互动单元`);
    const pool = records.filter(r => r && keyOf(r) === scenario.id);
    for (const stage of stages) if (pool.length && !pool.some(r => Array.isArray(r.lines) && r.lines.some(l => l && (!l.stages || Array.isArray(l.stages) && (!l.stages.length || l.stages.includes(stage)))))) errors.push(`${scenario.title} 在 ${stage} 阶段没有可用台词`);
  }
  if (counts.get('stable.touchDiscovery') !== 3) errors.push('首次接触必须保留 3 个单元，与现有 Core 发现进度一致');
  if (outline) {
    for (const field of ['voice', 'structure', 'boundaries']) if (typeof outline[field] !== 'string' || outline[field].length > 20000) errors.push(`大纲 ${field} 格式不正确`);
    for (const state of states) if (typeof outline.stateNotes?.[state.id] !== 'string' || outline.stateNotes[state.id].length > 20000) errors.push(`${state.title} 大纲格式不正确`);
  }
  return { errors: [...new Set(errors)], warnings };
}
