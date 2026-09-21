import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  EventJson,
  IntervalJson,
  TimeInterval,
  TimelineRecord,
  TimestampEvent,
  TYPE_INTERVAL
} from '../model/TimestampEvent';

const STORE_NAME: string = 'tsr_data';
const KEY_EVENTS: string = 'events';
const KEY_SORT_MODE: string = 'sort_mode';
const EMPTY_ARRAY: string = '[]';
const SORT_MANUAL: string = 'manual';
const SORT_RECENT: string = 'recent';
const BACKUP_APP: string = 'timestamp-recorder';
/** 备份格式版本：2 = 含 intervals（与 Android 版一致）；导入时兼容 1 */
const BACKUP_FORMAT: number = 2;

function recordsKey(id: number): string {
  return `records_${id}`;
}

function intervalsKey(id: number): string {
  return `intervals_${id}`;
}

/** 备份数据（对齐 Android BackupHelper.BackupData） */
export interface BackupData {
  events: TimestampEvent[];
  records: Map<number, number[]>;
  intervals: Map<number, TimeInterval[]>;
}

/** 备份文件根结构（对齐 Android BackupHelper.exportJson） */
interface BackupRoot {
  app: string;
  format: number;
  exportedAt: number;
  events: EventJson[];
  records: Record<string, number[]>;
  /** format 2 起有此字段；format 1 的老备份没有 */
  intervals?: Record<string, IntervalJson[]>;
}

/**
 * 数据层：Preferences + JSON，零第三方依赖、纯本地。
 *
 * 存储结构与键名与 Android 版完全一致：
 * - `events`              → JSON 数组，**数组顺序 = 手动排序顺序**
 * - `records_<eventId>`   → JSON 数组（点时刻），**最新在前（index 0 是最新一条）**
 * - `intervals_<eventId>` → JSON 数组（时间段），**按 start 升序**，`end` 缺省 = 进行中
 */
export class EventRepository {
  private prefs: preferences.Preferences;

  /** 数据变更回调（页面挂 syncAllForms 回刷服务卡片；FormAbility 内部不挂） */
  onChanged: (() => void) | null = null;

  constructor(context: common.Context) {
    this.prefs = preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged();
    }
  }

  // —— Preferences 同步 API 静态检查标注可能抛异常，统一在此 try/catch，避免散落各处 ——
  private safeGet(key: string, def: preferences.ValueType): preferences.ValueType {
    try {
      return this.prefs.getSync(key, def);
    } catch (err) {
      return def;
    }
  }

  private safePut(key: string, value: preferences.ValueType): void {
    try {
      this.prefs.putSync(key, value);
      this.prefs.flush();
    } catch (err) {
      }
  }

  private safeDelete(key: string): void {
    try {
      this.prefs.deleteSync(key);
      this.prefs.flush();
    } catch (err) {
      }
  }

  // ---------- 事件 CRUD ----------

  getEvents(): TimestampEvent[] {
    const raw: string = this.safeGet(KEY_EVENTS, EMPTY_ARRAY) as string;
    let list: TimestampEvent[] = [];
    try {
      const arr: EventJson[] = JSON.parse(raw) as EventJson[];
      list = arr.map((o: EventJson) =>
        new TimestampEvent(o.id, o.name, o.color, o.createdAt, o.type === undefined ? 0 : o.type));
    } catch (err) {
      list = [];
    }
    return list;
  }

  getEvent(id: number): TimestampEvent | null {
    const found: TimestampEvent[] = this.getEvents().filter((e: TimestampEvent) => e.id === id);
    return found.length > 0 ? found[0] : null;
  }

  addEvent(name: string, color: number, type: number = 0): TimestampEvent {
    const events: TimestampEvent[] = this.getEvents();
    let id: number = Date.now();
    while (events.some((e: TimestampEvent) => e.id === id)) {
      id++;
    }
    const ev: TimestampEvent = new TimestampEvent(id, name.trim(), color, Date.now(), type);
    events.push(ev);
    this.saveEvents(events);
    return ev;
  }

  updateEvent(id: number, name: string, color: number, type: number = 0): void {
    const next: TimestampEvent[] = this.getEvents().map((e: TimestampEvent) => {
      if (e.id === id) {
        return new TimestampEvent(e.id, name.trim(), color, e.createdAt, type);
      }
      return e;
    });
    this.saveEvents(next);
  }

  /** 删除事件：连同它的全部点记录与时间段一起删 */
  deleteEvent(id: number): void {
    this.saveEvents(this.getEvents().filter((e: TimestampEvent) => e.id !== id));
    this.safeDelete(recordsKey(id));
    this.safeDelete(intervalsKey(id));
  }

  /** 手动顺序（即存储数组的顺序） */
  getEventsManualOrder(): TimestampEvent[] {
    return this.getEvents();
  }

  /** 按最近记录时间降序；无记录的事件排在最后（时间段按最后一段的 start 计） */
  getEventsByRecent(): TimestampEvent[] {
    const out: TimestampEvent[] = this.getEvents();
    out.sort((a: TimestampEvent, b: TimestampEvent) => {
      const va: number = this.lastActivityAt(a);
      const vb: number = this.lastActivityAt(b);
      return vb - va;
    });
    return out;
  }

  /** 事件最近一次活动时间（点记录取最新一条；时间段取最后一段 start）。无记录返回 -1 */
  lastActivityAt(ev: TimestampEvent): number {
    if (ev.isInterval()) {
      const list: TimeInterval[] = this.getIntervals(ev.id);
      if (list.length > 0) {
        return list[list.length - 1].start;
      }
      return -1;
    }
    const last: number | null = this.lastRecord(ev.id);
    return last === null ? -1 : last;
  }

  /** 持久化新的手动顺序（未出现在列表里的排在末尾，防止丢事件） */
  setEventsOrder(orderedIds: number[]): void {
    const all: TimestampEvent[] = this.getEvents();
    const map: Map<number, TimestampEvent> = new Map<number, TimestampEvent>();
    all.forEach((e: TimestampEvent) => map.set(e.id, e));
    const out: TimestampEvent[] = [];
    orderedIds.forEach((id: number) => {
      const e: TimestampEvent | undefined = map.get(id);
      if (e !== undefined) {
        out.push(e);
        map.delete(id);
      }
    });
    all.forEach((e: TimestampEvent) => {
      if (map.has(e.id)) {
        out.push(e);
      }
    });
    this.saveEvents(out);
  }

  /** 用备份数据整体替换（覆盖，不是合并） */
  replaceAllData(events: TimestampEvent[], records: Map<number, number[]>,
    intervals: Map<number, TimeInterval[]> | null = null): void {
    // 先按旧事件列表逐个清掉记录键，避免残留
    this.getEvents().forEach((e: TimestampEvent) => {
      this.safeDelete(recordsKey(e.id));
      this.safeDelete(intervalsKey(e.id));
    });
    this.saveEvents(events);
    records.forEach((list: number[], id: number) => {
      this.safePut(recordsKey(id), JSON.stringify(list));
    });
    if (intervals !== null) {
      intervals.forEach((list: TimeInterval[], id: number) => {
        this.safePut(intervalsKey(id), JSON.stringify(list));
      });
    }
    this.notifyChanged();
  }

  // ---------- 备份（对齐 Android BackupHelper，格式红线：app=timestamp-recorder / format=2） ----------

  /** 导出全量 JSON（结构与 Android 互通；format 2 含 intervals，导入端兼容 1） */
  exportJson(): string {
    const evArr: EventJson[] = this.getEvents().map((e: TimestampEvent) => {
      const j: EventJson = { id: e.id, name: e.name, color: e.color, createdAt: e.createdAt, type: e.type };
      return j;
    });
    const recObj: Record<string, number[]> = {};
    const intObj: Record<string, IntervalJson[]> = {};
    this.getEvents().forEach((e: TimestampEvent) => {
      recObj[`${e.id}`] = this.getRecords(e.id);
      intObj[`${e.id}`] = this.getIntervals(e.id).map((it: TimeInterval) => {
        const j: IntervalJson = { start: it.start, end: it.end };
        return j;
      });
    });
    const root: BackupRoot = {
      app: BACKUP_APP,
      format: BACKUP_FORMAT,
      exportedAt: Date.now(),
      events: evArr,
      records: recObj,
      intervals: intObj
    };
    return JSON.stringify(root, null, 2);
  }

  /** 解析备份 JSON；app 不符或结构损坏返回 null。兼容 format 1（无 intervals） */
  parseBackup(json: string): BackupData | null {
    try {
      const root: BackupRoot = JSON.parse(json) as BackupRoot;
      if (root.app !== BACKUP_APP) {
        return null;
      }
      const events: TimestampEvent[] = root.events.map((o: EventJson) =>
        new TimestampEvent(o.id, o.name, o.color, o.createdAt, o.type === undefined ? 0 : o.type));
      const records: Map<number, number[]> = new Map<number, number[]>();
      const recKeys: string[] = Object.keys(root.records);
      recKeys.forEach((k: string) => {
        records.set(Number(k), root.records[k]);
      });
      const intervals: Map<number, TimeInterval[]> = new Map<number, TimeInterval[]>();
      // ⚠️ 用 for 循环而非 forEach：ArkTS 流分析在闭包内不保留「已判非 undefined」的窄化
      if (root.intervals !== undefined) {
        const intObj: Record<string, IntervalJson[]> = root.intervals;
        const intKeys: string[] = Object.keys(intObj);
        for (let i: number = 0; i < intKeys.length; i++) {
          const k: string = intKeys[i];
          const arr: IntervalJson[] = intObj[k];
          const list: TimeInterval[] = [];
          for (let j: number = 0; j < arr.length; j++) {
            list.push(new TimeInterval(arr[j].start, arr[j].end));
          }
          intervals.set(Number(k), list);
        }
      }
      const data: BackupData = { events: events, records: records, intervals: intervals };
      return data;
    } catch (err) {
      return null;
    }
  }

  // ---------- 设置（排序模式；键与 Android 语义一致） ----------

  getSortMode(): string {
    return this.safeGet(KEY_SORT_MODE, SORT_MANUAL) as string;
  }

  setSortMode(mode: string): void {
    this.safePut(KEY_SORT_MODE, mode === SORT_RECENT ? SORT_RECENT : SORT_MANUAL);
  }

  // ---------- 通用偏好（卡片绑定等杂项；隐私同意状态也走这里） ----------

  getPrefNum(key: string, defaultValue: number): number {
    return this.safeGet(key, defaultValue) as number;
  }

  setPrefNum(key: string, value: number): void {
    this.safePut(key, value);
  }

  getPrefStr(key: string, defaultValue: string): string {
    return this.safeGet(key, defaultValue) as string;
  }

  setPrefStr(key: string, value: string): void {
    this.safePut(key, value);
  }

  private saveEvents(events: TimestampEvent[]): void {
    const arr: EventJson[] = events.map((e: TimestampEvent) => {
      const j: EventJson = { id: e.id, name: e.name, color: e.color, createdAt: e.createdAt, type: e.type };
      return j;
    });
    this.safePut(KEY_EVENTS, JSON.stringify(arr));
    this.notifyChanged();
  }

  // ---------- 点记录（毫秒时间戳，最新在前） ----------

  getRecords(eventId: number): number[] {
    const raw: string = this.safeGet(recordsKey(eventId), EMPTY_ARRAY) as string;
    let list: number[] = [];
    try {
      list = JSON.parse(raw) as number[];
    } catch (err) {
      list = [];
    }
    return list;
  }

  /** 记一条，返回写入的毫秒时间戳 */
  addRecord(eventId: number): number {
    const millis: number = Date.now();
    const list: number[] = this.getRecords(eventId);
    list.unshift(millis);
    this.saveRecords(eventId, list);
    return millis;
  }

  deleteRecord(eventId: number, position: number): void {
    const list: number[] = this.getRecords(eventId);
    if (position >= 0 && position < list.length) {
      list.splice(position, 1);
      this.saveRecords(eventId, list);
    }
  }

  /** 批量删除：按记录的时间戳值删除 */
  deleteRecords(eventId: number, toRemove: number[]): void {
    if (toRemove.length === 0) {
      return;
    }
    const list: number[] = this.getRecords(eventId).filter((m: number) => !toRemove.includes(m));
    this.saveRecords(eventId, list);
  }

  /** 撤销最新一条 */
  undoLast(eventId: number): boolean {
    const list: number[] = this.getRecords(eventId);
    if (list.length === 0) {
      return false;
    }
    list.shift();
    this.saveRecords(eventId, list);
    return true;
  }

  clearRecords(eventId: number): void {
    this.safeDelete(recordsKey(eventId));
    this.notifyChanged();
  }

  recordCount(eventId: number): number {
    return this.getRecords(eventId).length;
  }

  lastRecord(eventId: number): number | null {
    const list: number[] = this.getRecords(eventId);
    return list.length > 0 ? list[0] : null;
  }

  // ---------- 时间段（区间）记录 ----------

  /** 全部时间段，按 start 升序（末尾即最新一段；end 缺省 = 进行中） */
  getIntervals(eventId: number): TimeInterval[] {
    const raw: string = this.safeGet(intervalsKey(eventId), EMPTY_ARRAY) as string;
    let list: TimeInterval[] = [];
    try {
      const arr: IntervalJson[] = JSON.parse(raw) as IntervalJson[];
      list = arr.map((o: IntervalJson) => new TimeInterval(o.start, o.end));
    } catch (err) {
      list = [];
    }
    return list;
  }

  /** 当前进行中的时间段；没有则返回 null */
  getOngoingInterval(eventId: number): TimeInterval | null {
    const list: TimeInterval[] = this.getIntervals(eventId);
    let found: TimeInterval | null = null;
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].isOngoing()) {
        found = list[i];
      }
    }
    return found;
  }

  /** 开始一段；已有进行中的段则失败（返回 false） */
  startInterval(eventId: number): boolean {
    if (this.getOngoingInterval(eventId) !== null) {
      return false;
    }
    const list: TimeInterval[] = this.getIntervals(eventId);
    list.push(new TimeInterval(Date.now()));
    this.saveIntervals(eventId, list);
    return true;
  }

  /** 结束当前进行中的段；没有进行中的段则失败（返回 false） */
  stopInterval(eventId: number): boolean {
    const list: TimeInterval[] = this.getIntervals(eventId);
    let changed: boolean = false;
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].isOngoing()) {
        list[i].end = Date.now();
        changed = true;
      }
    }
    if (!changed) {
      return false;
    }
    this.saveIntervals(eventId, list);
    return true;
  }

  /** 撤销最后一段（进行中的直接删；否则删最近已完成的一段） */
  undoLastInterval(eventId: number): boolean {
    const list: TimeInterval[] = this.getIntervals(eventId);
    if (list.length === 0) {
      return false;
    }
    list.pop();
    this.saveIntervals(eventId, list);
    return true;
  }

  /** 按 start 值删除一段 */
  deleteIntervalByStart(eventId: number, start: number): void {
    const list: TimeInterval[] = this.getIntervals(eventId).filter((it: TimeInterval) => it.start !== start);
    this.saveIntervals(eventId, list);
  }

  /** 批量删除：按 start 值集合删除 */
  deleteIntervals(eventId: number, toRemove: number[]): void {
    if (toRemove.length === 0) {
      return;
    }
    const list: TimeInterval[] = this.getIntervals(eventId).filter((it: TimeInterval) => !toRemove.includes(it.start));
    this.saveIntervals(eventId, list);
  }

  clearIntervals(eventId: number): void {
    this.safeDelete(intervalsKey(eventId));
    this.notifyChanged();
  }

  intervalCount(eventId: number): number {
    return this.getIntervals(eventId).length;
  }

  /** 已结束时间段的总时长（毫秒）；进行中的段不计入 */
  totalIntervalDuration(eventId: number): number {
    let sum: number = 0;
    const list: TimeInterval[] = this.getIntervals(eventId);
    for (let i: number = 0; i < list.length; i++) {
      if (!list[i].isOngoing()) {
        sum += list[i].duration();
      }
    }
    return sum;
  }

  /** 备份用：全部事件的时间段 */
  getAllIntervals(): Map<number, TimeInterval[]> {
    const map: Map<number, TimeInterval[]> = new Map<number, TimeInterval[]>();
    this.getEvents().forEach((ev: TimestampEvent) => {
      map.set(ev.id, this.getIntervals(ev.id));
    });
    return map;
  }

  private saveIntervals(eventId: number, list: TimeInterval[]): void {
    this.safePut(intervalsKey(eventId), JSON.stringify(list));
    this.notifyChanged();
  }

  private saveRecords(eventId: number, records: number[]): void {
    this.safePut(recordsKey(eventId), JSON.stringify(records));
    this.notifyChanged();
  }

  // ---------- 时间线 ----------

  /** 时间线：点记录 + 时间段（按 start）合并，统一按时间倒序 */
  getAllRecords(): TimelineRecord[] {
    const out: TimelineRecord[] = [];
    this.getEvents().forEach((ev: TimestampEvent) => {
      this.getRecords(ev.id).forEach((m: number) => {
        out.push(new TimelineRecord(ev.id, ev.name, ev.color, m));
      });
      this.getIntervals(ev.id).forEach((it: TimeInterval) => {
        out.push(new TimelineRecord(ev.id, ev.name, ev.color, it.start, it));
      });
    });
    out.sort((a: TimelineRecord, b: TimelineRecord) => b.millis - a.millis);
    return out;
  }
}
