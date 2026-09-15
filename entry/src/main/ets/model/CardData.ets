/**
 * 服务卡片共享数据结构（FormAbility 构建 → formBindingData → 卡片页 @LocalStorageProp）。
 * 注意：卡片数据必须可 JSON 序列化（纯 plain object / string / number），不要放类实例。
 */

/** 全事件卡片行 */
export interface CardEventJson {
  id: number;
  name: string;
  color: string;
  lastText: string;
}

/** 全事件卡片载荷 */
export interface CardAllPayload {
  formName: string;
  dimension: string;
  hasData: boolean;
  events: CardEventJson[];
  rest: number;
}

/** 单事件 / 胶囊卡片载荷 */
export interface CardSinglePayload {
  formName: string;
  dimension: string;
  hasData: boolean;
  eventId: number;
  name: string;
  color: string;
  lastText: string;
  count: number;
}

export const FORM_ALL: string = 'all_events';
export const FORM_SINGLE: string = 'single_event';
export const FORM_CAPSULE: string = 'capsule';

/** 绑定前缀：form_bind_<formName> → eventId */
export const PREF_BIND_PREFIX: string = 'form_bind_';
export const CARD_DARK: string = '#F01A1C1E';
export const CARD_MISSING: string = '#546E7A';
export const CARD_TEXT: string = '#FFFFFF';
export const CARD_TEXT_SUB: string = '#CCFFFFFF';
export const CARD_TEXT_DIM: string = '#99FFFFFF';

/** 维度枚举值（formInfo.FormDimension）→ 字符串标签 */
export function dimLabel(d: number): string {
  if (d === 1) {
    return '1*2';
  }
  if (d === 3) {
    return '2*4';
  }
  if (d === 4) {
    return '4*4';
  }
  return '2*2';
}

/** 4*4 显示更多行 */
export function maxRowsOf(dim: string): number {
  return dim === '4*4' ? 6 : 4;
}
