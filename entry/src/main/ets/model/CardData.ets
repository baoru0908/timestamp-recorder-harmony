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
  /** 底部提示文案：时间段 → 点击开始 / 结束；点时刻 → 点击记录（对齐 Android widget_interval_hint / widget_click_hint） */
  hint: string;
  /** 绑定事件是否为时间段形态（胶囊卡片据此显示「开始 / 结束」而非「记录」） */
  isInterval: boolean;
}

/**
 * 自定义卡片载荷（对齐 Android WidgetCustomProvider）：
 * 标题 + 背景色（或背景图）+ 勾选的多行事件。
 */
export interface CardCustomPayload {
  formName: string;
  dimension: string;
  hasData: boolean;
  /** 卡片标题（用户可自定义） */
  title: string;
  /** 背景色（hex 字符串；有背景图时作为兜底/降级色） */
  bgColor: string;
  /** 是否下发背景图（true 时卡片渲染 Image('memory://<bgImageKey>')） */
  hasBgImage: boolean;
  /** 背景图在 formImages 中的 key（卡片端拼 memory:// 用） */
  bgImageKey: string;
  /** 标题文字色（按背景亮度自适应的白色或近黑） */
  titleColor: string;
  /** 行主文字色 */
  textColor: string;
  /** 行副文字色 */
  subTextColor: string;
  events: CardEventJson[];
  rest: number;
}

export const FORM_ALL: string = 'all_events';
export const FORM_SINGLE: string = 'single_event';
export const FORM_CAPSULE: string = 'capsule';
export const FORM_CUSTOM: string = 'custom';

/** 绑定前缀：form_bind_<formName> → eventId */
export const PREF_BIND_PREFIX: string = 'form_bind_';
/**
 * 卡片实例元信息前缀：`form_meta_<formId>` → `"<formName>|<dimension>"`。
 * 用途：`onFormEvent` 只拿到 formId，靠异步反查 formName 会让刷新链路变长
 * （进程回收时刷新失败的根因），落盘后可直接定位卡片类型。
 */
export const PREF_FORM_META: string = 'form_meta_';

// —— 自定义卡片配置键（按 formName 存，与现有绑定模式一致）——
/** 标题 */
export const PREF_CUSTOM_TITLE: string = 'form_custom_title';
/** 背景色（有符号 int） */
export const PREF_CUSTOM_BG: string = 'form_custom_bgcolor';
/** 背景图文件名（存于 filesDir，空串 = 无背景图） */
export const PREF_CUSTOM_IMG: string = 'form_custom_bgimage';
/** 勾选的事件 id 列表（JSON 数组字符串） */
export const PREF_CUSTOM_EVENTS: string = 'form_custom_events';

/** 标题默认值 */
export const CUSTOM_DEFAULT_TITLE: string = '我的记录';
/** 背景图在 formImages 里的固定 key */
export const CUSTOM_IMG_KEY: string = 'custombg';
/** 背景图在沙箱中的固定文件名（单卡片配置，一卡一图） */
export const CUSTOM_IMG_FILE: string = 'custom_card_bg.jpg';
/** 背景图入库前的最大边长（超过则等比缩放，控制卡片渲染开销） */
export const CUSTOM_IMG_MAX_SIDE: number = 720;

/** 背景色预设（对齐 Android 6 预设：深浅混合，浅色会自动切换深色文字） */
export const CUSTOM_BG_PRESETS: string[] = [
  '#1A1C1E', // 深灰（默认）
  '#1E3A5F', // 深蓝
  '#3E2723', // 深棕
  '#1B3A2F', // 深绿
  '#3A1B2F', // 深紫
  '#F5F5F5'  // 浅灰（浅底→深色文字）
];

export const CARD_DARK: string = '#F01A1C1E';
export const CARD_MISSING: string = '#546E7A';
export const CARD_TEXT: string = '#FFFFFF';
export const CARD_TEXT_SUB: string = '#CCFFFFFF';
export const CARD_TEXT_DIM: string = '#99FFFFFF';
/** 浅底卡片使用的文字色 */
export const CARD_TEXT_ON_LIGHT: string = '#1A1C1E';
export const CARD_SUB_ON_LIGHT: string = '#991A1C1E';

// ---------- 卡片文案（逐条对齐 Android res/values/strings.xml，改文案时两端同步） ----------
/** 时间段进行中：widget_recording_dot */
export const CARD_TX_RECORDING: string = '● 进行中';
/** 时间段尚无任何段：widget_interval_idle */
export const CARD_TX_IV_IDLE: string = '未开始';
/** 时间段尚无任何段（单事件大卡片用）：widget_interval_start */
export const CARD_TX_IV_START: string = '点此开始';
/** 点时刻尚无记录：widget_row_no_record */
export const CARD_TX_NO_RECORD: string = '未记录';
/** 时间段卡片底部提示：widget_interval_hint */
export const CARD_TX_IV_HINT: string = '点击开始 / 结束';
/** 点时刻卡片底部提示：widget_click_hint */
export const CARD_TX_CLICK_HINT: string = '点击记录';
/** 绑定事件已被删除（短）：widget_single_missing_short */
export const CARD_TX_MISSING: string = '已删除';
/** 绑定事件已被删除（长）：widget_single_missing */
export const CARD_TX_MISSING_LONG: string = '事件已删除，长按重新配置';

/** 单事件卡片计数文案：widget_single_count（"共 %1$d 次"） */
export function cardCountText(n: number): string {
  return `共 ${n} 次`;
}

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

/**
 * 卡片排版档位（多事件场景的统一栅格）。
 *
 * 设计规则（详见 `release/CARD_LAYOUT_SPEC.md`）：
 * - **左基线**：标题左缘 = 行块左缘 = padH；时间右缘 = padH（正文左对齐、时间右对齐）
 * - **垂直**：行内元素一律垂直居中；行高 = 内容高 + 2×rowPadV
 * - **层级**：标题(L1) > 事件名(L2) > 时间/提示(L3) > 溢出提示(L4)
 * - **响应式**：按卡片尺寸档位取整套参数（1*2 / 2*2 / 2*4 / 4*4），字号与间距同步缩放，
 *   避免"小尺寸塞大字号导致溢出、大尺寸用小球导致空旷"
 */
export interface CardMetrics {
  /** 卡片左右内边距 */
  padH: number;
  /** 顶部内边距 */
  padTop: number;
  /** 底部内边距 */
  padBottom: number;
  /** 标题字号（L1） */
  titleSize: number;
  /** 次级提示字号（右上提示 / 溢出提示） */
  hintSize: number;
  /** 行块左右内边距（内容左基线 = padH + rowPadH） */
  rowPadH: number;
  /** 行高（内容 + 上下内边距） */
  rowH: number;
  /** 行内上下内边距 */
  rowPadV: number;
  /** 行间距 */
  rowGap: number;
  /** 事件名字号（L2） */
  nameSize: number;
  /** 时间字号（L3） */
  timeSize: number;
  /** 色点直径 */
  dotSize: number;
  /** 色点与事件名间距 */
  dotGap: number;
  /** 行块圆角 */
  rowRadius: number;
  /** 最多显示行数（超出显示「还有 N 个事件」） */
  maxRows: number;
}

/** 1*2 极扁档：只放得下一行 */
const M_1X2: CardMetrics = {
  padH: 12, padTop: 8, padBottom: 8,
  titleSize: 13, hintSize: 9,
  rowPadH: 10, rowH: 26, rowPadV: 5, rowGap: 4,
  nameSize: 12, timeSize: 10, dotSize: 8, dotGap: 6, rowRadius: 8,
  maxRows: 1
};

/** 2*2 标准档 */
const M_2X2: CardMetrics = {
  padH: 14, padTop: 12, padBottom: 10,
  titleSize: 15, hintSize: 10,
  rowPadH: 12, rowH: 32, rowPadV: 7, rowGap: 6,
  nameSize: 13, timeSize: 11, dotSize: 10, dotGap: 8, rowRadius: 12,
  maxRows: 4
};

/** 2*4 竖长档 */
const M_2X4: CardMetrics = {
  padH: 16, padTop: 14, padBottom: 12,
  titleSize: 16, hintSize: 10,
  rowPadH: 12, rowH: 36, rowPadV: 8, rowGap: 6,
  nameSize: 14, timeSize: 11, dotSize: 10, dotGap: 8, rowRadius: 12,
  maxRows: 6
};

/** 4*4 大卡档 */
const M_4X4: CardMetrics = {
  padH: 18, padTop: 16, padBottom: 14,
  titleSize: 17, hintSize: 11,
  rowPadH: 14, rowH: 40, rowPadV: 9, rowGap: 8,
  nameSize: 15, timeSize: 12, dotSize: 12, dotGap: 10, rowRadius: 14,
  maxRows: 6
};

/** 内容左基线（标题、行内文本、溢出提示统一缩进到这条竖线） */
export function contentInset(m: CardMetrics): number {
  return m.padH + m.rowPadH;
}

/** 按尺寸档位取整套排版参数（未知尺寸按 2*2 处理） */
export function cardMetricsOf(dim: string): CardMetrics {
  if (dim === '1*2') {
    return M_1X2;
  }
  if (dim === '2*4') {
    return M_2X4;
  }
  if (dim === '4*4') {
    return M_4X4;
  }
  return M_2X2;
}

/** 多事件卡片可显示的列表行数上限（按档位；与排版参数同源，避免"参数改了行数没改"） */
export function maxRowsOf(dim: string): number {
  return cardMetricsOf(dim).maxRows;
}

/** 自定义卡片与外层共享同一套行数规则 */
export function maxRowsOfCustom(dim: string): number {
  return cardMetricsOf(dim).maxRows;
}

/**
 * 判断 hex 颜色是否属于「浅色」（相对亮度 > 0.6）→ 决定卡片文字用深色还是白色。
 * 与 Android EventColors.onColor 的阈值保持一致（0.60）。
 * 解析失败时按深色处理（返回 false → 用白字，最保守）。
 */
export function isLightHex(hex: string): boolean {
  let h: string = hex.trim();
  if (h.startsWith('#')) {
    h = h.substring(1);
  }
  if (h.length !== 6) {
    return false;
  }
  const r: number = Number.parseInt(h.substring(0, 2), 16);
  const g: number = Number.parseInt(h.substring(2, 4), 16);
  const b: number = Number.parseInt(h.substring(4, 6), 16);
  if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
    return false;
  }
  // 感知亮度（与 Android 侧同一套系数）
  const lum: number = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return lum > 0.6;
}

/** 依背景色给出（标题色 / 主文字色 / 副文字色）三元组 */
export function customTextColors(bgHex: string): string[] {
  if (isLightHex(bgHex)) {
    return [CARD_TEXT_ON_LIGHT, CARD_TEXT_ON_LIGHT, CARD_SUB_ON_LIGHT];
  }
  return [CARD_TEXT, CARD_TEXT, CARD_TEXT_SUB];
}
