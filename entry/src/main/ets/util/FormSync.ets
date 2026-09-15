import { common } from '@kit.AbilityKit';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import { EventRepository } from '../data/EventRepository';
import { TimestampEvent } from '../model/TimestampEvent';
import { colorToHex } from '../model/TimestampEvent';
import { TimeFormat } from '../util/TimeFormat';
import { CardEventJson, CardAllPayload, CardSinglePayload, dimLabel, maxRowsOf, PREF_BIND_PREFIX, FORM_ALL, FORM_SINGLE, FORM_CAPSULE, CARD_MISSING } from '../model/CardData';

/**
 * 服务卡片数据构建 + 全量刷新。
 * FormAbility 与 App 页面共用（App 内数据变化后调 syncAllForms 回刷所有已添加卡片）。
 */
export function buildFormData(ctx: common.Context, name: string, dim: number): Record<string, Object> {
  const repo = new EventRepository(ctx);
  if (name === FORM_SINGLE || name === FORM_CAPSULE) {
    const payload: CardSinglePayload = {
      formName: name,
      dimension: dimLabel(dim),
      hasData: false,
      eventId: 0,
      name: '未绑定事件',
      color: CARD_MISSING,
      lastText: '',
      count: 0
    };
    const bindId: number = repo.getPrefNum(`${PREF_BIND_PREFIX}${name}`, 0);
    const ev: TimestampEvent | null = bindId > 0 ? repo.getEvent(bindId) : null;
    if (ev !== null) {
      const last: number | null = repo.lastRecord(ev.id);
      payload.hasData = true;
      payload.eventId = ev.id;
      payload.name = ev.name;
      payload.color = colorToHex(ev.color);
      payload.lastText = last !== null ? TimeFormat.hm(last) : '暂无记录';
      payload.count = repo.recordCount(ev.id);
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
    return out;
  }
  // 全事件卡片
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
    const last: number | null = repo.lastRecord(e.id);
    const row: CardEventJson = {
      id: e.id,
      name: e.name,
      color: colorToHex(e.color),
      lastText: last !== null ? TimeFormat.hm(last) : '暂无'
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

/** 回刷当前应用的所有已发布卡片 */
export function syncAllForms(ctx: common.Context): void {
  formProvider.getPublishedRunningFormInfos().then((infos) => {
    infos.forEach((info) => {
      const data: Record<string, Object> = buildFormData(ctx, info.formName, info.dimension);
      formProvider.updateForm(info.formId, formBindingData.createFormBindingData(data)).catch(() => {});
    });
  }).catch(() => {});
}
