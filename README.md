<div align="center">

# 时间戳记录器

**桌面点一下就记一笔 —— 完全离线的轻量时间戳记录工具**

HarmonyOS NEXT 原生应用 · ArkTS / ArkUI 声明式 · 与 Android 版备份互通

![Platform](https://img.shields.io/badge/Platform-HarmonyOS_NEXT-0052D9?style=flat-square)
![API](https://img.shields.io/badge/API-22%2B-007ACC?style=flat-square)
![Language](https://img.shields.io/badge/Language-ArkTS-8114E5?style=flat-square)
![Permissions](https://img.shields.io/badge/Permissions-None-success?style=flat-square)
![Size](https://img.shields.io/badge/HAP-%3C1_MB-lightgrey?style=flat-square)
![Release](https://img.shields.io/github/v/release/baoru0908/timestamp-recorder-harmony?style=flat-square&color=success&label=release)

<img src="docs/screenshots/events.jpg" width="21%" alt="事件页" />
<img src="docs/screenshots/timeline.jpg" width="21%" alt="时间线" />
<img src="docs/screenshots/stats.jpg" width="21%" alt="统计" />
<img src="docs/screenshots/tutorial.jpg" width="21%" alt="教程" />

<sub>事件 · 时间线 · 统计 · 教程（HarmonyOS 模拟器实拍）</sub>

</div>

---

## ✨ 特性

| | 特性 | 说明 |
|---|---|---|
| 📝 | **双页浏览** | 「事件」页管理事件，「时间线」页按月倒序回看全部记录，底部胶囊岛左右切换 |
| 👆 | **可拖动滑块** | 底栏滑块 1:1 跟手，页面位移与滑块共用同一进度；松手按过半吸附切页 |
| ⚡ | **一键记录** | 主页卡片胶囊按钮、详情页大按钮、**桌面卡片直接点** —— 三种方式都不进二级页 |
| 🃏 | **桌面服务卡片** | 三套形态（见下），点一下即记录，实时回刷 |
| 📊 | **统计** | 概览 + 各事件记录数柱状图 + 近 14 天趋势（Canvas 自绘，零依赖） |
| 🔀 | **排序** | 手动拖拽排序 / 按最近记录自动排序 |
| 🌗 | **深浅色** | 跟随系统；顶栏渐变模糊、底栏液态玻璃 |
| 🔒 | **零权限 · 完全离线** | 不申请任何权限，不发起任何网络请求；数据只写本机 Preferences |
| 💾 | **备份互通** | JSON 导出 / 导入，**与 Android 版文件互相可用** |

---

## 🃏 桌面卡片（招牌功能）

添加到桌面后**不打开 App 就能记一笔**：

| 卡片 | 支持尺寸 | 说明 |
|---|---|---|
| **全部事件** | 2×2 · 4×4 | 列出所有事件，点某一行即给该事件记一次 |
| **单事件** | 1×2 · 2×2 · 4×4 | 绑定一个事件，整卡点击即记录，显示最近时间与累计次数 |
| **胶囊** | 1×2 | 横向胶囊，显示事件名 + 「+ 记录」 |

添加方式：桌面双指捏合 / 长按空白处 →「服务卡片」→ 找到本应用 → 拖到桌面；
「单事件 / 胶囊」添加后长按可「编辑」绑定具体事件（也可在 App 内「设置 → 管理桌面卡片」一键添加）。

---

## 🚀 快速开始

### 环境要求

| 项 | 要求 |
|---|---|
| IDE | **DevEco Studio**（自带 HarmonyOS SDK） |
| SDK | 工程 `targetSdkVersion` = `26.0.0`，`compatibleSdkVersion` = `6.0.2(22)`；`compileSdkVersion` 不显式配置（用 IDE 内置 SDK） |
| 设备 | HarmonyOS **6.0.2（API 22）及以上**；「沉浸光感」液态玻璃底栏需系统支持该特性（API 26 起） |
| 签名 | 真机调试需**华为开发者账号**（DevEco 的「自动签名」即可） |

### 用 DevEco Studio 构建（推荐）

打开工程 → `File → Project Structure → Signing Configs` 勾选 **Automatically generate signature** → 点 **Run** 安装到设备或模拟器。

### 用命令行构建（hvigor 随 DevEco 一起安装）

```bash
# 0) 指向 DevEco Studio 安装目录（下例为 Windows 默认位置，按实际调整）
DEVECO="D:/Program Files/Huawei/DevEco Studio"
export DEVECO_SDK_HOME="$DEVECO/sdk"

# 1) 构建（产物：entry/build/default/outputs/default/entry-default-signed.hap）
"$DEVECO/tools/hvigor/bin/hvigorw" assembleHap --no-daemon

# 2) 安装到已连接设备（hdc 在 SDK 内）
"$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc" install -r \
  entry/build/default/outputs/default/entry-default-signed.hap
```

> ℹ️ `hvigorw` 需要 Node.js 运行时；DevEco Studio 自带一份（`<DevEco>/tools/node`），加入 `PATH` 即可。
>
> ⚠️ 构建前请**关闭终端代理**：依赖源 ohpm 为国内域名，挂代理会导致 `ECONNREFUSED`。
>
> `tools/deploy_all.sh` 可一键构建并部署到所有已连接设备（脚本内含多设备遍历）。

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

> 完整图文说明在 App 内「设置 → 使用教程」里，**离线可读**。

---

## 📥 版本与下载

前往 [Releases](https://github.com/baoru0908/timestamp-recorder-harmony/releases) 查看各版本发布说明。

| 版本 | 内容 |
|---|---|
| **v1.1.1** | 修正关于页文案（原先声称内嵌 MiSans，实际使用系统字体）与主页空态引导方位；移除未使用的网络权限，**现在真正零权限** |
| **v1.1.0** | 液态玻璃底栏（沉浸光感）+ 可拖动滑块联动切页；顶栏渐变模糊（对齐系统设置页）；时间轴跟随页面滑动；工具链升级 HarmonyOS 26 / API 26 |
| **v1.0.0** | 首个公开版本：事件管理 / 时间线彩虹轴 / 三套桌面卡片 / 统计图表 / 备份互通 |

> **版本号规则（语义化）**：`versionName = major.minor.patch`；
> `versionCode = major×1,000,000 + minor×1,000 + patch`（如 1.1.0 → 1001000）。
>
> 本仓库为**源码发布**：签名与开发者账号绑定，不便随 Release 分发 HAP，请按「快速开始」自行构建安装。

---

## 🔗 与 Android 版的关系

本工程是 Android 版 [TimestampRecorder](https://github.com/baoru0908/timestamp-recorder) 的**纯血鸿蒙原生实现（移植而非复刻）** —— 功能特性对齐、数据格式互通，UI 遵循 HarmonyOS Design 与服务卡片规范。

| 项 | 约定 |
|---|---|
| 包名 | `com.timestamp.recorder`（两端一致） |
| 备份 JSON | **格式完全一致**：`app: "timestamp-recorder"`、`format: 1`，两边导出的文件可互相导入 |
| 存储键名 | Preferences `tsr_data` → `events`（顺序即手动排序）/ `records_<eventId>`（最新在前） |
| 颜色存储 | 有符号 int（读取时做无符号转换，两端一致） |

> ⚠️ 两端**应用数据不互通**（沙箱隔离），跨设备迁移请使用**备份 JSON 导入导出**。

---

## 🛠 技术栈

- **ArkTS / ArkUI 声明式** · Stage 模型，单 HAP 体积 < 1 MB
- **`@kit.ArkData` Preferences** —— 本地键值存储（无数据库、无网络）
- **FormKit 服务卡片** —— `postCardAction` 实现卡片内点击即记录
- **`CanvasRenderingContext2D`** —— 统计图表自绘
- **`uiMaterial.systemMaterial`** —— 底栏「沉浸光感」液态玻璃（HarmonyOS 6/7 高级材质，API 26）
- **`linearGradientBlur` + `backgroundEffect`** —— 顶栏渐变模糊（内容进标题区渐进糊化、向下收束，无硬切）
- **`Swiper.startFakeDrag / fakeDragBy`** —— 底栏滑块与页面位移共用同一进度，1:1 跟手
- 图标全部自绘矢量、零第三方依赖

---

## 📁 工程结构

```
entry/src/main/ets/
├─ data/                EventRepository —— Preferences 数据层（事件 / 记录 CRUD、备份导入导出）
├─ model/               TimestampEvent（事件 / 记录模型）、CardData（卡片载荷）
├─ util/                Theme（深浅色令牌 + 玻璃材质）、TimeFormat（时间格式化）、FormSync（卡片回刷）
├─ pages/               Index（主页双页 + 底栏胶囊岛）、EventDetail、Stats、Settings、Tutorial、About、FormConfig
├─ widget/pages/        AllEventsCard、SingleEventCard、CapsuleCard（三套服务卡片）
├─ formability/         FormAbility —— 卡片生命周期与 message 事件
├─ entryability/        EntryAbility、FormConfigAbility
└─ entrybackupability/  EntryBackupAbility —— 系统备份扩展

docs/                   移植规格 / 可行性评估 / Android UI 参考 / screenshots（README 用图）
tools/                  deploy_all.sh（一键多设备构建部署）
```

---

## 📚 文档

- [`docs/port-spec.md`](docs/port-spec.md) —— 移植规格（数据结构 / 存储 / 备份格式 / 色板）
- [`docs/harmonyos-port-assessment.md`](docs/harmonyos-port-assessment.md) —— 可行性评估与 API 映射
- [`docs/android-ui-reference.md`](docs/android-ui-reference.md) —— Android 原版 UI 采集（作为参考）

---

<div align="center">
<sub>© 2026 baoru0908 · 独立开发者个人项目 · 灵感来自日常记录需求</sub><br/>
<sub>Android 版：<a href="https://github.com/baoru0908/timestamp-recorder">baoru0908/timestamp-recorder</a></sub>
</div>
