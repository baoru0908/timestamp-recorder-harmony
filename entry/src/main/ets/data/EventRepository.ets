import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { EventJson, TimelineRecord, TimestampEvent } from '../model/TimestampEvent';

const STORE_NAME: string = 'tsr_data';
const KEY_EVENTS: string = 'events';
const KEY_SORT_MODE: string = 'sort_mode';
const EMPTY_ARRAY: string = '[]';
const SORT_MANUAL: string = 'manual';
const SORT_RECENT: string = 'recent';

function recordsKey(id: number): string {
  return `records_${id}`;
}

/** 备份数据（对齐 Android BackupHelper.BackupData） */
export interface BackupData {
  events: TimestampEvent[];
  records: Map<number, number[]>;
}

/** 备份文件根结构（对齐 Android BackupHelper.exportJson） */
interface BackupRoot {
  app: string;
  format: number;
  exportedAt: number;
  events: EventJson[];
  records: Record<string, number[]>;
}

/**
 * 数据层：Preferences + JSON，零第三方依赖、纯本地。
 *
 * 存储结构与键名与 Android 版完全一致（见 docs/port-spec.md §2）：
 * - `events`            → JSON 数组，**数组顺序 = 手动排序顺序**
 * - `records_<eventId>` → JSON 数组，**最新在前（index 0 是最新一条）**
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
      list = arr.map((o: EventJson) => new TimestampEvent(o.id, o.name, o.color, o.createdAt));
    } catch (err) {
      list = [];
    }
    return list;
  }

  getEvent(id: number): TimestampEvent | null {
    const found: TimestampEvent[] = this.getEvents().filter((e: TimestampEvent) => e.id === id);
    return found.length > 0 ? found[0] : null;
  }

  addEvent(name: string, color: number): TimestampEvent {
    const events: TimestampEvent[] = this.getEvents();
    let id: number = Date.now();
    while (events.some((e: TimestampEvent) => e.id === id)) {
      id++;
    }
    const ev: TimestampEvent = new TimestampEvent(id, name.trim(), color, Date.now());
    events.push(ev);
    this.saveEvents(events);
    return ev;
  }

  updateEvent(id: number, name: string, color: number): void {
    const next: TimestampEvent[] = this.getEvents().map((e: TimestampEvent) => {
      if (e.id === id) {
        return new TimestampEvent(e.id, name.trim(), color, e.createdAt);
      }
      return e;
    });
    this.saveEvents(next);
  }

  /** 删除事件：连同它的全部记录一起删 */
  deleteEvent(id: number): void {
    this.saveEvents(this.getEvents().filter((e: TimestampEvent) => e.id !== id));
    this.safeDelete(recordsKey(id));
  }

  /** 手动顺序（即存储数组的顺序） */
  getEventsManualOrder(): TimestampEvent[] {
    return this.getEvents();
  }

  /** 按最近记录时间降序；无记录的事件排在最后 */
  getEventsByRecent(): TimestampEvent[] {
    const out: TimestampEvent[] = this.getEvents();
    out.sort((a: TimestampEvent, b: TimestampEvent) => {
      const la: number | null = this.lastRecord(a.id);
      const lb: number | null = this.lastRecord(b.id);
      const va: number = la === null ? -1 : la;
      const vb: number = lb === null ? -1 : lb;
      return vb - va;
    });
    return out;
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
  replaceAllData(events: TimestampEvent[], records: Map<number, number[]>): void {
    // 先按旧事件列表逐个清掉记录键，避免残留
    this.getEvents().forEach((e: TimestampEvent) => {
      this.safeDelete(recordsKey(e.id));
    });
    this.saveEvents(events);
    records.forEach((list: number[], id: number) => {
      this.saveRecords(id, list);
    });
  }

  // ---------- 备份（对齐 Android BackupHelper，格式红线：app=timestamp-recorder / format=1） ----------

  /** 导出全量 JSON（结构与 Android 完全互通） */
  exportJson(): string {
    const evArr: EventJson[] = this.getEvents().map((e: TimestampEvent) => {
      const j: EventJson = { id: e.id, name: e.name, color: e.color, createdAt: e.createdAt };
      return j;
    });
    const recObj: Record<string, number[]> = {};
    this.getEvents().forEach((e: TimestampEvent) => {
      recObj[`${e.id}`] = this.getRecords(e.id);
    });
    const root: BackupRoot = {
      app: 'timestamp-recorder',
      format: 1,
      exportedAt: Date.now(),
      events: evArr,
      records: recObj
    };
    return JSON.stringify(root, null, 2);
  }

  /** 解析备份 JSON；格式不符返回 null */
  parseBackup(json: string): BackupData | null {
    try {
      const root: BackupRoot = JSON.parse(json) as BackupRoot;
      if (root.app !== 'timestamp-recorder') {
        return null;
      }
      const events: TimestampEvent[] = root.events.map((o: EventJson) =>
        new TimestampEvent(o.id, o.name, o.color, o.createdAt));
      const records: Map<number, number[]> = new Map<number, number[]>();
      const keys: string[] = Object.keys(root.records);
      keys.forEach((k: string) => {
        records.set(Number(k), root.records[k]);
      });
      const data: BackupData = { events: events, records: records };
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

  // ---------- 通用偏好（卡片绑定等杂项） ----------

  getPrefNum(key: string, defaultValue: number): number {
    return this.safeGet(key, defaultValue) as number;
  }

  setPrefNum(key: string, value: number): void {
    this.safePut(key, value);
  }

  private saveEvents(events: TimestampEvent[]): void {
    const arr: EventJson[] = events.map((e: TimestampEvent) => {
      const j: EventJson = { id: e.id, name: e.name, color: e.color, createdAt: e.createdAt };
      return j;
    });
    this.safePut(KEY_EVENTS, JSON.stringify(arr));
    this.notifyChanged();
  }

  // ---------- 记录（毫秒时间戳，最新在前） ----------

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

  /** 时间线：全部事件的所有记录合并，按时间倒序 */
  getAllRecords(): TimelineRecord[] {
    const out: TimelineRecord[] = [];
    this.getEvents().forEach((ev: TimestampEvent) => {
      this.getRecords(ev.id).forEach((m: number) => {
        out.push(new TimelineRecord(ev.id, ev.name, ev.color, m));
      });
    });
    out.sort((a: TimelineRecord, b: TimelineRecord) => b.millis - a.millis);
    return out;
  }

  private saveRecords(eventId: number, records: number[]): void {
    this.safePut(recordsKey(eventId), JSON.stringify(records));
    this.notifyChanged();
  }
}
