import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { EventRepository } from '../data/EventRepository';
import { syncAllForms } from '../util/FormSync';
import { colorToHex, EVENT_COLORS, randomEventColor, TimelineRecord, TimestampEvent } from '../model/TimestampEvent';
import { TimeFormat } from '../util/TimeFormat';
import { getTheme, ThemeColors, GlassRowModifier, GlassColumnModifier, GlassStackModifier } from '../util/Theme';

/** 列表行模型：事件 + 该事件的记录数 / 最近一条时间 */
class EventRow {
  ev: TimestampEvent;
  count: number;
  last: number;

  constructor(ev: TimestampEvent, count: number, last: number) {
    this.ev = ev;
    this.count = count;
    this.last = last;
  }
}

/** 时间线分组（按月） */
class TimelineGroup {
  key: string;
  title: string;
  items: TimelineRecord[];
  // 月头上方那条记录（上月最后一条）的事件色，用于月头竖线渐变衔接；-1 = 列表最顶（HEAD 半透起笔）
  prevColor: number = -1;

  constructor(key: string, title: string, items: TimelineRecord[]) {
    this.key = key;
    this.title = title;
    this.items = items;
  }
}

// ============ 设计令牌：颜色走主题（深浅跟随系统，见 util/Theme.ets），此处只留尺寸常量 ============
const ISLAND_H: number = 56;
const FAB_SIZE: number = 52;
const RADIUS_LG: number = 20;
const CARD_GAP: number = 10;
const APPBAR_H: number = 102;   // 旧占位（未沉浸）；沉浸后改用 statusBarHeight + TOPBAR_CONTENT_H
const TOPBAR_CONTENT_H: number = 70; // 顶栏内容高（不含状态栏）：沉浸后顶栏总高 = statusBarHeight + 本值
const BOTTOMBAR_H: number = 92; // 悬浮玻璃底栏占位（内容层底部留白，沉浸后另加 navBarHeight）
const FAB_GAP: number = 60;     // 底部胶囊岛中央 FAB 中缝禁区宽度
// ⚠️ 内容层不再用 padding 给悬浮栏让位：改为首尾各插一个等高「留白 ListItem」，
//    这样内容可以从透明栏（实时高斯模糊）背后滚过去，时间轴也能一路贯穿到屏幕上下边缘。
const PAGE_TOP_GAP: number = 10; // 首项距顶栏底的额外呼吸量

function monthKeyOf(millis: number): string {
  const d: Date = new Date(millis);
  return `${d.getFullYear()}-${d.getMonth() + 1}`;
}

function monthTitleOf(millis: number): string {
  const d: Date = new Date(millis);
  return `${d.getFullYear()} 年 ${d.getMonth() + 1} 月`;
}

@Entry
@Component
struct Index {
  @State rows: EventRow[] = [];
  @State tlGroups: TimelineGroup[] = [];
  @State curTab: number = 0;
  // 新建 / 编辑事件弹层（editId < 0 = 新建）
  @State showAdd: boolean = false;
  @State editId: number = -1;
  @State editName: string = '';
  @State editColor: number = 0;
  // 顶栏 ⋮ 菜单
  @State showTopMenu: boolean = false;
  // 手动排序（P1-5：设置页切换，persist 于 sort_mode；@State 保证拖柄显隐即时刷新）
  @State sortManual: boolean = true;
  // 深浅色跟随系统（EntryAbility 写入 AppStorage，切换时全局换肤）
  @StorageProp('isDark') isDark: boolean = false;
  // 沉浸式避让区高度（EntryAbility.applyImmersive 写入）：状态栏 / 小白条导航条
  @StorageProp('statusBarHeight') statusBarH: number = 0;
  @StorageProp('navBarHeight') navBarH: number = 0;
  // Tab 跟手滑块：0=事件页，1=时间线页；滑动过程中为 0~1 连续值（由 Swiper.onContentDidScroll 驱动）
  @State tabProgress: number = 0;
  @State islandW: number = 0; // 底部胶囊岛实测宽度（用于计算滑块宽度与位移）

  private repo: EventRepository | null = null;
  private swiperCtl: SwiperController = new SwiperController();

  /** 当前语义色板（浅/深）。⚠️ ArkUI struct 内不能用 getter（首帧 this 为 undefined 崩溃），必须用普通方法 */
  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.repo = new EventRepository(ctx);
    this.repo.onChanged = () => syncAllForms(ctx);
    this.sortManual = this.repo.getSortMode() !== 'recent';
    this.reload();
  }

  /** 页面重新可见时刷新（从详情页 / 设置页返回，补齐 ForEach 复用不刷新的缺口） */
  onPageShow(): void {
    // 排序模式可能在设置页被改，返回时重新读取
    if (this.repo !== null) {
      this.sortManual = this.repo.getSortMode() !== 'recent';
    }
    this.reload();
    // 详情页「时间线」菜单项请求回到主页并切到时间线 tab（读后即清）
    if (AppStorage.get<boolean>('detailOpenTimeline') === true) {
      AppStorage.setOrCreate('detailOpenTimeline', false);
      this.switchTab(1);
    }
  }

  /** 从数据层重新读取（整体替换数组以触发刷新） */
  private reload(): void {
    if (this.repo === null) {
      return;
    }
    // 事件页：手动顺序（拖拽排序后的持久化顺序）
    const events: TimestampEvent[] = this.sortManual ? this.repo.getEvents() : this.repo.getEventsByRecent();
    const next: EventRow[] = [];
    events.forEach((ev: TimestampEvent) => {
      const last: number | null = this.repo!.lastRecord(ev.id);
      next.push(new EventRow(ev, this.repo!.recordCount(ev.id), last === null ? -1 : last));
    });
    this.rows = next;

    // 时间线（全部记录按时间倒序 → 按月分组）。同时维护竖线渐变衔接色：
    // prev 始终是「视觉上一条（更靠上、时间更新）」的事件色，相邻段首尾同色 → 整条连续（对齐 Android TimelineLineView）
    const groups: TimelineGroup[] = [];
    let curKey: string = '';
    let prev: number = -1;
    const records: TimelineRecord[] = this.repo.getAllRecords();
    for (let i = 0; i < records.length; i++) {
      const r: TimelineRecord = records[i];
      const key: string = monthKeyOf(r.millis);
      if (key !== curKey) {
        const g: TimelineGroup = new TimelineGroup(key, monthTitleOf(r.millis), []);
        g.prevColor = prev;
        groups.push(g);
        curKey = key;
      }
      // ⚠️ 哨兵必须精确 === -1：EVENT_COLORS 经 `| 0` 转有符号 int 全为负数，
      //    若用 < 0 判断，会把每条记录都误判成「无上一条」→ 整条线恒实色、渐变彻底失效。
      r.prevColor = prev === -1 ? r.eventColor : prev;
      prev = r.eventColor;
      const g0: TimelineGroup = groups[groups.length - 1];
      g0.items.push(r);
      if (g0.items.length === 1 && g0.prevColor === -1) {
        g0.prevColor = r.eventColor;  // 月头同规则归一化：无上一条时实色起笔
      }
    }
    this.tlGroups = groups;
  }

  // ==================== 顶栏动作 ====================

  private openDetail(id: number): void {
    router.pushUrl({ url: 'pages/EventDetail', params: { eventId: id } });
  }

  private openStats(): void {
    this.showTopMenu = false;
    router.pushUrl({ url: 'pages/Stats' });
  }

  private openSettings(): void {
    this.showTopMenu = false;
    router.pushUrl({ url: 'pages/Settings' });
  }

  private openTutorial(): void {
    this.showTopMenu = false;
    router.pushUrl({ url: 'pages/Tutorial' });
  }

  // ==================== 事件操作 ====================

  private openAddSheet(): void {
    this.editId = -1;
    this.editName = '';
    this.editColor = randomEventColor();
    this.showAdd = true;
  }

  private openEditSheet(ev: TimestampEvent): void {
    this.editId = ev.id;
    this.editName = ev.name;
    this.editColor = ev.color;
    this.showAdd = true;
  }

  private saveSheet(): void {
    const name: string = this.editName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入事件名称' });
      return;
    }
    if (this.editId < 0) {
      this.repo?.addEvent(name, this.editColor);
      this.getUIContext().getPromptAction().showToast({ message: `已新建「${name}」` });
    } else {
      this.repo?.updateEvent(this.editId, name, this.editColor);
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    }
    this.showAdd = false;
    this.reload();
  }

  private recordOnce(ev: TimestampEvent): void {
    const millis: number = this.repo?.addRecord(ev.id) ?? 0;
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: `已记录 ${TimeFormat.hm(millis)}` });
  }

  /** 卡片 ⋮：编辑 / 删除（对齐 Android showEventMenu） */
  private showEventMenu(ev: TimestampEvent): void {
    this.getUIContext().showAlertDialog({
      title: ev.name,
      message: '选择操作',
      buttons: [
        {
          value: '编辑事件',
          fontColor: this.theme().primary,
          action: () => {
            this.openEditSheet(ev);
          }
        },
        {
          value: '删除事件',
          fontColor: this.theme().danger,
          action: () => {
            this.confirmDeleteEvent(ev);
          }
        },
        {
          value: '取消',
          fontColor: this.theme().onSurfaceVariant,
          action: () => {
          }
        }
      ]
    });
  }

  private confirmDeleteEvent(ev: TimestampEvent): void {
    const count: number = this.repo?.recordCount(ev.id) ?? 0;
    this.getUIContext().showAlertDialog({
      title: '删除事件？',
      message: `将删除事件「${ev.name}」及其全部 ${count} 条记录，无法恢复。`,
      buttons: [
        {
          value: '删除',
          fontColor: this.theme().danger,
          action: () => {
            this.repo?.deleteEvent(ev.id);
            this.reload();
            this.getUIContext().getPromptAction().showToast({ message: '事件已删除' });
          }
        },
        {
          value: '取消',
          fontColor: this.theme().onSurfaceVariant,
          action: () => {
          }
        }
      ]
    });
  }

  /** 拖拽排序（P1-4）：List.onMove → 更新数组 → 持久化顺序 */
  private moveEvent(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.rows.length || to >= this.rows.length) {
      return;
    }
    const arr: EventRow[] = this.rows.slice();
    const item: EventRow = arr.splice(from, 1)[0];
    arr.splice(to, 0, item);
    this.rows = arr;
    this.repo?.setEventsOrder(arr.map((r: EventRow) => r.ev.id));
  }

  private switchTab(i: number): void {
    if (this.curTab === i) {
      return;
    }
    this.curTab = i;
    this.swiperCtl.changeIndex(i);
  }

  // ============ 首尾留白：与悬浮栏等高，让首/末项停栏边，同时内容可从栏背后穿过 ============

  /** 顶部留白高度 = 顶栏内容高 + 状态栏 + 呼吸量（事件页与时间线页共用 → 两页起始高度严格一致） */
  private topPad(): number {
    return TOPBAR_CONTENT_H + this.statusBarH + PAGE_TOP_GAP;
  }

  /** 底部留白高度 = 底栏占位 + 小白条 */
  private tlScroller: Scroller = new Scroller();
  private tlInitScrolled: boolean = false;

  private bottomPad(): number {
    return BOTTOMBAR_H + this.navBarH;
  }

  /** 时间轴最顶端那条记录的事件色（顶部留白段竖线用它，让轴线从屏幕顶边延伸进来） */
  private firstRecordColor(): number {
    if (this.tlGroups.length === 0 || this.tlGroups[0].items.length === 0) {
      return EVENT_COLORS[0];
    }
    return this.tlGroups[0].items[0].eventColor;
  }

  /** 时间轴最末端那条记录的事件色（底部留白段竖线用它，让轴线延伸出屏幕底边） */
  private lastRecordColor(): number {
    if (this.tlGroups.length === 0) {
      return EVENT_COLORS[0];
    }
    const g: TimelineGroup = this.tlGroups[this.tlGroups.length - 1];
    if (g.items.length === 0) {
      return EVENT_COLORS[0];
    }
    return g.items[g.items.length - 1].eventColor;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ---------- 时间轴灰线底（页面级固定，不随滚动）：列表限位正常，overscroll 回弹只露灰线、尽头不漏空 ----------
      // x=26vp：列表 padding 16 + 线区 Stack(22) 内线中心 11 - 半宽 1；opacity 跟随 tab 进度（事件页 0、时间线 1）
      Column()
        .width(2)
        .height('100%')
        .backgroundColor(this.theme().outline)
        .position({ x: 26, y: 0 })
        .opacity(this.tabProgress)

      // ---------- 内容层：双页撑满全屏，滚动内容从悬浮玻璃栏底下穿过 ----------
      Swiper(this.swiperCtl) {
        this.EventsPage()
        this.TimelinePage()
      }
      .index(this.curTab)
      .loop(false)
      .indicator(false)
      .duration(220)
      .curve(Curve.Friction)
      .width('100%')
      .height('100%')
      .onContentDidScroll((selectedIndex: number, index: number, position: number, mainAxisLength: number) => {
        if (index !== 0) {
          return;
        }
        // ⚠️ position 是「归一化页偏移」（SDK 原文：页0 的 translate = -position × mainAxisLength），不是像素。
        //    旧版按像素 -position / mainAxisLength 计算 → 进度几乎恒为 0，这就是滑块不跟手的根因。
        //    这里做量纲自适应：归一值(0~1)直接用，若大于 1 则视为像素再除以主轴长度，两种口径都兼容。
        const raw: number = position < 0 ? -position : position;
        const ratio: number = (raw > 1 && mainAxisLength > 0) ? raw / mainAxisLength : raw;
        this.tabProgress = ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
      })
      .onChange((i: number) => {
        this.curTab = i;
        this.tabProgress = i; // 兜底：静止时进度与页号一致
      })

      // ---------- 顶栏：独立悬浮贴顶（position 定位，只占自身高度，不遮挡下方列表点击） ----------
      // 顶栏（标题 + ⋮）：高斯模糊玻璃，透出下方滚动内容
      Row() {
          Column() {
            Text('时间戳记录')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().onSurface)
            Text('管理事件 · 一键记录 · 桌面快捷')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            this.MoreVertIcon(this.theme().onSurfaceVariant)
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showTopMenu = true;
          })
        }
        .width('100%')
        .height(TOPBAR_CONTENT_H + this.statusBarH)
        .padding({ left: 20, right: 8, top: this.statusBarH, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        // 沉浸光感（液态玻璃）：API 26 设备用 uiMaterial.ImmersiveMaterial 真·透出背后滚动内容；
        // 低版本降级实时高斯模糊。旧版 glassToolbar（alpha 75%）等同「不透明方块」，把背后内容全挡住了。
        .attributeModifier(new GlassRowModifier(this.theme().glassBar))

      // ---------- 底栏：独立悬浮贴底（markAnchor+position 锚到容器底边，只占自身高度，不遮挡列表） ----------
      Column() {
        // ---------- 底部胶囊岛（事件 / 时间线 + 居中加号） ----------
        this.BottomBar()
      }
      .width('100%')
      .markAnchor({ x: 0, y: '100%' })
      .position({ x: 0, y: '100%' })

      // ---------- 新建 / 编辑事件弹层 ----------
      if (this.showAdd) {
        this.AddSheet()
      }

      // ---------- 顶栏 ⋮ 菜单（设置 / 统计 / 教程） ----------
      if (this.showTopMenu) {
        this.TopMenuOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
    })
  }

  // ==================== 图标（基础形状自绘，零字体依赖） ====================

  /** 事件 tab：三点三线（对齐 ic_tab_events） */
  @Builder
  EventsTabIcon(color: string) {
    Column() {
      Row() {
        Circle().width(5).height(5).fill(color)
        Rect().width(11).height(2).radius(1).fill(color).margin({ left: 4 })
      }
      Row() {
        Circle().width(5).height(5).fill(color)
        Rect().width(11).height(2).radius(1).fill(color).margin({ left: 4 })
      }
      .margin({ top: 3 })
      Row() {
        Circle().width(5).height(5).fill(color)
        Rect().width(11).height(2).radius(1).fill(color).margin({ left: 4 })
      }
      .margin({ top: 3 })
    }
  }

  /** 时间线 tab：竖线 + 三点（对齐 ic_tab_timeline） */
  @Builder
  TimelineTabIcon(color: string) {
    Stack() {
      Rect().width(2.5).height(20).radius(1).fill(color)
      Column() {
        Circle().width(5.2).height(5.2).fill(color)
        Circle().width(5.2).height(5.2).fill(color).margin({ top: 2.2 })
        Circle().width(5.2).height(5.2).fill(color).margin({ top: 2.2 })
      }
    }
    .width(20)
    .height(20)
  }

  /** ⋮ 三点（对齐 ic_more_vert） */
  @Builder
  MoreVertIcon(color: string) {
    Column() {
      Circle().width(4).height(4).fill(color)
      Circle().width(4).height(4).fill(color).margin({ top: 3 })
      Circle().width(4).height(4).fill(color).margin({ top: 3 })
    }
    .width(20)
    .height(20)
    .justifyContent(FlexAlign.Center)
  }

  /** 拖拽手柄：2×3 圆点（对齐 ic_drag） */
  @Builder
  DragIcon(color: string) {
    Column() {
      Row() {
        Circle().width(4.5).height(4.5).fill(color)
        Circle().width(4.5).height(4.5).fill(color).margin({ left: 8 })
      }
      Row() {
        Circle().width(4.5).height(4.5).fill(color)
        Circle().width(4.5).height(4.5).fill(color).margin({ left: 8 })
      }
      .margin({ top: 3.5 })
      Row() {
        Circle().width(4.5).height(4.5).fill(color)
        Circle().width(4.5).height(4.5).fill(color).margin({ left: 8 })
      }
      .margin({ top: 3.5 })
    }
  }

  /** 白色加号（对齐 ic_add / ic_record_plus） */
  @Builder
  PlusIcon(size: number, barW: number, color: string) {
    Stack() {
      Rect().width(barW).height(size).radius(barW / 2).fill(color)
      Rect().width(size).height(barW).radius(barW / 2).fill(color)
    }
    .width(size)
    .height(size)
  }

  // ⚠️ 菜单三图标必须同风格：统一 18×18 容器 + onSurfaceVariant（次要色）+ 实心几何。
  //    旧版 Stats 用 primary 蓝、Tutorial 用描边框+文字，三者并排时风格割裂。

  /** 菜单行图标：设置 = 三条横杠 */
  @Builder
  SettingsIcon() {
    Column() {
      Rect().width(14).height(2).radius(1).fill(this.theme().onSurfaceVariant)
      Rect().width(14).height(2).radius(1).fill(this.theme().onSurfaceVariant).margin({ top: 3 })
      Rect().width(14).height(2).radius(1).fill(this.theme().onSurfaceVariant).margin({ top: 3 })
    }
    .width(18)
    .height(18)
    .justifyContent(FlexAlign.Center)
  }

  /** 菜单行图标：统计 = 三根柱 */
  @Builder
  StatsIcon() {
    Row() {
      Rect().width(3).height(7).radius(1).fill(this.theme().onSurfaceVariant)
      Rect().width(3).height(11).radius(1).fill(this.theme().onSurfaceVariant).margin({ left: 3 })
      Rect().width(3).height(15).radius(1).fill(this.theme().onSurfaceVariant).margin({ left: 3 })
    }
    .width(18)
    .height(18)
    .alignItems(VerticalAlign.Bottom)
    .justifyContent(FlexAlign.Center)
  }

  /** 菜单行图标：教程 = 实心「i」信息（说明 / 指引语义） */
  @Builder
  TutorialIcon() {
    Column() {
      Circle().width(4).height(4).fill(this.theme().onSurfaceVariant)
      Rect().width(3).height(10).radius(1.5).fill(this.theme().onSurfaceVariant).margin({ top: 3 })
    }
    .width(18)
    .height(18)
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 顶栏 ⋮ 菜单 ====================

  @Builder
  TopMenuOverlay() {
    Stack() {
      // 遮罩：点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme().menuMask)
        .onClick(() => {
          this.showTopMenu = false;
        })

      // 菜单卡（188 宽，右上角）。⚠️ 用父容器 alignContent 定位（子组件 .align() 在此失效，见 #27）
      Column() {
        Row() {
          this.SettingsIcon()
          Text('设置')
            .fontSize(15)
            .fontColor(this.theme().onSurface)
            .margin({ left: 12 })
          Blank()
        }
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .onClick(() => this.openSettings())

        Divider().color(this.theme().divider).strokeWidth(0.5)

        Row() {
          this.StatsIcon()
          Text('统计')
            .fontSize(15)
            .fontColor(this.theme().onSurface)
            .margin({ left: 12 })
          Blank()
        }
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .onClick(() => this.openStats())

        Divider().color(this.theme().divider).strokeWidth(0.5)

        Row() {
          this.TutorialIcon()
          Text('教程')
            .fontSize(15)
            .fontColor(this.theme().onSurface)
            .margin({ left: 12 })
          Blank()
        }
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .onClick(() => this.openTutorial())
      }
      .width(188)
      .attributeModifier(new GlassColumnModifier(this.theme().glassMenu))
      .borderRadius(16)
      .border({ width: 1, color: this.theme().glassStroke })
      .margin({ top: 62 + this.statusBarH, right: 12 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopEnd)
  }

  // ==================== 事件页 ====================

  @Builder
  EventsPage() {
    Column() {
      if (this.rows.length === 0) {
        Column() {
          Text('还没有事件')
            .fontSize(15)
            .fontColor(this.theme().onSurfaceVariant)
          Text('点击右下角 + 添加第一个事件')
            .fontSize(13)
            .fontColor(this.theme().onSurfaceVariant)
            .margin({ top: 6 })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .layoutWeight(1)
      } else {
        // ⚠️ 不再用 List({space}) + padding 让位：改为首尾插入等高留白项（间距改由卡片自身 margin 承担），
        //    这样列表内容可以从透明顶/底栏背后滚过，且两页留白高度完全一致（起始位置对齐）。
        List() {
          ListItem() {
            Column().height(this.topPad())
          }

          ForEach(this.rows, (row: EventRow) => {
            ListItem() {
              this.EventCard(row)
            }
            .id(`ev-${row.ev.id}`)
            .margin({ bottom: CARD_GAP })
          }, (row: EventRow) => `${row.ev.id}-${row.count}-${row.last}`)
          .onMove((from: number, to: number) => {
            this.moveEvent(from, to);
          })

          ListItem() {
            Column().height(this.bottomPad())
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        // alwaysEnabled：内容不足一屏时也允许划拉动效（缺省 false 时 List 完全拖不动）
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 事件卡片（对齐 Android item_event.xml）：拖柄 / 色点 / 名字+信息 / ⋮ / 快捷记录胶囊 */
  @Builder
  EventCard(row: EventRow) {
    Row() {
      // 拖拽手柄（手动排序模式）
      if (this.sortManual) {
        Column() {
          this.DragIcon(this.theme().outline)
        }
        .width(32)
        .height(36)
        .justifyContent(FlexAlign.Center)
      }

      // 事件色点
      Circle()
        .width(14)
        .height(14)
        .fill(colorToHex(row.ev.color))
        .margin({ left: this.sortManual ? 6 : 0 })

      // 名字 + 信息
      Column() {
        Text(row.ev.name)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.last === -1 ? '暂无记录' : `最近 ${TimeFormat.hm(row.last)}`)
          .fontSize(13)
          .fontColor(this.theme().onSurfaceVariant)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      .onClick(() => this.openDetail(row.ev.id))

      // ⋮（编辑 / 删除）
      Column() {
        this.MoreVertIcon(this.theme().onSurfaceVariant)
      }
      .width(34)
      .height(34)
      .margin({ left: 6 })
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.showEventMenu(row.ev))

      // 快捷记录胶囊（事件色 + 白色加号与计数）
      Row() {
        this.PlusIcon(13, 1.8, this.theme().white)
        Text(`${row.count}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().white)
          .margin({ left: 6 })
      }
      .height(36)
      .constraintSize({ minWidth: 62 })
      .padding({ left: 12, right: 14 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor(colorToHex(row.ev.color))
      .borderRadius(18)
      .margin({ left: 8 })
      .onClick(() => this.recordOnce(row.ev))
    }
    .width('100%')
    .padding({ left: 10, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.theme().glassCard)
    .borderRadius(RADIUS_LG)
    .border({ width: 1, color: this.theme().glassStroke })
    .alignItems(VerticalAlign.Center)
  }

  // ==================== 时间线页 ====================

  @Builder
  TimelinePage() {
    Column() {
      if (this.tlGroups.length === 0) {
        Column() {
          Text('还没有任何记录')
            .fontSize(15)
            .fontColor(this.theme().onSurfaceVariant)
          Text('先到主页点几下「记录」吧')
            .fontSize(13)
            .fontColor(this.theme().onSurfaceVariant)
            .margin({ top: 6 })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .layoutWeight(1)
      } else {
        // ⚠️ 同事件页：去掉 top/bottom padding，首尾各插一个「带竖线的留白项」。
        //    这样时间轴从屏幕最顶端（透明顶栏背后）一路贯穿到最底端（底栏之下），不再被夹在中间截断。
        List({ scroller: this.tlScroller }) {
          ListItem() {
            this.AxisSpacer(this.topPad(), this.theme().outline, colorToHex(this.firstRecordColor()))
          }

          ForEach(this.tlGroups, (g: TimelineGroup) => {
            ListItemGroup({ header: this.MonthHeader(g) }) {
              ForEach(g.items, (r: TimelineRecord) => {
                ListItem() {
                  this.TimelineRow(r)
                }
              }, (r: TimelineRecord) => `${r.eventId}-${r.millis}`)
            }
          }, (g: TimelineGroup) => `${g.key}-${g.items.length}-${g.items.length > 0 ? g.items[0].millis : 0}`)

          ListItem() {
            this.AxisSpacer(this.bottomPad(), colorToHex(this.lastRecordColor()), this.theme().outline)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        // 不吸顶：月份头要和普通记录节点一样随内容滑动、可滑出屏幕。
        // 旧版 sticky(StickyStyle.Header) 把月份钉死在额头下方（主人反馈「堆到额头下」）
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 月份头（对齐 Android item_timeline_month.xml）：线区 + 月份 + 条数 */
  @Builder
  MonthHeader(g: TimelineGroup) {
    Row() {
      // 线区：竖线延续 + 淡色刻度点（用该月首条记录的颜色）。
      // ⚠️ 行高与线高都固定 40，线从头贯穿到尾、与首条记录的线无缝衔接（#26 连带修复：月头线此前断 6.9vp）。
      Stack({ alignContent: Alignment.Center }) {
        // 竖线用普通 Column 承载 linearGradient（Shape 的 Rect 不支持通用渐变属性，会渲染成黑色）
        Column().width(2).height(42)  // +2vp：上下各溢出 1vp 与相邻线段重叠，消除滚动亚像素缝隙
          .linearGradient({
            // ⚠️ 必须与主背景(angle:135)同构：angle + 内联 colors。实测（像素级分析）：
            //    函数返回 colors 或 direction 版会渲染成纯色；angle:90 是横向在 2px 线上不可见。
            angle: 180,
            colors: [[colorToHex(g.prevColor), 0.0], [colorToHex(g.items[0].eventColor), 1.0]]
          })
        Circle()
          .width(7)
          .height(7)
          .fill(g.items.length > 0 ? colorToHex(g.items[0].eventColor) : this.theme().outline)
      }
      .width(22)
      .height(40)

      Row() {
        Text(g.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
        Text(`· ${g.items.length} 条`)
          .fontSize(12)
          .fontColor(this.theme().onSurfaceVariant)
          .margin({ left: 8 })
      }
      .margin({ left: 10 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    // 月份头完全透明：它已不是吸顶项，和普通记录节点一样随内容滚动、可滑出屏幕，
    // 不需要任何底色/模糊（主人反馈「被套了个模糊框」）
  }

  /**
   * 时间线竖线一段的两色纵向渐变（对齐 Android TimelineLineView）：
   * 从上一条事件色 prev 平滑过渡到本条事件色 own，相邻段首尾同色 → 整条读起来连续、呈彩虹轴。
   * - prev<0（无上一条）：整段用本条实色。旧版这里做「半透明起笔」，导致轴线在列表最顶端出现断口，
   *   与顶部留白段的实色线接不上，看起来像被截断。
   */
  private lineColors(prev: number, own: number): Array<[ResourceColor, number]> {
    if (prev < 0) {
      const solid: string = colorToHex(own);
      return [[solid, 0.0], [solid, 1.0]];
    }
    return [[colorToHex(prev), 0.0], [colorToHex(own), 1.0]];
  }

  /**
   * 时间轴首尾留白段（主人的「灰线底」设计）：
   * 长度 = 头/尾安全区 + AXIS_SPACER_EXTRA，线为线性渐变——
   * 顶段从灰(outline)向下渐入首节点色、底段从末节点色向下渐出到灰，
   * 渐变带 >= 一屏；overscroll 回弹再深也只露灰线，尽头不再漏空。
   */
  @Builder
  AxisSpacer(h: number, fromHex: string, toHex: string) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(2)
        .height(h + 2)  // +2vp 溢出重叠防滚动缝隙
        .linearGradient({
          angle: 180,  // to bottom；direction 版实测渲染成纯色（像素分析证实）
          colors: [[fromHex, 0.0], [toHex, 1.0]]
        })
    }
    .width(22)
    .height(h)
  }

  /** number(0xAARRGGBB 或 0xRRGGBB) + 指定 alpha(0-255) → '#AARRGGBB' */
  private argb(color: number, alpha: number): string {
    const ah: string = alpha.toString(16).padStart(2, '0');
    const rgb: string = ((color >>> 0) & 0xFFFFFF).toString(16).padStart(6, '0');
    return `#${ah}${rgb}`;
  }

  /** 时间线行（对齐 Android item_timeline_record.xml）：左侧竖线+节点，右侧玻璃卡 */
  @Builder
  TimelineRow(r: TimelineRecord) {
    Row() {
      // 线区：2dp 竖线贯穿 + 13dp 实心节点（事件色）。⚠️ 高度必须写死（卡 60 + 底距 8），
      // 百分比高度在 wrap-content 行里会塌陷成异常值导致各行堆叠（踩坑 #26）。
      Stack({ alignContent: Alignment.Center }) {
        Column().width(2).height(70)  // +2vp 溢出重叠防滚动缝隙
          .linearGradient({
            angle: 180,
            colors: [[colorToHex(r.prevColor), 0.0], [colorToHex(r.eventColor), 1.0]]
          })
        Circle()
          .width(13)
          .height(13)
          .fill(colorToHex(r.eventColor))
      }
      .width(22)
      .height(68)

      // 玻璃卡片
      Row() {
        Column() {
          Text(r.eventName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(TimeFormat.short(r.millis))
            .fontSize(12)
            .fontColor(this.theme().onSurfaceVariant)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(TimeFormat.relative(r.millis))
          .fontSize(13)
          .fontColor(this.theme().primary)
          .margin({ left: 10 })
          .maxLines(1)
      }
      .layoutWeight(1)
      .height(60)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.theme().glassCard)
      .borderRadius(16)
      .border({ width: 1, color: this.theme().glassStroke })
      .margin({ left: 10, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.openDetail(r.eventId))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ==================== 底部胶囊岛 ====================

  /** 单个 tab 宽度：胶囊岛减去左右内边距与 FAB 中缝后等分（struct 内禁用 getter，用普通方法） */
  private tabWidth(): number {
    const usable: number = this.islandW - 12; // 岛内左右 padding 各 6
    return usable > FAB_GAP ? (usable - FAB_GAP) / 2 : 0;
  }

  @Builder
  BottomBar() {
    Column() {
      Stack() {
        // 跟手滑块（底层）：宽度 = 单个 tab，x 随 tabProgress 连续移动（不加 animation，保证 1:1 跟手）
        if (this.tabWidth() > 0) {
          Row() {}
            .width(this.tabWidth())
            .height(ISLAND_H - 12)
            .borderRadius(24)
            .backgroundColor(this.theme().tabActive)
            .position({ x: 6 + this.tabProgress * (this.tabWidth() + FAB_GAP), y: 6 })
        }

        // 内容层：左 tab / FAB 中缝 / 右 tab（选中态由 tabProgress 判定，背景交给滑块）
        Row() {
          Row() {
            this.EventsTabIcon(this.tabProgress < 0.5 ? this.theme().onSurface : this.theme().onSurfaceVariant)
            Text('事件')
              .fontSize(15)
              .fontWeight(this.tabProgress < 0.5 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.tabProgress < 0.5 ? this.theme().onSurface : this.theme().onSurfaceVariant)
              .margin({ left: 7 })
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.switchTab(0))

          // FAB 中缝禁区（对齐 fab_glass_gap 60dp）：加号圆钮嵌在岛正中心
          Column() {
            Stack() {
              this.PlusIcon(26, 3, this.theme().white)
            }
            .width(FAB_SIZE)
            .height(FAB_SIZE)
            .borderRadius(FAB_SIZE / 2)
            .backgroundColor(this.theme().primary)
            .shadow({ radius: 12, color: '#331565C0', offsetY: 4 })
            .onClick(() => this.openAddSheet())
          }
          .width(60)
          .height('100%')
          .justifyContent(FlexAlign.Center)

          Row() {
            this.TimelineTabIcon(this.tabProgress >= 0.5 ? this.theme().onSurface : this.theme().onSurfaceVariant)
            Text('时间线')
              .fontSize(15)
              .fontWeight(this.tabProgress >= 0.5 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.tabProgress >= 0.5 ? this.theme().onSurface : this.theme().onSurfaceVariant)
              .margin({ left: 7 })
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.switchTab(1))
        }
        .width('100%')
        .height('100%')
        .padding({ left: 6, right: 6 })
      }
      .width('100%')
      .height(ISLAND_H)
      // 液态玻璃悬浮岛：API 26 用 ImmersiveMaterial 真·透光（透出背后滚动的时间线）；
      // 低版本降级实时高斯模糊。滑块/边框/圆角由常规链路上层叠加，互不冲突。
      .attributeModifier(new GlassStackModifier(this.theme().glassBar))
      .borderRadius(28)
      .border({ width: 1, color: this.theme().glassStroke })
      .margin({ left: 16, right: 16, bottom: 12 })
      .onAreaChange((_oldVal: Area, newVal: Area) => {
        // ⚠️ width 可能是 number(vp)，也可能是 "360vp" 字符串；Number('360vp') = NaN → tabWidth() 为 0 → 滑块不渲染
        const w: number = (typeof newVal.width === 'number') ?
          newVal.width : parseFloat(newVal.width.toString());
        if (!Number.isNaN(w) && w > 0) {
          this.islandW = w;
        }
      })
    }
    .width('100%')
    .padding({ bottom: this.navBarH })
  }

  /** 悬浮加号：已并入底部胶囊岛中缝（P1-4 修复 align 失效） */
  @Builder
  FabButton() {
    Stack() {
      this.PlusIcon(26, 3, this.theme().white)
    }
    .width(FAB_SIZE)
    .height(FAB_SIZE)
    .borderRadius(FAB_SIZE / 2)
    .backgroundColor(this.theme().primary)
    .shadow({ radius: 12, color: '#331565C0', offsetY: 4 })
    .onClick(() => this.openAddSheet())
  }

  // ==================== 新建 / 编辑事件弹层 ====================

  @Builder
  AddSheet() {
    Column() {
      Column() {
        Text(this.editId < 0 ? '新建事件' : '编辑事件')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
          .width('100%')

        Stack({ alignContent: Alignment.BottomEnd }) {
          TextInput({ text: this.editName, placeholder: '事件名称（如：喝水、吃药、打卡）' })
            .maxLength(20)
            .height(46)
            .padding({ right: 48 })
            .backgroundColor(this.theme().inputBg)
            .fontColor(this.theme().onSurface)
            .placeholderColor(this.theme().outline)
            .borderRadius(12)
            .onChange((v: string) => {
              this.editName = v;
            })
          // 字数统计（对齐 Android 输入框右下 n/20）
          Text(`${this.editName.length}/20`)
            .fontSize(11)
            .fontColor(this.theme().outline)
            .margin({ right: 10, bottom: 5 })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .margin({ top: 14 })

        Text('选择颜色')
          .fontSize(13)
          .fontColor(this.theme().onSurfaceVariant)
          .width('100%')
          .margin({ top: 16, bottom: 4 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(EVENT_COLORS, (c: number) => {
            Column()
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor(colorToHex(c))
              .border({
                width: this.editColor === c ? 3 : 0,
                color: this.theme().onSurface,
                radius: 17
              })
              .margin(5)
              .onClick(() => {
                this.editColor = c;
              })
          }, (c: number) => `${c}`)
        }
        .width('100%')

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(46)
            .backgroundColor(this.theme().cancelBtn)
            .fontColor(this.theme().onSurface)
            .borderRadius(23)
            .onClick(() => {
              this.showAdd = false;
            })
          Button('保存')
            .layoutWeight(1)
            .height(46)
            .backgroundColor(this.theme().primary)
            .borderRadius(23)
            .onClick(() => this.saveSheet())
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('88%')
      .padding(20)
      .backgroundColor(this.theme().glassMenu)
      .borderRadius(18)
      .border({ width: 1, color: this.theme().glassStroke })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme().mask)
  }
}
