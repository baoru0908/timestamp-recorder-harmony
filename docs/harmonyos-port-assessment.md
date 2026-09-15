# 时间戳记录器 → 纯血鸿蒙（HarmonyOS NEXT / 7）移植可行性评估

> 评估日期：2026-09-15　评估对象：v4.1.0（versionCode 30）
> 目标平台：**纯血鸿蒙**（HarmonyOS NEXT / HarmonyOS 7，仅支持 HAP，不含 AOSP 兼容层）
> 前提约定：**不强求液态玻璃，接受系统高斯模糊**；验证设备为纯血鸿蒙平板

---

## 一、结论

**可行，但性质是「重写客户端」，不是「移植」。**

| 项目 | 结论 |
|:---|:---|
| 技术可行性 | ✅ 全部核心功能都有鸿蒙对应能力，无「做不了」的功能 |
| 代码复用率 | ⚠️ 低——UI 层（约 6000 行含布局）需重写，可复用的是数据模型、算法与设计规范 |
| 核心特色（桌面点一下即记） | ✅ 可保留，FormKit 服务卡片机制甚至比 Android 更干净 |
| 招牌视觉（液态玻璃） | ⚠️ 降级为系统高斯模糊（原生支持，观感依然成立） |
| 主要成本 | 学习 ArkTS/ArkUI/Stage 模型/FormKit + 全量重写界面 |
| 主要风险 | 无 Material 组件库需自建样式；无动态取色；平板大屏布局需重新设计 |

**一句话**：这不是「把 APK 搬过去」，而是「照着重写一个鸿蒙 App」——**但每一个功能都落得下地**，包括我们最看重的「桌面点一下直接记录」。

---

## 二、项目现状盘点（移植评估的基线数据）

| 项 | 数值 |
|:---|:---|
| Kotlin 源文件 | 20 个 / 3,298 行 |
| Java 源文件（液态玻璃源码集成） | 7 个 / 1,369 行 |
| 布局 XML | 24 个 / 2,791 行 |
| 资源 XML（含 values / drawable / xml） | 72 个 / 3,606 行 |
| 平台 API 引用 | **146 处 / 60 个类** |
| 第三方依赖 | 0（自绘图表、自写数据层） |
| 声明的权限 | 0（无 INTERNET） |

> 「零第三方依赖、零权限」这两条在鸿蒙上同样是优势：没有 SDK 适配问题，也不需要权限迁移。

---

## 三、能力映射总表

### 3.1 UI 框架（工作量最大的一块）

| 我们的实现 | 鸿蒙对应 | 迁移性质 |
|:---|:---|:---|
| `AppCompatActivity` / `BaseActivity` | `UIAbility`（生命周期：onCreate → onWindowStageCreate → onForeground → onBackground → onDestroy）+ `@Entry @Component` 页面 | 重写 |
| Activity 间跳转 `Intent` + `finish()` | `router.pushUrl` / `NavPathStack` + `router.back()` | 替换 |
| XML 布局（Column/Row 线性布局） | ArkUI 声明式容器 `Column` / `Row` / `Stack` / `Flex` | 重写 |
| `MaterialToolbar` | `Navigation` 标题栏 / 自建顶部栏组件 | 自建 |
| `MaterialCardView` / `MaterialButton` | ArkUI `Column` + `.borderRadius()` / `.shadow()` / `.backgroundColor()`（无 Material 库，需自建视觉规范） | 自建 |
| `RecyclerView` + Adapter | `List` + `ForEach` / `LazyForEach`（**必须提供 key**） | 重写 |
| `LinearLayoutManager` / `GridLayoutManager` | `List` / `Grid` / `WaterFlow` + `lanes()` | 重写 |
| **`ItemTouchHelper`（拖拽排序）** | **`List.onItemDragStart` / `onItemDrop` / `onItemMove`**（官方 FAQ 有完整的数组交换示例） | 重写但更简单 |
| **`ViewPager2`（跟手切页）** | **`Swiper`**（支持控制器、跟手、自定义切换曲线） | 替换 |
| `LayoutInflater` | `@Builder` 构建器 / 自定义组件 | 重写 |
| `ViewBinding` | 直接引用组件 + `$r()` 资源引用 | 替换 |
| 自定义 View（`AttributeSet` / `onDraw` / `onTouchEvent`） | `@Component` + `Canvas` 组件 + 手势系统（`onTouch` / `Gesture`） | 重写 |
| `Toast` | `promptAction.showToast` | 替换 |
| `Snackbar` | 无直接对应（用 `promptAction` 或自建） | 自建 |
| `AlertDialog` / `MaterialAlertDialogBuilder` | `promptAction.showDialog` / `CustomDialog` / `bindSheet` | 替换 |
| `DecelerateInterpolator`（动效曲线） | `curves` 模块（`springCurve` / `bezierCurve` / `interpolatingSpring`） | 替换 |
| `CoordinatorLayout` | `Stack` / `RelativeContainer` | 重写 |

### 3.2 数据存储与文件

| 我们的实现 | 鸿蒙对应 | 迁移性质 |
|:---|:---|:---|
| `SharedPreferences`（`EventRepository` 的全部存储） | `@ohos.data.preferences`（`getPreferencesSync` / `put` / `get` / `flush`） | 换 API，**数据结构不变** |
| `org.json`（事件与记录的序列化） | ArkTS 内建 `JSON.parse` / `JSON.stringify` | 可直接复用格式 |
| 备份文件（JSON 导出 / 覆盖恢复） | `@ohos.file.fs` 读写 | **备份文件格式可完全复用** |
| `ActivityResultContracts`（系统文件选择器） | `@ohos.file.picker` 的 `DocumentViewPicker`（`save` / `select`） | 替换 |
| `Uri` / `ContentResolver` | `fileUri` / `fs.open` | 替换 |
| `Context` | `UIAbilityContext` / `getContext(this)` | 替换 |

### 3.3 系统能力与适配

| 我们的实现 | 鸿蒙对应 | 迁移性质 |
|:---|:---|:---|
| `Intent` / `Bundle` / `ComponentName` | `Want` + `startAbility` | 替换 |
| `PendingIntent`（小组件点击） | `wantAgent` + `postCardAction` | 替换 |
| **`ClipboardManager` / `ClipData`（点行复制时间）** | **`@ohos.pasteboard`**（`pasteboard.createData` + `systemPasteboard.setData`） | 替换 |
| **`Typeface` / `Font` / `FontFamily` / `AssetManager`（MiSans 字体）** | **`font.registerFont()`**（字体文件放 `resources/rawfile`）+ `.fontFamily($rawfile('MiSans.ttf'))` | 替换，**字体文件可复用** |
| `Build`（SDK 版本判断） | `deviceInfo.sdkApiVersion` / `canIUse()` | 替换 |
| `Configuration`（深浅色适配） | `Configuration.colorMode` + `onConfigurationUpdate` | 替换 |
| `DynamicColors`（Material 3 动态取色） | ⚠️ **无对应**——鸿蒙未开放壁纸取色；需自建配色（可用系统主题色或固定方案） | 自建 |
| `WindowCompat` / `WindowInsetsCompat` / `enableEdgeToEdge` / `SystemBarStyle` / `updatePadding` / `ViewCompat`（沉浸式 + 状态栏避让） | `window` 模块（`setWindowLayoutFullScreen`）+ `expandSafeArea()` + `getWindowAvoidArea()` 避让区 | 重写 |
| `ViewTreeObserver`（布局完成回调） | `onAreaChange` / `onSizeChange` | 替换 |

### 3.4 自绘图形（图表与时间线）

| 我们的实现 | 鸿蒙对应 | 迁移性质 |
|:---|:---|:---|
| `BarChartView`（统计柱状图，Canvas 自绘） | `Canvas` 组件 + `CanvasRenderingContext2D` | 思路可复用，API 重写 |
| `TabSliderView`（胶囊滑块，自绘 + 阴影） | 同上（`shadowBlur` / `shadowColor` / `roundRect` 均支持） | 同上 |
| `TimelineLine`（渐变彩线，`LinearGradient` + `Shader`） | 同上（`createLinearGradient` + `addColorStop` 完全对应） | 同上 |
| `Paint` / `RectF` / `Color` / `GradientDrawable` | `CanvasRenderingContext2D` 属性 + 组件的 `.linearGradient()` / `.borderRadius()` | 替换 |

> **补充**：ArkUI 的 Canvas 还支持离屏绘制（`OffscreenCanvas`）与在 **ArkTS 卡片内绘制**（API 9+），复杂自绘不受限。

### 3.5 桌面小组件（核心特色）

| 我们的实现 | 鸿蒙对应 | 迁移性质 |
|:---|:---|:---|
| `AppWidgetProvider`（三种 Provider） | `FormExtensionAbility`（在 `module.json5` 注册，`type: "form"`） | 重写 |
| `AppWidgetManager`（更新小组件） | `formProvider.updateForm()` / `setFormNextRefreshTime()` | 替换 |
| `RemoteViews`（固定行渲染） | **ArkTS 卡片**（`@Entry @Component` + `@LocalStorageProp` 单向注入） | 重写 |
| `widget_*_info.xml`（尺寸与描述） | `form_config.json`（`supportDimensions` / `defaultDimension` / `isDynamic` / `updateEnabled`） | 重写 |
| `PendingIntent` → 点击直接记一条 | **`postCardAction` 的 `message` 事件** → 触发 `onFormEvent(formId, message)` 后台写入并回刷卡片 | 重写，**能力等价** |
| 点击后由 `AppWidgetOptions` 分档换版式（1×1~4×4） | `form_config.json` 配置多尺寸 + 卡片内按 `formInfo` 尺寸分支渲染 | 重写 |

**核心结论**：`postCardAction` 的 `message` 事件**不会拉起 App 界面**，可直接在 `FormExtensionAbility` 里写数据并更新卡片显示——**「桌面点一下直接记一条」这个招牌在纯血鸿蒙上完全成立**。

### 3.6 液态玻璃 → 高斯模糊（降级方案）

| 项 | Android 现状（v4.1.0） | 鸿蒙方案 |
|:---|:---|:---|
| 实现原理 | AGSL RuntimeShader 逐帧录制 RenderNode，物理折射 + 色散 + GPU 高斯 | ArkUI 系统材质模糊 |
| 可用 API | `LiquidGlassView`（源码集成，API 33+） | `backgroundEffect({radius, saturation, brightness, color})` / `backgroundBlurStyle(BlurStyle.Thick…)` / `backdropBlur(radius)` |
| 溢出效果 | 折射 + 色散（人无我有） | ❌ 无自定义着色器接口，**不可复刻** |
| 观感 | 玻璃质感 + 折射 | 标准高斯模糊材质（鸿蒙 7 另有系统级 `GlassComponent` / `glassBlurStyle`） |
| 附带好处 | 需自行处理浮窗夺状态栏、RenderNode 自引用崩溃等 6 个坑 | 系统渲染服务统一处理，**应用侧零开销、无上述坑** |
| 降级影响 | — | 视觉独特性下降，但「玻璃栏 + 实时模糊」的观感依然成立 |

> 结论：玻璃从「不可复刻」变为「**降级可用**」，且实现复杂度大幅下降。

---

## 四、完整 API 映射明细（60 个类）

| Android 类 | 用途 | 鸿蒙对应 | 难度 |
|:---|:---|:---|:---:|
| `Activity` / `AppCompatActivity` | 页面容器 | `UIAbility` + `@Entry` 页面 | 中 |
| `Bundle` | 参数传递 | `Want.parameters` / 直接传参 | 低 |
| `Intent` | 页面跳转 | `Want` + `router.pushUrl` | 低 |
| `Context` | 上下文 | `UIAbilityContext` / `getContext(this)` | 低 |
| `ComponentName` | 组件定位 | `Want.bundleName/abilityName` | 低 |
| `Uri` | 资源定位 | `fileUri` / 字符串路径 | 低 |
| `View` / `ViewGroup` | 视图基类 | ArkUI 组件（无 View 体系） | 高 |
| `LayoutInflater` | 布局加载 | `@Builder` / 自定义组件 | 中 |
| `AttributeSet` | 自定义 View 参数 | 自定义组件 `@Prop` 参数 | 中 |
| `RecyclerView` | 列表 | `List` + `LazyForEach` | 中 |
| `LinearLayoutManager` | 线性布局 | `List` 默认 | 低 |
| `GridLayoutManager` | 网格布局 | `Grid` / `List.lanes()` | 低 |
| `ItemTouchHelper` | 拖拽排序 | `List.onItemDragStart/onItemDrop` | 中 |
| `ViewPager2` | 跟手切页 | `Swiper` | 低 |
| `MotionEvent` | 触摸事件 | `onTouch` / `Gesture` | 中 |
| `ViewTreeObserver` | 布局回调 | `onAreaChange` / `onSizeChange` | 低 |
| `ViewCompat` / `WindowCompat` | 兼容工具 | 无（鸿蒙无兼容层需求） | 低 |
| `WindowInsetsCompat` | 系统栏避让 | `expandSafeArea()` / `getWindowAvoidArea()` | 中 |
| `SystemBarStyle` / `enableEdgeToEdge` / `updatePadding` | 沉浸式 | `window.setWindowLayoutFullScreen` + 安全区 | 中 |
| `Configuration` | 深浅色/配置 | `Configuration.colorMode` | 低 |
| `Toast` | 轻提示 | `promptAction.showToast` | 低 |
| `Snackbar` | 底部提示 | 自建 / `promptAction` | 中 |
| `AlertDialog` / `MaterialAlertDialogBuilder` | 弹窗 | `promptAction.showDialog` / `CustomDialog` | 低 |
| `Menu` / `MenuItem` | 菜单 | `bindMenu` / `Menu` 组件 | 中 |
| `MaterialToolbar` | 标题栏 | `Navigation` / 自建 | 中 |
| `CoordinatorLayout` | 协调布局 | `Stack` / `RelativeContainer` | 中 |
| `ImageView` | 图片 | `Image` | 低 |
| `TextView` | 文本 | `Text` | 低 |
| `Gravity` | 对齐 | `.align()` / `.justifyContent()` | 低 |
| `Bitmap` / `BitmapDrawable` | 位图 | `image.PixelMap` | 中 |
| `Color` / `ColorStateList` | 颜色 | `Color` / `.stateStyles()` | 低 |
| `GradientDrawable` | 形状背景 | `.borderRadius()` / `.linearGradient()` | 低 |
| `DecelerateInterpolator` | 动效曲线 | `curves` 模块 | 低 |
| `DynamicColors` | 动态取色 | ⚠️ 无对应，需自建 | 中 |
| `MaterialColors` | 主题取色 | `$r('sys.color.*')` 系统色 | 低 |
| `Canvas` / `Paint` / `RectF` | 自绘 | `Canvas` + `CanvasRenderingContext2D` | 中 |
| `Shader` / `LinearGradient` | 渐变 | `createLinearGradient` | 低 |
| `AssetManager` | 资源读取 | `resourceManager` / `rawfile` | 低 |
| `Typeface` / `Font` / `FontFamily` | 字体 | `font.registerFont` | 低 |
| `Build` | 版本判断 | `deviceInfo.sdkApiVersion` | 低 |
| `ClipboardManager` / `ClipData` | 剪贴板 | `@ohos.pasteboard` | 低 |
| `AppWidgetProvider` / `AppWidgetManager` / `RemoteViews` | 桌面小组件 | **FormKit**（FormExtensionAbility + ArkTS 卡片） | 高 |
| `PendingIntent` | 延迟意图 | `wantAgent` / `postCardAction` | 中 |
| `ActivityResultContracts` | 系统文件选择 | `DocumentViewPicker` | 低 |

> 另有 `SharedPreferences`（经 `Context` 调用）→ `@ohos.data.preferences`，`org.json` → 内建 `JSON`。

---

## 五、工作量估算

| 模块 | Android 现状 | 鸿蒙重写量估算 |
|:---|:---|:---|
| 页面（7 个：主页 / 详情 / 设置 / 统计 / 关于 / 教程 / 卡片配置） | Kotlin + 24 布局 XML | 约 1,600–2,200 行 ArkTS |
| 自绘组件（柱状图 / 滑块 / 时间线） | 3 个自定义 View | 约 400–600 行 |
| 数据层（仓库 / 备份 / 偏好 / 字体） | 4 个模块 | 约 400–600 行（逻辑可直接翻译） |
| 服务卡片（三种形态） | 3 个 Provider + RemoteViews | 约 500–700 行 ArkTS + 配置 |
| 工程与配置（module.json5 / 签名 / 资源） | Gradle + Manifest | 配置类工作 |
| **合计** | | **约 3,000–4,000 行 ArkTS** |

对比：现有 Android 侧 Kotlin 3,298 行 + 布局 2,791 行。**ArkUI 声明式写法更紧凑，但状态管理与卡片限制会补回来一部分**。加上学习与调试，工作量应视为「从零做一个同等复杂度的小 App」。

---

## 六、风险与限制清单

| # | 风险 | 影响 | 应对 |
|:---:|:---|:---|:---|
| 1 | 无 Material 组件库 | 卡片 / 按钮 / 圆角阴影需自建样式 | ArkUI 的 `borderRadius` / `shadow` / `backgroundColor` 足够，建立一套 `@Styles` 复用 |
| 2 | 动态取色（M3）无对应 | 配色方案要自己定 | 用系统语义色 `$r('sys.color.*')` + 固定主色 |
| 3 | 玻璃折射不可复刻 | 视觉独特性下降 | 用系统高斯模糊材质（用户已接受） |
| 4 | 卡片 UI 硬限制 | 卡片内只能 V1 状态管理、不能做派生计算、`Button` 带参构造文字不渲染（要用 `Text` 模拟） | 把派生逻辑放 `FormExtensionAbility`，卡片只做「显示收到的值」 |
| 5 | 卡片刷新频控 | 不能秒级刷新（最短 5 分钟周期） | 点击触发即时回刷（我们要的正是这个），周期刷新不依赖 |
| 6 | 平板大屏形态 | 现有竖屏手机布局不适用 | 用自适应布局（栅格 / 断点），顺便把平板体验做好 |
| 7 | 无手机端设备验证 | 只能验平板 | 可用 DevEco 模拟器补手机形态验证 |
| 8 | 学习曲线 | ArkTS / ArkUI / Stage / FormKit / hvigor 全新 | 分阶段推进，先跑通最小闭环 |
| 9 | 无自动化迁移工具 | 全靠手写 | 已在本次评估产出 API 映射表作为施工图 |

---

## 七、建议的分阶段路线

| 阶段 | 目标 | 交付物 | 验收标准 |
|:---|:---|:---|:---|
| **P0 链路验证** | 建工程 → 签名 → 装上平板 | 一个页面：事件列表 + 点一下记录 + `Preferences` 存储 | 平板能装能跑，记录不丢 |
| **P1 核心功能** | 补齐主流程 | 时间线（Canvas）+ 统计 + 拖拽排序 + 设置 + 备份导入导出 | 与 Android 版功能对齐 |
| **P2 招牌特色** | 桌面卡片 | FormKit 服务卡片（点一下即记 + 计数回刷） | 桌面上点一下，App 不打开也能记 |
| **P3 打磨** | 观感与适配 | 高斯模糊玻璃栏 + 深浅色 + 平板大屏布局 | 观感达标 |

> **建议从 P0 开始**：用最小成本把「开发 → 签名 → 装机」这条链路跑通，拿到确定性结论后再投入 P1。

---

## 八、关于「官方扫描工具」

经核查，**华为没有提供「扫描 APK 自动生成鸿蒙移植报告」的成品工具**。官方口径与可用能力如下：

| 说法 | 实际情况 |
|:---|:---|
| 「鸿蒙迁移评估工具」扫 APK 识别 90% 不兼容 API | ❌ 无官方成品；多为自媒体传抄，未在官方文档中找到对应工具 |
| DevEco Studio 可导入 Android 工程并列出不兼容项 | ⚠️ 官方文档未记载该校验流程；华为开发者论坛官方答复为「APK 不能直接转成鸿蒙原生包，需用 ArkTS/ArkUI 重建」 |
| API 变更助手（Tools > API Change Assistant） | ✅ 真实存在，但**只扫描 ArkTS 工程**的跨版本 API 行为变更，对本项目（Android 工程）不适用 |
| Android → 鸿蒙 API 映射参考 | ✅ 存在于官方文档 / 官方论坛对照表（Activity→UIAbility、XML→ArkUI、RecyclerView→List、SharedPreferences→Preferences、Intent→Want 等） |

**因此本评估采用的方法**：提取项目实际使用的 60 个 Android 类（146 处引用），逐个对照鸿蒙官方能力，形成上文第 3、4 节的映射表——**这份表就是施工图**，比任何「一键报告」更贴合本项目。

---

## 九、环境与前置条件

| 项 | 要求 | 本机状态 |
|:---|:---|:---|
| DevEco Studio | Windows 10/11 64 位 | ✅ Win11 专业版 |
| 内存 | ≥ 16GB | ✅ 31.6GB |
| 硬盘 | ≥ 100GB 可用 | ✅ C 盘 121.8GB / D 盘 98.6GB |
| 工具链 | DevEco Studio（含 SDK、hvigor、ohpm） | ❌ 未安装，需从官网获取 |
| 签名 | 华为开发者账号（实名认证，免费）+ 自动签名，或手动 p12/p7b + 设备 UDID 注册 | ❌ 待办 |
| 真机 | 纯血鸿蒙设备，开开发者模式 + USB 调试（hdc） | ✅ 纯血鸿蒙平板一台 |

**SDK 版本对应**：DevEco Studio 6.1 → API 23（HarmonyOS 6.1）；5.0.5 → API 14。
