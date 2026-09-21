/**
 * 数据模型与色板
 *
 * 与 Android 版 EventRepository.kt 严格对齐：备份 JSON 字段名、色值的有符号 int
 * 存储方式都保持一致，保证两边导出的备份可以互相导入。
 */

/** 事件类型：点时刻（记录一个个瞬间） */
export const TYPE_POINT: number = 0;
/** 事件类型：时间段（记录 start ~ end 的区间，可开始/结束） */
export const TYPE_INTERVAL: number = 1;

/** 事件：一个可独立记录时间戳的分类 */
export class TimestampEvent {
  id: number;
  name: string;
  /** ARGB 颜色值。注意：与 Android 版一致，存的是**有符号 32 位 int**（可能是负数） */
  color: number;
  createdAt: number;
  /** 记录类型：TYPE_POINT / TYPE_INTERVAL。缺省为点时刻（兼容 format 1 的老备份） */
  type: number = TYPE_POINT;

  constructor(id: number, name: string, color: number, createdAt: number, type: number = TYPE_POINT) {
    this.id = id;
    this.name = name;
    this.color = color;
    this.createdAt = createdAt;
    this.type = type === TYPE_INTERVAL ? TYPE_INTERVAL : TYPE_POINT;
  }

  /** 是否为时间段（区间）类型 */
  isInterval(): boolean {
    return this.type === TYPE_INTERVAL;
  }
}

/** 存储 / 备份中的事件 JSON 结构（字段名不能改，跨平台兼容红线） */
export interface EventJson {
  id: number;
  name: string;
  color: number;
  createdAt: number;
  /** 可选：老备份（format 1）没有此字段，读时按点时刻处理 */
  type?: number;
}

/**
 * 时间段记录：start ~ end。
 * `end` 未定义表示**进行中**（对齐 Android：`end` 缺省即 ongoing）。
 * JSON.stringify 会自然丢弃 undefined，落盘结构与 Android 一致。
 */
export class TimeInterval {
  start: number;
  end?: number;

  constructor(start: number, end?: number) {
    this.start = start;
    if (end !== undefined) {
      this.end = end;
    }
  }

  /** 是否进行中（未结束） */
  isOngoing(): boolean {
    return this.end === undefined;
  }

  /** 时长（毫秒）。进行中则以当前时间作为结束 */
  duration(): number {
    const e: number = this.end === undefined ? Date.now() : this.end;
    return e - this.start;
  }
}

/** 存储 / 备份中的区间 JSON 结构（字段名不能改，跨平台兼容红线） */
export interface IntervalJson {
  start: number;
  end?: number;
}

/** 时间线条目：一条记录 + 所属事件信息（派生结构，不落盘） */
export class TimelineRecord {
  eventId: number;
  eventName: string;
  eventColor: number;
  millis: number;
  // 视觉上一条（时间更新、位于本行上方）记录的事件色，用于时间线竖线两色渐变；-1 = 无（列表首条）
  prevColor: number = -1;
  /** 时间段条目：非空表示这是一条区间记录（millis = start），用于时间线显示起止与时长 */
  interval: TimeInterval | null = null;

  constructor(eventId: number, eventName: string, eventColor: number, millis: number,
    interval: TimeInterval | null = null) {
    this.eventId = eventId;
    this.eventName = eventName;
    this.eventColor = eventColor;
    this.millis = millis;
    this.interval = interval;
  }
}

/**
 * 分类染色色板（23 色，与 Android 版 EventColors.palette 严格对齐；
 * `| 0` 转成有符号 int 以保持存储一致，顺序也一致：第 0 格不是「自定义」，
 * 末尾也不额外加「自定义」，「自定义」由 ColorPickerPanel 组件层单独处理）。
 */
export const EVENT_COLORS: number[] = [
  0xFFE53935 | 0, // 红
  0xFFFB8C00 | 0, // 橙
  0xFFF9A825 | 0, // 琥珀
  0xFF43A047 | 0, // 绿
  0xFF00897B | 0, // 青绿
  0xFF00ACC1 | 0, // 青
  0xFF1E88E5 | 0, // 蓝
  0xFF3949AB | 0, // 靛
  0xFF8E24AA | 0, // 紫
  0xFFD81B60 | 0, // 粉
  0xFF6D4C41 | 0, // 棕
  0xFF546E7A | 0, // 蓝灰
  0xFFC62828 | 0, // 深红
  0xFFEF6C00 | 0, // 深橙
  0xFFFDD835 | 0, // 明黄
  0xFF689F38 | 0, // 草绿
  0xFF26A69A | 0, // 薄荷
  0xFF00BCD4 | 0, // 亮青
  0xFF42A5F5 | 0, // 浅蓝
  0xFF5C6BC0 | 0, // 浅靛
  0xFFAB47BC | 0, // 浅紫
  0xFFEC407A | 0, // 玫粉
  0xFF8D6E63 | 0  // 浅棕
];

/**
 * 判断字符串是否为合法 hex 颜色：
 * 接受 `#RRGGBB` / `RRGGBB` / `#RGB` / `RGB`（大小写均可），去掉首尾空格后判断。
 */
export function isValidHex(s: string): boolean {
  const t: string = s.trim();
  const m: RegExpMatchArray | null = t.match(/^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/);
  return m !== null;
}

/**
 * hex 颜色字符串 → 有符号 32 位 int（与 [colorToHex] 严格互逆：
 * `colorToHex(hexToColor('#3B82F6')) === '#3B82F6'`）。
 * - `#` 可省略；支持 3 位缩写（`#F00` → 红）。
 * - 解析失败时返回安全默认色（蓝 0xFF1E88E5）。
 *
 * 转换逻辑：`parseInt(h,16)` 得到 0..0xFFFFFF 的 RGB；`0xFF000000 | rgb` 补全 alpha 通道；
 * 末尾 `| 0` 把超过 2^31 的无符号值收敛为有符号 int（负数），
 * 与 `colorToHex` 里的 `color >>> 0` 互为逆操作。
 */
export function hexToColor(hex: string): number {
  const t: string = hex.trim();
  const m: RegExpMatchArray | null = t.match(/^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/);
  if (m === null) {
    return 0xFF1E88E5 | 0; // 安全默认蓝
  }
  let h: string = m[1];
  if (h.length === 3) {
    h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  }
  const rgb: number = parseInt(h, 16);
  return (0xFF000000 | rgb) | 0;
}

/** 随机取一个色板颜色（新建事件默认色） */
export function randomEventColor(): number {
  const i: number = Math.floor(Math.random() * EVENT_COLORS.length);
  return EVENT_COLORS[i];
}

/**
 * 有符号 int 色值 → `#RRGGBB` 字符串。
 * Android 侧存的是 `0xFFE53935.toInt()`（负数），必须先做无符号转换再取低 24 位。
 */
export function colorToHex(color: number): string {
  const hex: string = ((color >>> 0) & 0xFFFFFF).toString(16);
  // ⚠️ 必须 toUpperCase：linearGradient 的运行时颜色解析不认小写 hex（实测渲染成纯色），fill 无此问题
  return '#' + hex.padStart(6, '0').toUpperCase();
}

/** 毫秒时长 → 可读文本（如 `2 小时 5 分钟`、`45 秒`）。用于区间时长展示 */
export function formatDuration(ms: number): string {
  if (ms < 0) {
    ms = 0;
  }
  const totalSec: number = Math.floor(ms / 1000);
  const d: number = Math.floor(totalSec / 86400);
  const h: number = Math.floor((totalSec % 86400) / 3600);
  const m: number = Math.floor((totalSec % 3600) / 60);
  const s: number = totalSec % 60;
  if (d > 0) {
    return `${d} 天 ${h} 小时`;
  }
  if (h > 0) {
    return `${h} 小时 ${m} 分钟`;
  }
  if (m > 0) {
    return `${m} 分钟 ${s} 秒`;
  }
  return `${s} 秒`;
}
