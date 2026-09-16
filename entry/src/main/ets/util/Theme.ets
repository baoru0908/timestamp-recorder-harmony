/**
 * 语义化设计令牌（对齐 Android 原项目 values/colors.xml + values-night/colors.xml）。
 * 全部用 string 而不是 $r 资源：事件色等需要动态拼接透明度（`${hex}99`），string 更顺手。
 * 深浅两套由 getTheme(isDark) 切换；isDark 由 AppStorage('isDark') 全局驱动，跟随系统。
 */
import uiMaterial from '@ohos.arkui.uiMaterial';

/**
 * 液态玻璃统一封装（API 26 ImmersiveMaterial）。
 *
 * 跟随系统「沉浸光感」风格的三个前提（缺一不可）：
 *  1) 设备/系统需支持 API 26 沉浸光感：工程 targetSdkVersion=26.0.0（满足 ImmersiveMaterial 运行前提），
 *     compatibleSdkVersion=6.0.2(22) 仅规定最低可安装版本；API 22~25 设备上 isImmersiveMaterialSupported()
 *     返回 false，自动走下方「实时高斯模糊降级」分支，功能与观感降级但不崩溃。
 *  2) entry/module.json5 声明 metadata [{ name:"ohos.arkui.UIMaterial.state", value:"enable" }]
 *     → 应用 MaterialState 置为 ENABLE，系统材质样式优先级高于组件自身 background/blur → 真正跟随系统光感。
 *  3) 组件必须位于「沉浸光感生效范围」内：Navigation/NavDestination 标题栏，
 *     或横向 Tabs 中 barPosition=BarPosition.End 的底部 TabBar。
 *     ⚠️ 这是最容易踩的坑：范围外的组件系统直接判
 *     "Material inactive: out of scope. Use component in navigation title bar or Tabbar."
 *     → 材质完全不生效、组件背景变全透明（旧版曾误判为「模拟器不支持 systemMaterial」）。
 *     底部胶囊岛已因此改造为 Tabs 的 tabBar（见 pages/Index.ets）。
 *
 * applyGlass 行为：
 *  - getMaterialInfo().state===ENABLE 且 isImmersiveMaterialSupported() 时 → 纯 systemMaterial + lightEffect:{color:undefined} 跟随系统。
 *    另叠一层极低 alpha 的 backgroundColor 兜底：系统材质生效时会被其覆盖（看不出来），
 *    万一材质未生效（如组件又跑出生效范围）也有底色，不会变成「整片透明」。
 *  - 其余（设备系统版本不足 / metadata 未生效）→ 仅 backgroundEffect 实时高斯模糊降级。
 */
type AnyGlassAttr = RowAttribute | ColumnAttribute | StackAttribute;

// 模块级缓存：应用生命周期内设备沉浸光感能力不变，只需探测一次，避免每个玻璃组件重复查询 + 刷日志。
let materialSupportedCache: boolean | null = null;

/** 探测当前设备是否真正支持「系统沉浸光感」（API 26 设备 + MaterialState=ENABLE）。结果缓存复用。 */
function isImmersiveSupported(): boolean {
  if (materialSupportedCache !== null) {
    return materialSupportedCache;
  }
  let ok: boolean = false;
  try {
    const supported: boolean = uiMaterial.isImmersiveMaterialSupported();
    const state: number = uiMaterial.getMaterialInfo().state;
    ok = supported && state === uiMaterial.MaterialState.ENABLE;
  } catch (e) {
    ok = false;
  }
  materialSupportedCache = ok;
  // 仅首次探测打一条日志（release 下也仅此一条，用于确认是否 out of scope），不再逐组件刷屏。
  console.info(`[Glass] immersiveMaterial supported=${ok}`);
  return ok;
}

function applyGlass(attr: AnyGlassAttr, color: string, radius: number, inScope: boolean): void {
  // 三条件：①组件在生效范围（Navigation 标题栏 / 底部 TabBar）②设备/系统支持 ③应用 MaterialState=ENABLE。
  // inScope 由调用方声明：范围外的组件若强行调 systemMaterial，系统判 out of scope → 材质不生效且背景全透。
  const useSystem: boolean = inScope && isImmersiveSupported();
  // 兜底底色：系统材质生效时被覆盖；未生效（降级分支）时也有底，不至于整片透明。
  attr.backgroundColor(color);
  if (useSystem) {
    // 跟随系统沉浸光感：systemMaterial；lightEffect 显式置 undefined 表示光感跟随系统、不写死颜色。
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
    applyGlass(instance, this.color, this.radius, false);
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
    applyGlass(instance, this.color, this.radius, false);
  }
}

/** inScope=true 仅限「底部 TabBar / Navigation 标题栏」内的组件（当前：底部胶囊岛挂在 Tabs.tabBar 上） */
export class GlassStackModifier implements AttributeModifier<StackAttribute> {
  private color: string;
  private radius: number;
  private inScope: boolean;
  constructor(color: string, radius: number = 28, inScope: boolean = false) {
    this.color = color;
    this.radius = radius;
    this.inScope = inScope;
  }
  applyNormalAttribute(instance: StackAttribute): void {
    applyGlass(instance, this.color, this.radius, this.inScope);
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

/**
 * 「纯模糊、不加 tint」的材质色（透明）。
 * 依据：实测鸿蒙第一方设置页顶栏底色与页面背景**完全一致**（标题区/下方/卡片缝隙多点采样均 #EFF3F6）
 *       —— 它只对背后的内容做模糊，不额外叠任何色。顶栏用它即可得到同样的「栏底=页面背景」观感。
 * 注意：悬浮胶囊岛**不能**用它（岛下面就是滚动内容，没有 tint 会失去「实体面板」感），仍用 glassBar。
 */
export const GLASS_BLUR_ONLY: string = '#00000000';

/** AppStorage 全局键名 */
export const KEY_IS_DARK: string = 'isDark';
