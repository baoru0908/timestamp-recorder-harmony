import { common } from '@kit.AbilityKit';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import { fileIo as fs } from '@kit.CoreFileKit';
import { EventRepository } from '../data/EventRepository';
import { TimestampEvent, TimeInterval, colorToHex } from '../model/TimestampEvent';
import { TimeFormat } from '../util/TimeFormat';
import {
  CardEventJson,
  CardAllPayload,
  CardSinglePayload,
  dimLabel,
  maxRowsOf,
  maxRowsOfCustom,
  customTextColors,
  cardCountText,
  PREF_BIND_PREFIX,
  PREF_CUSTOM_TITLE,
  PREF_CUSTOM_BG,
  PREF_CUSTOM_IMG,
  PREF_CUSTOM_EVENTS,
  CUSTOM_DEFAULT_TITLE,
  CUSTOM_IMG_KEY,
  CARD_TX_RECORDING,
  CARD_TX_IV_IDLE,
  CARD_TX_IV_START,
  CARD_TX_NO_RECORD,
  CARD_TX_IV_HINT,
  CARD_TX_CLICK_HINT,
  CARD_TX_MISSING,
  FORM_ALL,
  FORM_SINGLE,
  FORM_CAPSULE,
  FORM_CUSTOM,
  CARD_MISSING
} from '../model/CardData';

/**
 * 卡片行内「最近时间」文案 —— **三种卡片共用同一套规则**，逐条对齐 Android：
 * - 时间段：进行中 → `● 进行中`；有段 → 最近一段的 end（缺省用 start）的 HH:mm:ss；无段 → `未开始`（单事件大卡片用 `点此开始`）
 * - 点时刻：有记录 → 最近一条的 HH:mm:ss；无 → `未记录`
 * 边界说明：跨天的时间段只显示「时:分:秒」（与 Android 一致，不显示日期）；两端均为本地时区。
 */
function rowTimeText(repo: EventRepository, ev: TimestampEvent, singleCard: boolean): string {
  if (ev.isInterval()) {
    if (repo.getOngoingInterval(ev.id) !== null) {
      return CARD_TX_RECORDING;
    }
    const latest: TimeInterval | null = repo.latestInterval(ev.id);
    if (latest !== null) {
      return TimeFormat.hm(latest.end ?? latest.start);
    }
    return singleCard ? CARD_TX_IV_START : CARD_TX_IV_IDLE;
  }
  const last: number | null = repo.lastRecord(ev.id);
  return last !== null ? TimeFormat.hm(last) : CARD_TX_NO_RECORD;
}

/**
 * 服务卡片数据构建 + 全量刷新。
 * FormAbility 与 App 页面共用（App 内数据变化后调 syncAllForms 回刷所有已添加卡片）。
 *
 * 背景图（自定义卡片）走官方 fd 机制：把沙箱图片以 **fd** 放进 `formImages`，
 * 卡片端用 `Image('memory://<key>')` 渲染（卡片不能直接读沙箱路径）。
 * fd 生命周期：本次刷新打开 → 下次刷新前关闭（见 closeTrackedFds），避免 fd 泄漏。
 */

/** 已下发的图片 fd 登记表：formId → fd 列表（用于下次刷新前回收） */
const trackedFds: Map<string, number[]> = new Map<string, number[]>();

/** 关闭某卡片上一轮打开的所有图片 fd */
export function closeTrackedFds(formId: string): void {
  const arr: number[] | undefined = trackedFds.get(formId);
  if (arr === undefined) {
    return;
  }
  for (let i: number = 0; i < arr.length; i++) {
    try {
      fs.closeSync(arr[i]);
    } catch (err) {
    }
  }
  trackedFds.delete(formId);
}

/** 登记本次下发的 fd（下次刷新前关闭） */
function trackFds(formId: string, data: Record<string, Object>): void {
  const imgs: Record<string, number> | undefined = data['formImages'] as Record<string, number> | undefined;
  if (imgs === undefined) {
    return;
  }
  const keys: string[] = Object.keys(imgs);
  const fds: number[] = [];
  for (let i: number = 0; i < keys.length; i++) {
    fds.push(imgs[keys[i]]);
  }
  if (fds.length > 0) {
    trackedFds.set(formId, fds);
  }
}

/** 读取勾选的事件 id 列表（JSON 数组字符串；解析失败返回空） */
function readCustomIds(repo: EventRepository): number[] {
  const raw: string = repo.getPrefStr(PREF_CUSTOM_EVENTS, '[]');
  let ids: number[] = [];
  try {
    const arr: number[] = JSON.parse(raw) as number[];
    if (Array.isArray(arr)) {
      ids = arr;
    }
  } catch (err) {
    ids = [];
  }
  return ids;
}

export function buildFormData(ctx: common.Context, name: string, dim: number): Record<string, Object> {
  const repo = new EventRepository(ctx);

  // ---------- 自定义卡片：标题 + 背景色/背景图 + 勾选多事件 ----------
  if (name === FORM_CUSTOM) {
    const dimStr: string = dimLabel(dim);
    const title: string = repo.getPrefStr(PREF_CUSTOM_TITLE, CUSTOM_DEFAULT_TITLE);
    const bgHex: string = colorToHex(repo.getPrefNum(PREF_CUSTOM_BG, 0xFF1A1C1E | 0));
    const imgFile: string = repo.getPrefStr(PREF_CUSTOM_IMG, '');

    const out: Record<string, Object> = {};
    // 背景图：文件存在才下发 fd，否则降级为纯底色（不白屏）
    let hasBg: boolean = false;
    if (imgFile.length > 0) {
      const path: string = `${ctx.filesDir}/${imgFile}`;
      try {
        if (fs.accessSync(path)) {
          const f = fs.openSync(path, fs.OpenMode.READ_ONLY);
          const imgMap: Record<string, number> = {};
          imgMap[CUSTOM_IMG_KEY] = f.fd;
          out['formImages'] = imgMap;
          hasBg = true;
        }
      } catch (err) {
        hasBg = false;
      }
    }

    // 勾选的事件（过滤已被删除的 id）
    const ids: number[] = readCustomIds(repo);
    const cap: number = maxRowsOfCustom(dimStr);
    const rows: CardEventJson[] = [];
    let valid: number = 0;
    for (let i: number = 0; i < ids.length; i++) {
      const ev: TimestampEvent | null = repo.getEvent(ids[i]);
      if (ev === null) {
        continue;
      }
      valid++;
      if (rows.length < cap) {
        const row: CardEventJson = {
          id: ev.id,
          name: ev.name,
          color: colorToHex(ev.color),
          lastText: rowTimeText(repo, ev, false)
        };
        rows.push(row);
      }
    }

    // 文字色：有背景图时统一走深底白字（图上叠加了压暗遮罩）
    const cols: string[] = customTextColors(hasBg ? '#000000' : bgHex);
    out['formName'] = name;
    out['dimension'] = dimStr;
    out['hasData'] = valid > 0;
    out['title'] = title;
    out['bgColor'] = bgHex;
    out['hasBgImage'] = hasBg;
    out['bgImageKey'] = CUSTOM_IMG_KEY;
    out['titleColor'] = cols[0];
    out['textColor'] = cols[1];
    out['subTextColor'] = cols[2];
    out['events'] = rows;
    out['rest'] = valid > rows.length ? valid - rows.length : 0;
    return out;
  }

  // ---------- 单事件 / 胶囊 ----------
  if (name === FORM_SINGLE || name === FORM_CAPSULE) {
    const payload: CardSinglePayload = {
      formName: name,
      dimension: dimLabel(dim),
      hasData: false,
      eventId: 0,
      name: CARD_TX_MISSING,
      color: CARD_MISSING,
      lastText: '',
      count: 0,
      hint: CARD_TX_CLICK_HINT,
      isInterval: false
    };
    const bindId: number = repo.getPrefNum(`${PREF_BIND_PREFIX}${name}`, 0);
    const ev: TimestampEvent | null = bindId > 0 ? repo.getEvent(bindId) : null;
    if (ev !== null) {
      payload.hasData = true;
      payload.eventId = ev.id;
      payload.name = ev.name;
      payload.color = colorToHex(ev.color);
      // 时间段 → 进行中 / 最近一段结束时间 / 点此开始；点时刻 → 最近记录时间 / 未记录
      payload.lastText = rowTimeText(repo, ev, true);
      // 计数：时间段统计「段数」，点时刻统计「条数」（对齐 Android WidgetSingleProvider）
      payload.count = ev.isInterval() ? repo.intervalCount(ev.id) : repo.recordCount(ev.id);
      payload.hint = ev.isInterval() ? CARD_TX_IV_HINT : CARD_TX_CLICK_HINT;
      payload.isInterval = ev.isInterval();
    }
    const out: Record<string, Object> = {};
    out['formName'] = payload.formName;
    out['dimension'] = payload.dimension;
    out['hasData'] = payload.hasData;
    out['eventId'] = payload.eventId;
    out['name'] = payload.name;
    out['color'] = payload.color;
    out['lastText'] = payload.lastText;
    out['count'] = payload.count;
    out['hint'] = payload.hint;
    out['isInterval'] = payload.isInterval;
    return out;
  }

  // ---------- 全事件卡片 ----------
  const payload: CardAllPayload = {
    formName: name,
    dimension: dimLabel(dim),
    hasData: false,
    events: [],
    rest: 0
  };
  const events: TimestampEvent[] = repo.getEvents();
  payload.hasData = events.length > 0;
  const cap: number = maxRowsOf(payload.dimension);
  events.forEach((e: TimestampEvent) => {
    if (payload.events.length >= cap) {
      return;
    }
    const row: CardEventJson = {
      id: e.id,
      name: e.name,
      color: colorToHex(e.color),
      lastText: rowTimeText(repo, e, false)
    };
    payload.events.push(row);
  });
  payload.rest = events.length > payload.events.length ? events.length - payload.events.length : 0;
  const out: Record<string, Object> = {};
  out['formName'] = payload.formName;
  out['dimension'] = payload.dimension;
  out['hasData'] = payload.hasData;
  out['events'] = payload.events;
  out['rest'] = payload.rest;
  return out;
}

/**
 * 构建并下发单个卡片数据（含图片 fd 的生命周期管理）。
 * App 侧（syncAllForms）与 FormAbility 侧（refreshAll）共用，避免逻辑重复。
 */
export function updateOneForm(ctx: common.Context, formId: string, name: string, dim: number): Promise<void> {
  // 先回收上一轮 fd，再构建新数据（避免图片 fd 泄漏）
  closeTrackedFds(formId);
  const data: Record<string, Object> = buildFormData(ctx, name, dim);
  trackFds(formId, data);
  return formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
}

/** 回刷当前应用的所有已发布卡片 */
export function syncAllForms(ctx: common.Context): void {
  formProvider.getPublishedRunningFormInfos().then((infos) => {
    infos.forEach((info) => {
      updateOneForm(ctx, info.formId, info.formName, info.dimension).catch(() => {});
    });
  }).catch(() => {});
}
