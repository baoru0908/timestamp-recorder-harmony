/**
 * 时间格式化（对齐 Android 版 TimeFormat，见 docs/port-spec.md §5）
 *
 * 注：P0 阶段文案先用常量，后续统一迁到 resources 支持多语言。
 */

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

function dateOf(millis: number): Date {
  return new Date(millis);
}

export class TimeFormat {
  /** 2026-09-15 09:41:53 */
  static full(millis: number): string {
    const d: Date = dateOf(millis);
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} `
      + `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
  }

  /** 09:41:53 */
  static hm(millis: number): string {
    const d: Date = dateOf(millis);
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
  }

  /** 2026-09-15 09:41 */
  static short(millis: number): string {
    const d: Date = dateOf(millis);
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} `
      + `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  }

  /** 复制到剪贴板的格式：完整时间 + Unix 秒 */
  static forClipboard(millis: number): string {
    return `${TimeFormat.full(millis)}  (Unix 秒: ${Math.floor(millis / 1000)})`;
  }

  /** 相对时间：刚刚 / N 分钟前 / N 小时前 / N 小时, M 分钟前 / N 天前 */
  static relative(millis: number, now: number = Date.now()): string {
    const diff: number = now - millis;
    if (diff < 60000) {
      return '刚刚';
    }
    const min: number = Math.floor(diff / 60000);
    if (min < 60) {
      return `${min} 分钟前`;
    }
    if (min < 1440) {
      const h: number = Math.floor(min / 60);
      const m: number = min % 60;
      return m === 0 ? `${h} 小时前` : `${h} 小时, ${m} 分钟前`;
    }
    return `${Math.floor(min / 1440)} 天前`;
  }
}
