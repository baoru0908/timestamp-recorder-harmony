/**
 * 语义化设计令牌（对齐 Android 原项目 values/colors.xml + values-night/colors.xml）。
 * 全部用 string 而不是 $r 资源：事件色等需要动态拼接透明度（`${hex}99`），string 更顺手。
 * 深浅两套由 getTheme(isDark) 切换；isDark 由 AppStorage('isDark') 全局驱动，跟随系统。
 */
import uiMaterial from '@ohos.arkui.uiMaterial';
import deviceInfo from '@ohos.deviceInfo';

/**
 * 液态玻璃统一封装（API 26 ImmersiveMaterial）。
 *
 * 跟随系统「沉浸光感」风格的两个前提（缺一不可）：
 *  1) entry/module.json5 声明 metadata [{ name:"ohos.arkui.UIMaterial.state", value:"enable" }]
 *     → 应用 MaterialState 置为 ENABLE，系统材质样式优先级高于组件自身 background/blur → 真正跟随系统光感。
 *  2) 运行设备系统 ≥ HarmonyOS 7 / API 26（系统级沉浸光感是 API 26 特性，见 SKILL.md 空间化章节）。
 *     当前兼容档 6.0.2(22)：平板(HarmonyOS 6.1.0)不满足，仅降级静态高斯模糊；
 *     模拟器(nova 16 Pro, HarmonyOS 7.0.0/API 26)满足，但本机 DevEco 6.2 SDK 仅装 6.0.2(22)，
 *     无法编译 target=26 的包（hvigor 报 illegal），故 app 仍跑 22 兼容档、systemMaterial 被系统禁用 → 同样降级。
 *     → 需升级 DevEco/SDK 到 API 26 支持并把 app target 提到 26.0.0(26)，模拟器方能真跟随光感。
 *
 * applyGlass 行为：
 *  - getMaterialInfo().state===ENABLE 且 isImmersiveMaterialSupported() 时 → 纯 systemMaterial + lightEffect:{color:undefined} 跟随系统，
 *    绝不叠 backgroundEffect（会盖住系统材质、造成「不随系统光感」的静态模糊）。
 *  - 其余（系统/SDK 不支持）→ 仅 backgroundEffect 实时高斯模糊降级，带极低 alpha 底色保可见。
 */
type AnyGlassAttr = RowAttribute | ColumnAttribute | StackAttribute;

/** 模拟器即使系统是 API 26 且 state=ENABLE，渲染层也不实现 systemMaterial（调了就整片透明）→ 必须走模糊兜底 */
function isEmulator(): boolean {
  try {
    return deviceInfo.productModel.toLowerCase().includes('emulator');
  } catch (e) {
    return false;
  }
}

function applyGlass(attr: AnyGlassAttr, color: string, radius: number): void {
  let useSystem: boolean = false;
  try {
    // 三条件：非模拟器 + 设备支持 + 应用级 MaterialState 已 ENABLED（module.json5 metadata 生效）。
    useSystem = !isEmulator() &&
      uiMaterial.isImmersiveMaterialSupported() &&
      uiMaterial.getMaterialInfo().state === uiMaterial.MaterialState.ENABLE;
  } catch (e) {
    useSystem = false;
  }
  if (useSystem) {
    // 跟随系统沉浸光感：仅 systemMaterial；lightEffect 显式置 undefined 表示光感跟随系统、不写死颜色。
    // 严禁再叠 backgroundEffect —— ENABLE 状态下系统材质优先级最高，叠加模糊只会盖住/混淆系统光感。
    attr.systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: true,
      lightEffect: { color: undefined }
    }));
  } else {
    // 系统材质不可用（设备系统版本不足 / SDK 受限 / metadata 未生效）：降级实时高斯模糊，带极低 alpha 底色保可见。
    attr.backgroundEffect({ radius: radius, saturation: 1.2, brightness: 1.0, color: color });
  }
}

export class GlassRowModifier implements AttributeModifier<RowAttribute> {
  private color: string;
  private radius: number;
  constructor(color: string, radius: number = 30) {
    this.color = color;
    this.radius = radius;
  }
  applyNormalAttribute(instance: RowAttribute): void {
    applyGlass(instance, this.color, this.radius);
  }
}

export class GlassColumnModifier implements AttributeModifier<ColumnAttribute> {
  private color: string;
  private radius: number;
  constructor(color: string, radius: number = 22) {
    this.color = color;
    this.radius = radius;
  }
  applyNormalAttribute(instance: ColumnAttribute): void {
    applyGlass(instance, this.color, this.radius);
  }
}

export class GlassStackModifier implements AttributeModifier<StackAttribute> {
  private color: string;
  private radius: number;
  constructor(color: string, radius: number = 28) {
    this.color = color;
    this.radius = radius;
  }
  applyNormalAttribute(instance: StackAttribute): void {
    applyGlass(instance, this.color, this.radius);
  }
}
export interface ThemeColors {
  isDark: boolean;
  // 主背景 135° 三段渐变（对齐 bg_main_gradient.xml）
  bgStart: string;
  bgCenter: string;
  bgEnd: string;
  // 文字 / 描边
  onSurface: string;
  onSurfaceVariant: string;
  outline: string;
  primary: string;
  onPrimary: string;
  // 玻璃
  glassCard: string;
  glassStroke: string;
  glassToolbar: string;
  glassMenu: string;
  glassBar: string;   // 顶/底悬浮栏：极低 alpha，真正透出背后滚动内容（沉浸光感）；glassToolbar 过实会挡住背后
  // 其他
  white: string;
  danger: string;
  mask: string;
  menuMask: string;
  divider: string;
  cancelBtn: string;      // 取消按钮底
  tabActive: string;      // 底部 tab 选中底色
  inputBg: string;        // 输入框底
}

/** 浅色（values/colors.xml + drawable/bg_main_gradient.xml） */
const LIGHT: ThemeColors = {
  isDark: false,
  bgStart: '#DCE9FF',
  bgCenter: '#F3E8FF',
  bgEnd: '#FFE9F3',
  onSurface: '#1A1C1E',
  onSurfaceVariant: '#44474F',
  outline: '#74777F',
  primary: '#1565C0',
  onPrimary: '#FFFFFF',
  glassCard: '#E8FFFFFF',
  glassStroke: '#1A1565C0',
  glassToolbar: '#BFFBF8FF',
  glassMenu: '#CCF7F4FF',
  glassBar: '#14FFFFFF',
  white: '#FFFFFF',
  danger: '#E53935',
  mask: 'rgba(0,0,0,0.35)',
  menuMask: 'rgba(0,0,0,0.08)',
  divider: '#1A1565C0',
  cancelBtn: '#E7EAEE',
  tabActive: '#1F1565C0',
  inputBg: '#0F000000'
};

/** 深色（values-night/colors.xml + drawable-night/bg_main_gradient.xml） */
const DARK: ThemeColors = {
  isDark: true,
  bgStart: '#1A2333',
  bgCenter: '#1E1B2E',
  bgEnd: '#2A1B26',
  onSurface: '#E6E0E9',
  onSurfaceVariant: '#CAC4D0',
  outline: '#938F99',
  primary: '#1565C0',
  onPrimary: '#FFFFFF',
  glassCard: '#33000000',
  glassStroke: '#26FFFFFF',
  glassToolbar: '#66141218',
  glassMenu: '#8A141218',
  glassBar: '#33141218',
  white: '#FFFFFF',
  danger: '#E53935',
  mask: 'rgba(0,0,0,0.55)',
  menuMask: 'rgba(0,0,0,0.30)',
  divider: '#26FFFFFF',
  cancelBtn: '#49454F',
  tabActive: '#26FFFFFF',
  inputBg: '#1FFFFFFF'
};

export function getTheme(isDark: boolean): ThemeColors {
  return isDark ? DARK : LIGHT;
}

/** AppStorage 全局键名 */
export const KEY_IS_DARK: string = 'isDark';
