# 时间戳记录器 · 鸿蒙版

![Platform](https://img.shields.io/badge/Platform-HarmonyOS%20NEXT-0052D9)
![API](https://img.shields.io/badge/API-22%2B-007ACC)
![Language](https://img.shields.io/badge/ArkTS-Declarative-8114E5)
![Status](https://img.shields.io/badge/Status-Feature%20Complete-success)
![Offline](https://img.shields.io/badge/Network-None%20Required-lightgrey)

> **把「某件事发生了几次、最后一次是什么时候」记下来 —— 桌面点一下就记录，不用打开 App。**
>
> Android 版 [TimestampRecorder](https://github.com/baoru0908/timestamp-recorder) 的纯血鸿蒙原生实现，与 Android 版功能对齐、备份文件互通。

---

## ✨ 特性

| | 特性 | 说明 |
|---|---|---|
| 📝 | **双页浏览** | 「事件」页管理事件，「时间线」页按月份倒序回看全部记录 |
| ⚡ | **一键记录** | 主页事件卡胶囊按钮、详情页大按钮、**桌面卡片直接点** —— 三种方式都不用进二级页 |
| 🃏 | **桌面服务卡片** | 三套卡片（见下），点一下即记录，实时回刷 |
| 📊 | **统计** | 各事件记录数柱状图 + 近 14 天趋势图（Canvas 绘制） |
| 🔀 | **排序** | 手动拖拽排序 / 按最近记录自动排序 |
| 🌗 | **深浅色** | 跟随系统，玻璃质感顶栏与卡片 |
| 💾 | **备份** | JSON 导出 / 导入，**与 Android 版文件互通** |
| 🔒 | **纯离线** | 数据只存本地，无网络请求、无账号、无统计 |

---

## 🃏 桌面卡片（招牌功能）

添加到桌面后**不打开 App 就能记一笔**：

| 卡片 | 尺寸 | 说明 |
|---|---|---|
| **全部事件** | 2×2 / 4×4 | 列出所有事件，点某一行即给该事件记一次 |
| **单事件** | 1×2 / 2×2 / 4×4 | 绑定一个事件，整卡点击即记录，显示最近时间与累计次数 |
| **胶囊** | 1×2 | 横向胶囊，显示事件名 + 「+ 记录」 |

添加方式：桌面双指捏合 → 服务卡片 → 找到本应用 → 选卡片添加；单事件 / 胶囊卡片长按「编辑」可绑定具体事件（也可在 App 内「设置 → 管理桌面卡片」）。

---

## 📖 使用教程

<a id="tutorial"></a>

1. **新建事件** —— 点底部正中间的圆形「＋」，输入名字（如「喝水」「吃药」）、选个颜色，保存。
2. **记一条** —— 点事件卡片最右边的彩色按钮，立刻写入当前时间（毫秒级），不用进详情页。
3. **看记录** —— 左右滑动（或拖动底部胶囊岛）切到「时间线」，所有记录按事件颜色串成一条线；右上角「⋮」里还有统计图表。
4. **改与删** —— 时间线 / 卡片上长按即可重命名、换色或删除。
5. **备份** —— 设置 → 备份与恢复，导出 JSON（与 Android 版格式完全一致，可互相导入）。

**把记录按钮放到桌面上**（核心特色，不用打开 App 就能记）：

- 方式一 · 一键添加：设置 → 桌面卡片 →「管理桌面卡片」，按引导添加。（部分桌面不支持该接口，没反应就换方式二）
- 方式二 · 手动添加：桌面双指捏合 / 长按空白处 →「服务卡片」→ 找到「时间戳记录器」→ 按住想要的卡片拖到桌面。

三种卡片形态：**全部事件**（列表按钮，点哪行记哪个）、**单事件**（大按钮，可拉伸换版式）、**胶囊**（横条，省地方）。

> 完整图文说明在 App 内「设置 → 使用教程」里，离线可读，无网时以 App 内置版本为准。

---

## 🚀 快速开始

### 环境要求

- **DevEco Studio**（含 HarmonyOS SDK，工程钉 API 22 / `6.0.2(22)`）
- HarmonyOS NEXT 真机，或 DevEco 自带模拟器
- 真机调试需华为开发者账号自动签名

### 构建与安装

```bash
# 编译 + 签名，产物：entry/build/default/outputs/default/entry-default-signed.hap
devecocli build

# 一键构建并部署到所有已连接设备
bash tools/deploy_all.sh
```

或用 DevEco Studio 直接打开工程，点 Run 安装到设备 / 模拟器。

> ⚠️ 构建前请**关闭终端代理**：依赖源 ohpm 为国内域名，挂代理会导致 `ECONNREFUSED`。

---

## 🛠 技术栈

- **ArkTS / ArkUI 声明式** · Stage 模型
- **`@kit.ArkData` Preferences** —— 本地键值存储（无数据库、无网络）
- **FormKit 服务卡片** —— `postCardAction` 实现卡片内点击即记录
- **`CanvasRenderingContext2D`** —— 统计图表自绘
- **`backgroundEffect`** —— 顶栏 / 卡片高斯模糊玻璃质感

---

## 📥 下载

前往 [Releases](https://github.com/baoru0908/timestamp-recorder-harmony/releases) 获取各版本发布说明。

| 版本 | 内容 |
|---|---|
| **v1.1.0** | 液态玻璃底栏（沉浸光感）+ 可拖动滑块联动切页；顶栏渐变模糊（对齐系统设置页）；时间轴跟随页面滑动；工具链升级 HarmonyOS 26 / API 26 |
| **v1.0.0** | 首个公开版本：事件管理 / 时间线彩虹轴 / 三套桌面卡片 / 统计图表 / 备份互通 |

> **版本号规则（语义化）**：`versionName = major.minor.patch`；
> `versionCode = major×1,000,000 + minor×1,000 + patch`（如 1.0.0 → 1000000）。
>
> 当前为源码发布：HAP 需按「快速开始」自行构建签名（签名与开发者账号绑定，不随 Release 附包）。

---

## 🔗 与 Android 版的关系

| 项 | 约定 |
|---|---|
| 包名 | `com.timestamp.recorder`（两端一致） |
| 备份 JSON | **格式完全一致**，两边导出的文件可互相导入（`app: "timestamp-recorder"`, `format: 1`） |
| 存储键名 | 沿用 `tsr_data` / `events` / `records_<id>`，语义一致 |
| 颜色存储 | 有符号 int（读取时做无符号转换，两端一致） |

> ⚠️ 两端**应用数据不互通**（沙箱隔离），跨设备迁移请使用**备份 JSON 导入导出**。
>
> 设计取向：这是**移植而非复刻** —— 功能特性对齐，但 UI 遵循 HarmonyOS Design 与服务卡片规范，不追求与 Android 像素级一致。

---

## 📁 工程结构

```
entry/src/main/ets/
├─ data/          EventRepository —— Preferences 数据层（事件 / 记录 CRUD）
├─ model/         TimestampEvent（事件 / 记录模型）、CardData（卡片载荷）
├─ util/          Theme（深浅色令牌）、TimeFormat（时间格式）、FormSync（卡片回刷）
├─ pages/         Index（主页双页）、EventDetail、Stats、Settings、Tutorial、FormConfig
├─ widget/pages/  AllEventsCard、SingleEventCard、CapsuleCard
├─ formability/   FormAbility —— 卡片生命周期与 message 事件
└─ entryability/  EntryAbility、FormConfigAbility

docs/             移植规格 / 可行性评估 / Android UI 参考
tools/            deploy_all.sh（一键多设备部署）
```

---

## 📚 文档

- [`docs/port-spec.md`](docs/port-spec.md) —— 移植规格（数据结构 / 存储 / 备份格式 / 色板）
- [`docs/harmonyos-port-assessment.md`](docs/harmonyos-port-assessment.md) —— 可行性评估与 API 映射
- [`docs/android-ui-reference.md`](docs/android-ui-reference.md) —— Android 原版 UI 采集（作为参考）

---

## 👤 关于

独立开发者个人项目 · 灵感来自日常记录需求。
Android 版：[baoru0908/timestamp-recorder](https://github.com/baoru0908/timestamp-recorder)
