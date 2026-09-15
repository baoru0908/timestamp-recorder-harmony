/**
 * 数据模型与色板
 *
 * 与 Android 版 EventRepository.kt 严格对齐：备份 JSON 字段名、色值的有符号 int
 * 存储方式都保持一致，保证两边导出的备份可以互相导入。
 */

/** 事件：一个可独立记录时间戳的分类 */
export class TimestampEvent {
  id: number;
  name: string;
  /** ARGB 颜色值。注意：与 Android 版一致，存的是**有符号 32 位 int**（可能是负数） */
  color: number;
  createdAt: number;

  constructor(id: number, name: string, color: number, createdAt: number) {
    this.id = id;
    this.name = name;
    this.color = color;
    this.createdAt = createdAt;
  }
}

/** 存储 / 备份中的事件 JSON 结构（字段名不能改，跨平台兼容红线） */
export interface EventJson {
  id: number;
  name: string;
  color: number;
  createdAt: number;
}

/** 时间线条目：一条记录 + 所属事件信息（派生结构，不落盘） */
export class TimelineRecord {
  eventId: number;
  eventName: string;
  eventColor: number;
  millis: number;
  // 视觉上一条（时间更新、位于本行上方）记录的事件色，用于时间线竖线两色渐变；-1 = 无（列表首条）
  prevColor: number = -1;

  constructor(eventId: number, eventName: string, eventColor: number, millis: number) {
    this.eventId = eventId;
    this.eventName = eventName;
    this.eventColor = eventColor;
    this.millis = millis;
  }
}

/** 分类染色色板（12 色，与 Android 版逐一对应；`| 0` 转成有符号 int 以保持存储一致） */
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
  0xFF546E7A | 0  // 蓝灰
];

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
