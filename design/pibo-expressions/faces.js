// Pibo 表情配置表 — 每个情绪 = 一组脸部参数
// 映射到项目的 6-态活动机 (PiboActivityState) + 拍一拍 moods (正常/生气/呓语)
// 见 CLAUDE.md「Pibo activity zone — 6-state machine」与「拍一拍 / pat」。
//
// 字段: id, name(EN), zh(中文), maps(项目状态), brows, eyes, muzzle, cheeks, mouth, extras[], bg
// 规则: 嘴 (mouth) 默认 'none'——只有需要时才画; 海豹鼻 (muzzle) 默认常驻。

export const FACES = [
  // ── 6-态活动机 ───────────────────────────────────────────────
  { id: 'idle', name: 'Idle', zh: '发呆', maps: 'IDLE 发呆 (默认)',
    brows: 'flat', eyes: 'dot', muzzle: true, cheeks: 'default', mouth: 'none',
    bg: '#d9ece2' },

  { id: 'active', name: 'Active', zh: '活跃', maps: 'ACTIVE 活跃 (步数≥10k/运动中)',
    brows: 'raised', eyes: 'happy', muzzle: true, cheeks: 'blush', mouth: 'smile',
    extras: ['sparkle'], bg: '#cfe9d6' },

  { id: 'irritated', name: 'Irritated', zh: '烦躁', maps: 'IRRITATED 烦躁 (久坐/睡不足)',
    brows: 'angry', eyes: 'dot', muzzle: true, cheeks: 'default', mouth: 'wavy',
    extras: ['anger'], bg: '#f2dcd9' },

  { id: 'sleeping', name: 'Sleeping', zh: '深眠', maps: 'SLEEPING 深眠 (22:00–06:00 / 拔毛后)',
    brows: 'none', eyes: 'sleep', muzzle: true, cheeks: 'default', mouth: 'none',
    extras: ['zzz'], bg: '#2b3a4a' },

  { id: 'waking', name: 'Waking', zh: '初醒', maps: 'WAKING 初醒 (06:00–10:00 首开)',
    brows: 'sad', eyes: 'half', muzzle: true, cheeks: 'default', mouth: 'o',
    extras: ['zzz'], bg: '#fbe6d6' },

  { id: 'disturbed', name: 'Disturbed', zh: '被打扰', maps: '🅿️ 被打扰 (10min 内≥3 拍)',
    brows: 'angry', eyes: 'squeeze', muzzle: true, cheeks: 'default', mouth: 'frown',
    extras: ['sweat'], bg: '#f6e7cf' },

  // ── 拍一拍 moods (PiboSpeechLine.mood) ───────────────────────
  { id: 'normal', name: 'Content', zh: '正常·说话', maps: 'pat mood 正常 (白色圆框)',
    brows: 'flat', eyes: 'dot', muzzle: true, cheeks: 'default', mouth: 'smile',
    bg: '#e0efe6' },

  { id: 'angry', name: 'Angry', zh: '生气·扭头', maps: 'pat mood 生气 (黑框 + 扭头)',
    brows: 'angry', eyes: 'x', muzzle: true, cheeks: 'none', mouth: 'cat',
    extras: ['anger'], bg: '#f2d3cf' },

  { id: 'murmur', name: 'Murmur', zh: '呓语', maps: 'pat mood 呓语 (深眠/发呆自语)',
    brows: 'none', eyes: 'sleep', muzzle: true, cheeks: 'default', mouth: 'wavy',
    extras: ['zzz'], bg: '#e5e0f2' },

  // ── 通用情绪扩展 (供未来 per-state 美术 / 弹幕 / 故事复用) ──────
  { id: 'joyful', name: 'Joyful', zh: '大笑', maps: '能量收集/成就时刻',
    brows: 'raised', eyes: 'happy', muzzle: true, cheeks: 'blush', mouth: 'open',
    extras: ['sparkle'], bg: '#fdf1d6' },

  { id: 'surprised', name: 'Surprised', zh: '惊讶', maps: '识别到活动/拍照误读',
    brows: 'raised', eyes: 'wide', muzzle: true, cheeks: 'default', mouth: 'o',
    bg: '#d9ecf5' },

  { id: 'sad', name: 'Sad', zh: '难过', maps: '连续能量不足 (decline arc)',
    brows: 'sad', eyes: 'dot', muzzle: true, cheeks: 'default', mouth: 'frown',
    extras: ['tear'], bg: '#dde6ec' },

  { id: 'shy', name: 'Shy', zh: '害羞', maps: '亲密度/被夸',
    brows: 'flat', eyes: 'happy', muzzle: true, cheeks: 'blush', mouth: 'cat',
    bg: '#fadfe4' },

  { id: 'love', name: 'Love', zh: '喜欢', maps: '声音能量/高亲密度',
    brows: 'raised', eyes: 'heart', muzzle: true, cheeks: 'blush', mouth: 'open',
    extras: ['hearts'], bg: '#fbdfe6' },

  { id: 'sick', name: 'Sick', zh: '生病/眩晕', maps: '生病态 (long-term neglect)',
    brows: 'sad', eyes: 'spiral', muzzle: true, cheeks: 'default', mouth: 'wavy',
    extras: ['sweat'], bg: '#dfe6d2' },

  { id: 'glitch', name: 'Glitch', zh: '发疯/故障', maps: '发疯态 glitch 故障艺术',
    brows: 'angry', eyes: 'x', muzzle: true, cheeks: 'none', mouth: 'wavy',
    extras: ['glitch'], bg: '#c9d3d0' },
];
