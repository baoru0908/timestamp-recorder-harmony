# 移植规格书（Android → 纯血鸿蒙）

> 本文件是 ArkTS 实现的**施工规格**：数据结构、存储设计、备份格式、色板、格式化规则与兼容性坑。
> 与 Android 版（v4.1.0）逐条对齐，**目标是与 Android 版数据互通（备份文件可直接互相导入）**。

---

## 一、数据模型

### 1.1 事件 TimestampEvent

| 字段 | 类型 | 说明 |
|:---|:---|:---|
| `id` | number（Long） | 创建时取 `当前毫秒`，若冲突则 +1 直到唯一 |
| `name` | string | 显示名，保存时 `trim()` |
| `color` | number（Int） | ARGB 颜色值，见 §4 色板 |
| `createdAt` | number（Long） | 创建时间毫秒 |

### 1.2 时间线条目 TimelineRecord（派生结构，不落盘）

| 字段 | 说明 |
|:---|:---|
| `eventId` / `eventName` / `eventColor` | 记录所属事件（**记录时不快照，查询时从事件表关联**——Android 版实际实现为查询时组装） |
| `millis` | 该条记录的时间戳 |

> 时间线 = 全部事件的全部记录合并后按 `millis` 倒序。事件被删时其记录一并删除，无需额外过滤。

---

## 二、存储设计（必须与 Android 版结构一致）

**Android 现状**：`SharedPreferences("tsr_data")` + JSON 字符串。

| 存储键 | 内容 | 格式 |
|:---|:---|:---|
| `events` | 全部事件 | JSON 数组 `[{id,name,color,createdAt},…]`，**数组顺序 = 手动排序顺序** |
| `records_<eventId>` | 某事件的记录 | JSON 数组 `[millis,…]`，**最新在前（index 0 是最新）** |

**鸿蒙方案**：`@ohos.data.preferences`，`preferences.getPreferencesSync(context, { name: 'tsr_data' })`，键名、JSON 结构、顺序语义**全部保持一致**。

### 关键设计约定（沿用 Android 版，勿改）

1. **手动排序直接复用存储数组次序** —— 没有 `order` 字段，拖拽结束把新顺序整体回写 `events` 数组。无需数据迁移。
2. **记录最新在前** —— `addRecord` 用 `unshift`（插到 index 0），`undoLast` 删 index 0。
3. **删除事件连带删记录** —— 同时删除 `events` 里的条目与 `records_<id>` 键。
4. **所有写操作串行化**（Android 用 `@Synchronized`；鸿蒙侧注意并发调用，卡片回写与页面写入可能同时发生）。

### 数据层接口清单（ArkTS 需实现同名能力）

| 方法 | 语义 |
|:---|:---|
| `getEvents()` | 全部事件（数组顺序 = 手动顺序） |
| `getEvent(id)` | 单个事件 |
| `addEvent(name, color)` | 新建，返回新事件 |
| `updateEvent(id, name, color)` | 改名 / 改色 |
| `deleteEvent(id)` | 删事件 + 其全部记录 |
| `getEventsByRecent()` | 按最近记录时间倒序（无记录排最后） |
| `setEventsOrder(orderedIds)` | 持久化新手动顺序（防止漏项：未出现在列表里的排在末尾） |
| `getRecords(eventId)` | 记录列表（最新在前） |
| `addRecord(eventId)` | 记一条，返回毫秒 |
| `deleteRecord(eventId, position)` | 删指定位置 |
| `deleteRecords(eventId, set)` | 批量删除（按时间戳值） |
| `undoLast(eventId)` | 撤销最新一条，返回是否成功 |
| `clearRecords(eventId)` | 清空该事件记录 |
| `recordCount(eventId)` / `lastRecord(eventId)` | 计数 / 最近一条 |
| `getAllRecords()` | 时间线数据源（全部记录按时间倒序） |
| `replaceAllData(data)` | 备份恢复：先清空旧 records_* 键，再整体写入 |

---

## 三、备份格式（跨平台兼容红线）

**格式必须与 Android 版完全一致**，这样两边导出的 JSON 可以互相导入：

```json
{
  "app": "timestamp-recorder",
  "format": 1,
  "exportedAt": 1757900000000,
  "events": [
    { "id": 1757900000000, "name": "喝水", "color": -1749179, "createdAt": 1757900000000 }
  ],
  "records": {
    "1757900000000": [1757900123456, 1757900000000]
  }
}
```

| 约束 | 说明 |
|:---|:---|
| `app` | **必须等于** `"timestamp-recorder"`，否则视为非法备份 |
| `format` | 当前 `1` |
| `records` 的键 | 字符串形式的 eventId（JSON 对象键只能是字符串） |
| 导出缩进 | Android 版用 2 空格美化，鸿蒙版保持一致便于比对 |
| 恢复语义 | **整体覆盖，不是合并**；恢复前提示「将覆盖 N 个事件、M 条记录」 |

---

## 四、事件色板（12 色，Material 风格）

| # | 色值 | 名称 |
|:--:|:---|:---|
| 1 | `#E53935` | 红 |
| 2 | `#FB8C00` | 橙 |
| 3 | `#F9A825` | 琥珀 |
| 4 | `#43A047` | 绿 |
| 5 | `#00897B` | 青绿 |
| 6 | `#00ACC1` | 青 |
| 7 | `#1E88E5` | 蓝 |
| 8 | `#3949AB` | 靛 |
| 9 | `#8E24AA` | 紫 |
| 10 | `#D81B60` | 粉 |
| 11 | `#6D4C41` | 棕 |
| 12 | `#546E7A` | 蓝灰 |

新建事件时默认**随机**取一个。

> ⚠️ **兼容性坑（务必处理）**：Android 侧 `color` 以**有符号 32 位 int** 存入 JSON（`0xFFE53935.toInt()` → 负数，如 `-1749179`）。鸿蒙读取后转颜色字符串时必须做无符号转换：
> `'#' + ((n >>> 0) & 0xFFFFFF).toString(16).padStart(6, '0')`
> 写入时也保持同样的有符号数值，否则两边备份不互通。

---

## 五、时间显示规则

| 场景 | 格式 | 示例 |
|:---|:---|:---|
| 详情页完整时间 | `yyyy-MM-dd HH:mm:ss` | `2026-09-15 09:41:53` |
| 时间线行内时间 | `HH:mm:ss` | `09:41:53` |
| 卡片最近记录 | `yyyy-MM-dd HH:mm` | `2026-09-15 09:41` |
| 复制到剪贴板 | `yyyy-MM-dd HH:mm:ss  (Unix 秒: <秒>)` | — |

**相对时间（时间线）**：

| 差值 | 文案 |
|:---|:---|
| < 60 秒 | 刚刚 |
| < 60 分钟 | N 分钟前 |
| < 24 小时 | N 小时前 / N 小时, M 分钟前（M=0 时省略） |
| ≥ 24 小时 | N 天前 |

> Unix 秒 = `Math.floor(millis / 1000)`。

---

## 六、页面与功能清单（P0–P3 范围）

### P0 最小闭环
| 页面 / 能力 | 内容 |
|:---|:---|
| 事件列表页 | 事件卡片列表（色点 + 名字 + 记录数 + 最近时间）、点卡片右侧按钮记一条、底部「＋」新建 |
| 新建/编辑事件弹窗 | 名称（空则提示）+ 12 色选择 + 保存 |
| 数据落地 | Preferences（§2 结构）+ 重启不丢 |

### P1 核心功能
| 能力 | 要点 |
|:---|:---|
| 左右切页 | 事件 ↔ 时间线（`Swiper` 跟手）+ 底部胶囊滑块 |
| 时间线 | 全部记录按月分组、按事件染色、顶部起笔线贯穿 |
| 详情页 | 大记录按钮、撤销上一条、记录列表、点行复制、长按删除、批量管理、导出 CSV |
| 统计 | 各事件记录数柱状图 + 近 14 天趋势（`Canvas` 自绘） |
| 拖拽排序 | 按住「≡」拖动（`List.onItemDragStart` / `onItemDrop`）+ 「按最近记录」模式 |
| 设置 | 排序模式、小组件圆角、一键添加、备份导入导出、教程入口、关于 |
| 备份 | 导出/恢复 JSON（§3 格式，走 `DocumentViewPicker`，零权限） |

### P2 招牌特色（服务卡片）
| 形态 | 说明 |
|:---|:---|
| 全部事件卡片 | 列出事件，点哪行记哪个 |
| 单事件卡片 | 绑定一个事件，按尺寸分档渲染（1×1 ~ 4×4） |
| 胶囊卡片 | 2×1 横向 |

点击后走 `postCardAction` 的 `message` 事件 → `onFormEvent` 后台写入 → `updateForm` 回刷卡片（**不打开 App 界面**）。

### P3 打磨
高斯模糊玻璃栏（`backgroundEffect`）、深浅色、平板大屏自适应布局、应用图标。

---

## 七、其他移植注意点

| 项 | 说明 |
|:---|:---|
| 字体 | MiSans 可通过 `font.registerFont()` + `resources/rawfile` 复用同一份字体文件 |
| 剪贴板 | `@ohos.pasteboard`（`createData` + `systemPasteboard.setData`） |
| 卡片圆角设置 | Android 侧是小组件圆角四档（8/16/24/32dp），鸿蒙卡片圆角由 `form_config.json` 与卡片自身样式决定 |
| 删除确认 | 一律弹确认框（删事件=连同记录一起删；删记录=单条；批量删除=显示条数） |
| 空状态 | 事件列表、时间线、详情页、统计页都需要中文空状态文案（复用 Android 版 strings） |
| 深浅色 | 全部颜色走语义化资源，不硬编码 |
