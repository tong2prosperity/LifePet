export function startOfDayMs(value: number = Date.now()): number {
  const d = new Date(value);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function daysSinceBirth(birthMs: number, nowMs: number = Date.now()): number {
  const elapsed = startOfDayMs(nowMs) - startOfDayMs(birthMs);
  const days = Math.floor(elapsed / 86400000) + 1;
  return Math.max(1, days);
}

export function timeLabel(valueMs: number): string {
  const d = new Date(valueMs);
  const hh = d.getHours().toString().padStart(2, '0');
  const mm = d.getMinutes().toString().padStart(2, '0');
  return `${hh}:${mm}`;
}

export function relativeTimeLabel(valueMs: number, nowMs: number = Date.now()): string {
  const target = startOfDayMs(valueMs);
  const today = startOfDayMs(nowMs);
  const time = timeLabel(valueMs);
  if (target === today) {
    return `今 ${time}`;
  }
  if (target === today - 86400000) {
    return `昨 ${time}`;
  }
  const d = new Date(valueMs);
  return `${d.getMonth() + 1}/${d.getDate()} ${time}`;
}

export function dateLabel(nowMs: number = Date.now()): string {
  const d = new Date(nowMs);
  const weekdays: string[] = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  return `${weekdays[d.getDay()]} · ${d.getMonth() + 1}/${d.getDate()}`;
}

export function greeting(nowMs: number = Date.now()): string {
  const h = new Date(nowMs).getHours();
  if (h < 5) {
    return '深夜';
  }
  if (h < 11) {
    return '早上好';
  }
  if (h < 13) {
    return '午安';
  }
  if (h < 18) {
    return '下午好';
  }
  if (h < 22) {
    return '晚上好';
  }
  return '夜深了';
}

export function makeId(prefix: string): string {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
}
