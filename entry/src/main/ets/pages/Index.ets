import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { EventRepository } from '../data/EventRepository';
import { syncAllForms } from '../util/FormSync';
import { colorToHex, EVENT_COLORS, formatDuration, randomEventColor, TimeInterval, TimelineRecord, TimestampEvent, TYPE_INTERVAL, TYPE_POINT } from '../model/TimestampEvent';
import { ColorPickerPanel } from '../components/ColorPickerPanel';
import { TimeFormat } from '../util/TimeFormat';
import { getTheme, ThemeColors, GlassColumnModifier, GlassStackModifier, GLASS_BLUR_ONLY } from '../util/Theme';
import { logD } from '../util/Log';

/** 列表行模型：事件 + 该事件的段/条数 + 进行中的区间（null = 无进行中段） */
class EventRow {
  ev: TimestampEvent;
  count: number;
  ongoing: TimeInterval | null;

  constructor(ev: TimestampEvent, count: number, ongoing: TimeInterval | null) {
    this.ev = ev;
    this.count = count;
    this.ongoing = ongoing;
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
const TOPBAR_CONTENT_H: number = 70; // 顶栏内容高（不含状态栏）：沉浸后顶栏总高 = statusBarHeight + 本值
const TOPBAR_FADE_H: number = 32;    // 顶栏底部渐隐区高度：linearGradientBlur 在此区间把模糊强度渐减到 0。
                                     // ⚠️ 它同时决定「材质层总高」与「首项留白」（PAGE_TOP_GAP = 本值）：
                                     //    收窄 → 材质层底边上移、首卡片更贴标题；但**满模糊平台必须仍盖住标题区**（见 ramp）。
// 点击 tab 切换的平移动画：时长 ms / 逐帧节拍 ms。
// ⚠️ 这套动画由我们自己逐帧驱动（见 switchTab），不用 Swiper 的 changeIndex 过渡动画 ——
//    实测：只要在过渡期间逐帧改 tabProgress（动画状态），内容区三帧截图完全一致 = 被重渲染打断成瞬跳。
const TAB_ANIM_MS: number = 300;
const TAB_ANIM_TICK_MS: number = 16;
const DRAG_SNAP_MS: number = 180;   // 甩手/松手后的吸附时长（同样自绘，保证页与块同一套判决）
const BOTTOMBAR_H: number = 92; // 悬浮玻璃底栏占位（内容层底部留白，沉浸后另加 navBarHeight）
const FAB_GAP: number = 60;     // 底部胶囊岛中央 FAB 中缝禁区宽度
// ⚠️ 内容层不再用 padding 给悬浮栏让位：改为首尾各插一个等高「留白 ListItem」，
//    这样内容可以从透明栏（实时高斯模糊）背后滚过去，时间轴也能一路贯穿到屏幕上下边缘。
// 首项距顶栏底的呼吸量。必须 ≥ TOPBAR_FADE_H：顶栏底部是「模糊渐减到 0」的过渡区，
// 留白不足时静止状态下首个卡片会落在过渡区里被轻微糊掉。两页的顶部占位都取自 topPad()，保持一致。
const PAGE_TOP_GAP: number = TOPBAR_FADE_H;

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
  @State editType: number = TYPE_POINT; // 新建/编辑弹层选中的事件类型（点时刻 / 时间段）
  // 顶栏 ⋮ 菜单
  @State showTopMenu: boolean = false;
  // 手动排序（P1-5：设置页切换，persist 于 sort_mode；@State 保证拖柄显隐即时刷新）
  @State sortManual: boolean = true;
  // 深浅色跟随系统（EntryAbility 写入 AppStorage，切换时全局换肤）
  @StorageProp('isDark') isDark: boolean = false;
  // 沉浸式避让区高度（EntryAbility.applyImmersive 写入）：状态栏 / 小白条导航条
  @StorageProp('statusBarHeight') statusBarH: number = 0;
  @StorageProp('navBarHeight') navBarH: number = 0;
  /**
   * App 回到前台时由 EntryAbility.onForeground 递增。
   * 桌面卡片在 **独立 `:form` 进程**写入 preferences，本进程缓存不会自动刷新；
   * 该计数变化时触发本页「丢弃缓存 + 从磁盘重读」，保证卡片记录即刻反映到 App。
   */
  @StorageProp('fgReloadTick') @Watch('onForegroundReload') fgReloadTick: number = 0;
  // Tab 跟手滑块：0=事件页，1=时间线页；滑动过程中为 0~1 连续值（由 Swiper.onContentDidScroll 驱动）
  @State tabProgress: number = 0;
  @State islandW: number = 0; // 底部胶囊岛实测宽度（用于计算滑块宽度与位移）
  @State islandDragging: boolean = false; // 正在拖动底栏滑块（拖动期间由手指驱动 tabProgress）
  @State islandSettling: boolean = false; // 松手后吸附中（禁止 Swiper 回写 tabProgress，避免与滑块动画打架）
  @State pageW: number = 0; // 页面宽度 vp（拖拽驱动内容位移、时间轴灰线跟随页面平移）
  @State tick: number = 0; // 秒表驱动：每 1s +1 触发重渲染（进行中的时间段需要实时刷新「已 xxx」）

  private repo: EventRepository | null = null;
  private swiperCtl: SwiperController = new SwiperController();
  private dragStartX: number = 0;        // 拖动起点（windowX）
  private dragStartProgress: number = 0; // 拖动起始进度（0 或 1）
  private suppressClickUntil: number = 0; // 拖动刚结束时短暂屏蔽 onClick，避免误触切换
  private fakeDragging: boolean = false;  // Swiper 模拟拖拽是否已开启（@since 23，try/catch 兜底低版本）
  private contentP: number = -1;          // Swiper 上报的内容进度（诊断/对账用：-1 表示尚未上报）
  private dragApplied: number = 0;
  // 点击切换的自绘平移动画（与手指拖拽共用 fakeDrag 机制）
  private tapTimer: number = -1;
  private tapFrom: number = 0;
  private tapTo: number = 0;
  private tapStartTs: number = 0;
  private tapAnimMs: number = 300;   // 本次自绘动画时长（点击 300 / 松手吸附 180）        // 本次拖动中已下发给 Swiper 的累计位移（fakeDragBy 是增量，需自己记已下发量）
  private timerId: number = -1;      // 进行中时间段的秒表定时器（有进行中段才起，无则停）

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

  /** 页面销毁：清掉点击平移动画的定时器，避免野定时器继续改状态 */
  aboutToDisappear(): void {
    this.stopTapAnim(false, false);
    this.stopTimer();
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

  /**
   * App 回到前台：卡片（独立 `:form` 进程）可能刚写过数据，本进程的 Preferences 缓存是旧的
   * → 直接 reload（reload 内部会先丢弃缓存、从磁盘重读）。与 onPageShow 重复触发也无副作用。
   */
  onForegroundReload(): void {
    this.reload();
  }

  /** 从数据层重新读取（整体替换数组以触发刷新） */
  private reload(): void {
    if (this.repo === null) {
      return;
    }
    // ⚠️ 先丢弃进程内 Preferences 缓存、从磁盘重读：卡片在 `:form` 进程写入后，
    //    本进程缓存不会自动失效，否则这里读到的仍是旧数据（Bug：卡片记录后 App 不更新）。
    this.repo.refresh();
    // 事件页：手动顺序（拖拽排序后的持久化顺序）
    const events: TimestampEvent[] = this.sortManual ? this.repo.getEvents() : this.repo.getEventsByRecent();
    const next: EventRow[] = [];
    events.forEach((ev: TimestampEvent) => {
      if (ev.isInterval()) {
        // 时间段：count = 段数；ongoing = 进行中的那一段（null 表示没有）
        const ongoing: TimeInterval | null = this.repo!.getOngoingInterval(ev.id);
        next.push(new EventRow(ev, this.repo!.intervalCount(ev.id), ongoing));
      } else {
        // 点时刻：count = 条数；无进行中概念
        next.push(new EventRow(ev, this.repo!.recordCount(ev.id), null));
      }
    });
    this.rows = next;
    this.syncTimer();

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
    this.editType = TYPE_POINT;
    this.showAdd = true;
  }

  private openEditSheet(ev: TimestampEvent): void {
    this.editId = ev.id;
    this.editName = ev.name;
    this.editColor = ev.color;
    this.editType = ev.type;
    this.showAdd = true;
  }

  private saveSheet(): void {
    const name: string = this.editName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入事件名称' });
      return;
    }
    if (this.editId < 0) {
      this.repo?.addEvent(name, this.editColor, this.editType);
      this.getUIContext().getPromptAction().showToast({ message: `已新建「${name}」` });
    } else {
      this.repo?.updateEvent(this.editId, name, this.editColor, this.editType);
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

  /** 时间段事件：开始 / 结束切换（对齐 EventDetail.toggleInterval） */
  private toggleInterval(ev: TimestampEvent): void {
    const ongoing: TimeInterval | null = this.repo?.getOngoingInterval(ev.id) ?? null;
    if (ongoing !== null) {
      const ok: boolean = this.repo?.stopInterval(ev.id) ?? false;
      if (ok) {
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '已结束，时长已记录' });
      }
      return;
    }
    const started: boolean = this.repo?.startInterval(ev.id) ?? false;
    if (started) {
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已开始计时' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已有进行中的时段' });
    }
  }

  // ---------- 秒表（仅存在进行中的时间段时逐秒刷新） ----------

  private syncTimer(): void {
    let hasOngoing: boolean = false;
    for (let i: number = 0; i < this.rows.length; i++) {
      if (this.rows[i].ongoing !== null) {
        hasOngoing = true;
        break;
      }
    }
    if (hasOngoing) {
      if (this.timerId < 0) {
        this.timerId = setInterval(() => {
          this.tick = this.tick + 1;
        }, 1000);
      }
    } else {
      this.stopTimer();
    }
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
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
    const isIntervalEv: boolean = ev.isInterval();
    const count: number = isIntervalEv ? (this.repo?.intervalCount(ev.id) ?? 0) : (this.repo?.recordCount(ev.id) ?? 0);
    const unit: string = isIntervalEv ? '段' : '条';
    this.getUIContext().showAlertDialog({
      title: '删除事件？',
      message: `将删除事件「${ev.name}」及其全部 ${count} ${unit}记录，无法恢复。`,
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

  /**
   * 点击 tab 切换（自绘平移动画）。
   *
   * 为什么不用 Swiper 自带的过渡动画（`changeIndex` + `.duration()`）：
   *   实测「点击 → 连抓三帧」，内容区（y<2400）三帧**逐像素完全一致** → 页面是瞬跳的，
   *   只有底栏在变（滑块在补间）。换曲线（Friction / FastOutSlowIn）、摘掉动画回调都一样；
   *   而早前那次「滑块被瞬时写入、没有逐帧改动状态」的版本反倒能看到中间位移 ——
   *   结论：**过渡期间逐帧改 tabProgress 引发的重渲染会把 Swiper 的过渡动画打断成瞬跳**。
   * 所以改为与手指拖拽完全同一套机制：`startFakeDrag` + 逐帧 `fakeDragBy`，
   * 页面位移与滑块共用同一个 p → 天生同步、也不受重渲染影响（fakeDragBy 是显式位移）。
   */
  private switchTab(i: number): void {
    if (this.curTab === i) {
      logD('Tab', `switch ${i} 被忽略（curTab 已是该页）`);
      return;
    }
    this.curTab = i;
    this.startSelfAnim(i, TAB_ANIM_MS);
  }

  /**
   * 启动一段自绘平移动画：从当前进度平滑推到 to（页面与滑块共用同一个 p）。
   * 点击切换（300ms）与松手吸附（180ms）都走这里 —— 两种场景必须是**同一套判决**，
   * 否则会出现「页面按速度甩过去了、滑块按过半规则被弹回来」的错位。
   */
  private startSelfAnim(to: number, ms: number): void {
    this.stopTapAnim(false, true); // 只清定时器，保留 fakeDrag 会话（内容不会跳）
    this.tapFrom = this.tabProgress;
    this.tapTo = to;
    this.tapAnimMs = ms;
    this.tapStartTs = Date.now();
    this.dragStartProgress = this.tapFrom; // 内容位移以动画起点为原点（driveContent 的换算基准）
    this.dragApplied = 0;
    this.islandSettling = true;            // 动画期间禁止索引/内容位置回写覆盖滑块
    if (!this.fakeDragging) {
      try {
        this.fakeDragging = this.swiperCtl.startFakeDrag();
      } catch (err) {
        this.fakeDragging = false;
      }
    }
    if (!this.fakeDragging) {
      // 模拟拖拽不可用（API < 23）：退化为直接切页 + 滑块瞬时归位
      this.islandSettling = false;
      this.tabProgress = to;
      this.curTab = to;
      try {
        this.swiperCtl.changeIndex(to);
      } catch (err) {
      }
      return;
    }
    this.tapTimer = setInterval(() => this.tickTapAnim(), TAB_ANIM_TICK_MS);
  }

  /** 自绘平移动画的一帧：easeOutCubic 缓动推进 p，同时驱动滑块与内容 */
  private tickTapAnim(): void {
    const k: number = Math.min(1, (Date.now() - this.tapStartTs) / this.tapAnimMs);
    const eased: number = 1 - Math.pow(1 - k, 3);
    const p: number = this.tapFrom + (this.tapTo - this.tapFrom) * eased;
    this.tabProgress = p;
    this.driveContent(p);
    if (k >= 1) {
      this.stopTapAnim(true, false);
    }
  }

  /**
   * 结束自绘平移动画。
   * settle=true → 收口：结束模拟拖拽、把页号**钉死**在 tapTo（`changeIndex(to, false)` 无动画落位）、
   *   进度归位并短暂屏蔽回写。钉死这一步是关键：fakeDrag 结束瞬间 Swiper 会按**残留速度**自行吸附，
   *   那套判决与我们的「过半吸附」不一致 → 不钉就会「页面甩走了、滑块弹回来」。
   * keepFake=true → 只清定时器、保留 fakeDrag 会话（用于「重开动画前」的清理，内容不跳）。
   */
  private stopTapAnim(settle: boolean, keepFake: boolean): void {
    if (this.tapTimer !== -1) {
      clearInterval(this.tapTimer);
      this.tapTimer = -1;
    }
    if (this.fakeDragging && !keepFake) {
      try {
        this.swiperCtl.stopFakeDrag();
      } catch (err) {
      }
      this.fakeDragging = false;
    }
    this.dragApplied = 0;
    if (settle) {
      this.tabProgress = this.tapTo;
      this.curTab = this.tapTo;
      try {
        this.swiperCtl.changeIndex(this.tapTo, false); // 无动画钉死页号，压掉 Swiper 自己的速度判决
      } catch (err) {
      }
      this.islandSettling = true;
      setTimeout(() => {
        this.islandSettling = false;
      }, 260);
    }
  }

  /** 点击 tab 区域切换（拖动刚结束时短暂屏蔽，避免拖拽尾巴被识别成点击） */
  private tapTab(i: number): void {
    if (Date.now() < this.suppressClickUntil) {
      return;
    }
    this.switchTab(i);
  }

  /** 点击中缝加号（同样屏蔽拖拽尾巴，否则从加号上起拖、松手会顺势弹出新建弹层） */
  private tapFab(): void {
    if (Date.now() < this.suppressClickUntil) {
      return;
    }
    this.openAddSheet();
  }

  /**
   * 底栏拖拽交互（**滑块手柄口径**，主人 2026-09-16 08:25 明确）：
   *   ① 滑块本身 1:1 跟手指走 —— 手指位移直接换算成滑块位移，跨过「一个滑块行程(含 FAB 中缝)」= 一页；
   *   ② 页面的位移沿用滑块原有比例（页面进度 = 滑块进度），通过 `driveContent` 下发给 Swiper。
   *   方向：手指右移 = 滑块右移 = 选中右侧的「时间线」。
   */
  private onIslandTouch(e: TouchEvent): void {
    if (e.touches.length === 0) {
      return;
    }
    const x: number = e.touches[0].windowX;
    if (e.type === TouchType.Down) {
      if (this.tapTimer !== -1) {
        // 手指按下：先把还在跑的自绘动画落位收口，避免动画与手指抢控制权
        this.stopTapAnim(true, false);
      }
      this.dragStartX = x;
      this.dragStartProgress = this.tabProgress;
      this.islandDragging = false;
      this.dragApplied = 0; // 新一轮拖动：已下发位移清零
    } else if (e.type === TouchType.Move) {
      const dx: number = x - this.dragStartX;
      // 超过 6vp 才判定为拖动，避免误吞正常点击
      if (!this.islandDragging && Math.abs(dx) > 6) {
        this.islandDragging = true;
        // 开启 Swiper 模拟拖拽（startFakeDrag @since 23）：让页面内容也 1:1 跟手。
        // ⚠️ 只在尚未开启时开启：已开启时 startFakeDrag() 会返回 false，若据此把标志置 false 就会「内容不动」。
        if (!this.fakeDragging) {
          try {
            this.fakeDragging = this.swiperCtl.startFakeDrag() ? true : this.swiperCtl.isFakeDragging();
          } catch (err) {
            this.fakeDragging = false; // API < 23 无此能力 → 仅滑块跟手，松手再切页
          }
        }
      }
      if (this.islandDragging) {
        // 换算基准 = 滑块自身行程：手指走完「一个 tab 宽 + FAB 中缝」= 滑块走完一页 ✓ 滑块 1:1 跟手
        const unit: number = this.tabWidth() + FAB_GAP;
        if (unit > 0) {
          let p: number = this.dragStartProgress + dx / unit;
          p = p < 0 ? 0 : (p > 1 ? 1 : p);
          this.tabProgress = p;
          // 页面位移跟着滑块进度走（同一 p，页面跨度为 pageW）→ 页面按滑块比例平移
          this.driveContent(p);
        }
      }
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      if (this.islandDragging) {
        const target: number = this.tabProgress >= 0.5 ? 1 : 0;
        this.islandDragging = false;
        this.suppressClickUntil = Date.now() + 300;
        // 一行对账日志：p = 手指算出的进度，contentP = Swiper 上报的内容进度；两者应几乎相等（联动正常）
        logD('Drag', `up p=${this.tabProgress.toFixed(3)} contentP=${this.contentP.toFixed(3)} target=${target}`);
        // 松手吸附同样**自绘**：页面与滑块共用同一个 p、同一套「过半」判决，并在收口时把页号钉死。
        // 旧写法「stopFakeDrag 交给 Swiper 自己吸附 + 滑块另外 animateTo」是两套判决 → 会错位。
        this.startSelfAnim(target, DRAG_SNAP_MS);
      } else {
        // 只是点了一下没拖动：解除 Down 时留下的屏蔽位
        this.islandSettling = false;
      }
    }
  }

  /**
   * 把 Swiper 内容推到进度 p 对应的位置（页面跟手）。
   *
   * ⚠️⚠️ 关键坑：`fakeDragBy(offset)` 是**增量**语义（每次调用把内容按 offset 再挪一段），
   *      不是「设置绝对位移」。若每次传累计值，内容会把历次累计量反复叠加 ——
   *      hilog 实测：手指 p 才 0.08，内容 contentP 已被叠到 1.0 顶死边界（然后 consumed=false），
   *      表现就是「滑块没怎么动、页面已经飞到头」的脱节感。故这里只下发**本次增量** = want - applied。
   *
   * fakeDragBy 方向：正数 = 拖向起始页（内容右移），负数 = 拖向末尾页（内容左移）。
   * 目标位移 want = -(p - 拖动起点进度) × 页宽：p 变大 → 内容左移 → 露出右侧页。
   */
  private driveContent(p: number): void {
    if (!this.fakeDragging || this.pageW <= 0) {
      return;
    }
    const want: number = -(p - this.dragStartProgress) * this.pageW;
    const delta: number = want - this.dragApplied;
    if (delta === 0) {
      return;
    }
    // 越界时 Swiper 返回 false（不消费）→ 不推进已下发量，避免留下虚假位移导致反弹不跟手
    if (this.swiperCtl.fakeDragBy(delta)) {
      this.dragApplied = want;
    }
  }

  // ============ 首尾留白：与悬浮栏等高，让首/末项停栏边，同时内容可从栏背后穿过 ============

  /** 顶部留白高度 = 顶栏内容高 + 状态栏 + 呼吸量（事件页与时间线页共用 → 两页起始高度严格一致） */
  private topPad(): number {
    return TOPBAR_CONTENT_H + this.statusBarH + PAGE_TOP_GAP;
  }

  /**
   * 顶栏「满模糊平台」末端在材质层高度中的比例。
   * 材质层高 = statusBarH + TOPBAR_CONTENT_H + TOPBAR_FADE_H；平台要盖住「状态栏 + 标题区」（标题文字
   * ink 底其实只到 statusBarH+~95，这里留 10vp 余量给收束起头），所以：
   *   ratio = (statusBarH + TOPBAR_CONTENT_H − 10) / 材质层高
   * 用运行时值计算，换设备（状态栏高度不同）也不会让标题区落进收束段。
   */
  private fadePlatformRatio(): number {
    const body: number = this.statusBarH + TOPBAR_CONTENT_H;
    const total: number = body + TOPBAR_FADE_H;
    if (total <= 0) {
      return 0.7;
    }
    const r: number = (body - 10) / total;
    return r < 0 ? 0 : (r > 0.95 ? 0.95 : r);
  }

  /** 收束段内第 k 点（0~1）在材质层高度中的比例：从平台末端线性铺到材质底边 */
  private fadeTaperAt(k: number): number {
    const r: number = this.fadePlatformRatio();
    return r + (1 - r) * k;
  }

  /** 底部留白高度 = 底栏占位 + 小白条 */
  private tlScroller: Scroller = new Scroller();

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
      // ---------- 内容层：双页撑满全屏，滚动内容从悬浮玻璃栏底下穿过 ----------
      // 注：时间轴的「超长灰线底」已挪进 TimelinePage 内部（见该 Builder），不再挂在根 Stack —— 详见那里的注释。
      // ⚠️ 外层 Tabs 只为「沉浸光感生效范围」服务：官方文档明确 uiMaterial.systemMaterial 仅在
      //    Navigation/NavDestination 标题栏、或「横向 Tabs + barPosition=End」的底部 TabBar 内生效，
      //    其他区域系统直接判 Material inactive: out of scope（只剩静态高斯模糊，不跟随系统光感控件）。
      //    故把底部胶囊岛挂成 Tabs 的 tabBar（只放 1 个 TabContent → 单 tab 占满整条 bar 宽）；
      //    页面切换与跟手进度仍由内部 Swiper 承担，Tabs 单页不抢横向滑动手势，两者互不冲突。
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          Swiper(this.swiperCtl) {
            this.EventsPage()
            this.TimelinePage()
          }
      // ⚠️ 不要绑 `.index(this.curTab)`：点击切换要靠 changeIndex 的平移动画，绑定后动画途中重渲染会把旧页码写回去 → 变成瞬跳。
      //    页码以 Swiper 自身为准，通过 onChange 回写 curTab。
      .loop(false)
      .indicator(false)
      .duration(220) // 手势翻页/吸附时长（点击切换走自绘动画，不用它）
      .curve(Curve.Friction)
      .width('100%')
      .height('100%')
      .onContentDidScroll((selectedIndex: number, index: number, position: number, mainAxisLength: number) => {
        if (index !== 0) {
          return;
        }
        // 对账探针：记录 Swiper 自己上报的内容进度（拖拽/吸附期间也记，便于核对是否与手指一致）
        const clampP: number = position < 0 ? -position : position;
        const norm: number = (clampP > 1 && mainAxisLength > 0) ? clampP / mainAxisLength : clampP;
        this.contentP = norm < 0 ? 0 : (norm > 1 ? 1 : norm);
        // 拖拽底栏滑块 / 吸附动画期间由手指驱动进度，禁止内容位置回写 tabProgress（否则进度被拉回整数、滑块不跟手）
        if (this.islandDragging || this.islandSettling) {
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
        if (this.islandDragging) {
          return;
        }
        if (this.islandSettling) {
          // 点击切换的过渡动画进行中：滑块由 switchTab 的 animateTo 补间，这里不得瞬跳覆盖
          // 屏蔽位由 animateTo.onFinish / 兜底定时器解除，不在这里清
          return;
        }
        this.tabProgress = i; // 兜底：静止时进度与页号一致
      })
        }
        .tabBar(this.BottomBar())
      }
      // barOverlap：TabBar 悬浮叠在内容之上（保留「内容从玻璃岛背后滚过」的视觉）；
      // barHeight = 胶囊岛 56 + 下边距 12 + 小白条导航区高；bar 底透明，避免系统默认底色挡住内容。
      .barOverlap(true)
      .barHeight(ISLAND_H + 12 + this.navBarH)
      // ⚠️ 必须显式清掉 Tabs 自带 bar 背景：系统在 API 26 会给底部 TabBar 铺一层**矩形**系统材质，
      //    叠加在胶囊岛外侧就变成主人看到的「方形遮罩」。置透明 + NONE 后只剩胶囊岛自己的玻璃。
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barMode(BarMode.Fixed)
      .width('100%')
      .height('100%')

      // ---------- 顶栏：独立悬浮贴顶（Stack 内位于内容层之上，只占自身高度，不遮挡下方列表点击） ----------
      // 顶栏（标题 + ⋮）：实时高斯模糊玻璃，透出下方滚动内容。
      // ⚠️ 顶栏无法走 systemMaterial：官方限定沉浸光感只在 Navigation 标题栏 / 底部 TabBar 生效（见 Theme.ets 注释），
      //    硬调会被判 out of scope → 材质失效且背景全透。故这里用 backgroundEffect 做「观感等效」的液态玻璃，
      //    另用底部渐隐带消解硬边，避免时间线内容被生硬地「切」进模糊区。
      Stack({ alignContent: Alignment.TopStart }) {
        // ① 材质层：实时高斯模糊 + 材质色。
        //    关键在 linearGradientBlur（官方 linearGradientBlur @since 12）：给「材质层自身」按竖直方向
        //    渐减模糊强度 —— 上半段保持实模糊、下半段逐步化开到 0，于是模糊区的下边缘不再是一条硬切线，
        //    内容滚入顶栏时是「渐渐糊掉」而不是「到某条线突然糊」。内容层是兄弟节点，不受此模糊影响（标题始终清晰）。
        //    ⚠️ 只做「实时模糊 + 极低 tint」，**不加投影/描边**：实测设置页顶栏底色与页面背景完全一致
        //       （标题区/下方/卡片缝隙多点采样均 #EFF3F6，无阴影无描边）→ 投影会在模糊区下缘压出一条暗带，
        //       正好与「不生硬」相反。
        Column()
          .width('100%')
          .height('100%')
          // 纯模糊、不加 tint（主人 2026-09-16 拍板对齐第一方）：栏底与页面背景同色，只把背后内容糊掉。
          //
          // ⚠️ 模糊「过渡生硬」的两条根因（逐行像素实测）：
          //   ① `backgroundEffect` 的**均匀背板模糊在材质层底边是硬截断**的 —— 越靠边它越明显；
          //      实测红色细线峰值在 y440→520 只用了 ~23vp 就从 32 冲到 170（锐利态），等于「一刀切」。
          //      对策：**背板模糊半径下调 20 → 10**，把这条硬边的高度砍半；主模糊改由带梯度的 linearGradientBlur 承担。
          //   ② 单段线性 ramp 收得太快 → 改成多段渐进（模糊系数随高度平缓衰减），拖长过渡区间。
          // 背板模糊只给 3：它的作用是「把背后的内容捕获进材质层」，好让 linearGradientBlur 有的可糊；
          // 它本身是均匀模糊、底边必然硬截断，**半径越小这条硬边的幅度越小**（实测半径 20→10 已减弱一半）。
          // 主模糊全部交给可以随高度渐变的 linearGradientBlur（半径 42）。
          .attributeModifier(new GlassColumnModifier(GLASS_BLUR_ONLY, 3))
          // 半径 42（强度只增不减）。
          // ⚠️ 平台末端必须**按当前设备的状态栏高度动态算**（见 fadePlatformRatio）：写死比例会因
          //    状态栏高度不同而错位 —— 一旦平台末端低于标题区底边，标题下半部就落进收束段、糊度被削弱。
          .linearGradientBlur(42, {
            // 平台 0~fadePlatformRatio()：盖住状态栏 + 标题区（留 10vp 余量）→ 标题背后始终是「实模糊」；
            // 之后 5 段收束（1 → .75 → .25 → 0）走完剩下的渐隐区 → 长而软，不硬切。
            // ⚠️ 段数不是越多越好：实测 11 段余弦 ramp 反而比 5 段更「不糊」（疑似实现内部量化），故用 5 段。
            fractionStops: [
              [1, 0.0],
              [1, this.fadePlatformRatio()],
              [0.75, this.fadeTaperAt(0.33)],
              [0.25, this.fadeTaperAt(0.72)],
              [0, 1.0]
            ],
            direction: GradientDirection.Bottom
          })

        // ② 内容层：标题 + ⋮（高度只到状态栏+内容高，保证文字不被压到渐隐区里）
        Row() {
          Column() {
            Text('时间戳记录器')
              .fontSize(24) // 对齐鸿蒙第一方（设置页）大标题：ink 高 ≈23.4vp → fontSize 24
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
        // left 16：与列表卡片左缘同一条竖线（设置页标题 x=56px=16vp，与其卡片对齐）
        .padding({ left: 16, right: 8, top: this.statusBarH, bottom: 8 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(TOPBAR_CONTENT_H + this.statusBarH + TOPBAR_FADE_H)

      // ---------- 底栏：已上移为 Tabs 的 tabBar（见上方注释），此处不再重复挂载 ----------

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
    .onAreaChange((_oldVal: Area, newVal: Area) => {
      // 页面宽度（vp）：拖拽底栏滑块时用它换算内容位移，同时供时间轴灰线跟随页面平移
      const w: number = (typeof newVal.width === 'number') ?
        newVal.width : parseFloat(newVal.width.toString());
      if (!Number.isNaN(w) && w > 0) {
        this.pageW = w;
      }
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
          Text('点击底部中间的 ＋ 添加一个事件') // 空态引导：FAB 在底部正中间（曾误写「右下角」）
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
          // ⚠️ key 必须含进行中标志：点「结束」时段数不变，仅 ongoing 从非 null 变 null，
          // 若 key 只含 id-count 则不变化 → ForEach 复用旧组件，胶囊文案停在「结束」不刷新
          }, (row: EventRow) => `${row.ev.id}-${row.count}-${row.ongoing === null ? 0 : 1}`)
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

  /** 卡片副标题：点时刻=共 N 条；时间段=共 N 段（进行中追加「· 进行中 已 xxx」）。
   *  读取 this.tick 以建立依赖：秒表每 1s 触发重渲染，进行中的「已 xxx」随之刷新。 */
  private cardSubtitle(row: EventRow): string {
    const beat: number = this.tick; // 建立 tick 依赖（不实际参与计算，避免被编译器优化掉）
    if (row.ev.isInterval()) {
      if (row.count === 0) {
        return '暂无时段';
      }
      const base: string = `共 ${row.count} 段`;
      if (row.ongoing !== null) {
        return `${base} · 进行中 ${formatDuration(row.ongoing.duration() + (beat - beat))}`;
      }
      return base;
    }
    if (row.count === 0) {
      return '暂无记录';
    }
    return `共 ${row.count} 条`;
  }

  /** 时间线区间条目的第二行文案（点时刻不进此方法）。读取 this.tick 建立依赖：进行中的「已 xxx」逐秒刷新 */
  private tlIntervalSecondLine(it: TimeInterval): string {
    const beat: number = this.tick; // 建立 tick 依赖（不参与计算，避免被优化掉）
    if (it.isOngoing()) {
      return `进行中 · 已 ${formatDuration(it.duration() + (beat - beat))}`;
    }
    return `${TimeFormat.hm(it.start)} → ${TimeFormat.hm(it.end ?? it.start)} · ${formatDuration(it.duration())}`;
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
        Text(this.cardSubtitle(row))
          .fontSize(13)
          .fontColor(this.theme().onSurfaceVariant)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      .onClick(() => this.openDetail(row.ev.id))

        // ⋮（编辑 / 删除）
        // ⚠️ 热区 40×40vp：满足《通用应用 UX 体验标准》2.1.3.3「可点击热区不得小于 40vp×40vp」（必须级）
        Column() {
          this.MoreVertIcon(this.theme().onSurfaceVariant)
        }
        .width(40)
        .height(40)
        .margin({ left: 6 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.showEventMenu(row.ev))

      // 快捷记录胶囊（事件色 + 白色图标）。点时刻=记一条；时间段=开始/结束切换
      Row() {
        if (row.ev.isInterval()) {
          if (row.ongoing !== null) {
            // 进行中：方块「停止」图标 + 文案
            Rect()
              .width(12)
              .height(12)
              .borderRadius(3)
              .fill(this.theme().white)
            Text('结束')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().white)
              .margin({ left: 6 })
          } else {
            this.PlusIcon(13, 1.8, this.theme().white)
            Text('开始')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().white)
              .margin({ left: 6 })
          }
        } else {
          this.PlusIcon(13, 1.8, this.theme().white)
          Text(`${row.count}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().white)
            .margin({ left: 6 })
        }
      }
      .height(36)
      .constraintSize({ minWidth: 62 })
      .padding({ left: 12, right: 14 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor(colorToHex(row.ev.color))
      .borderRadius(18)
      .margin({ left: 8 })
      .onClick(() => {
        if (row.ev.isInterval()) {
          this.toggleInterval(row.ev);
        } else {
          this.recordOnce(row.ev);
        }
      })
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
    Stack({ alignContent: Alignment.TopStart }) {
      // ---------- 时间轴「超长灰线底」----------
      // x=26vp：列表 padding 16 + 线区 Stack(22) 内线中心 11 - 半宽 1，与时间轴竖线严格对齐。
      // ⚠️ 必须挂在**页面内部**（TimelinePage 自己的 Stack 里），而不是根 Stack：
      //    它是页面的一部分，左右滑页 / 滚到尽头继续左滑的 overscroll 弹性位移时，都跟着页面一起走。
      //    挂在根 Stack 时位置只能由「钳制到 0~1 的 tabProgress」推出来 —— 超出末页继续左滑时
      //    Swiper 内容弹性左移、这条线却钉在 x=26 不动，就露出主人看到的「多余的灰色线」。
      Column()
        .width(2)
        .height('100%')
        .backgroundColor(this.theme().outline)
        .position({ x: 26, y: 0 })

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
              }, (r: TimelineRecord) => `${r.eventId}-${r.millis}-${r.interval === null ? -1 : (r.interval.end ?? -1)}`)
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
          if (r.interval !== null) {
            // 时间段：开始 → 结束 · 时长；进行中显示「进行中 · 已 xxx」（文案在方法内计算，含 tick 依赖）
            Text(this.tlIntervalSecondLine(r.interval))
              .fontSize(12)
              .fontColor(r.interval.isOngoing() ? this.theme().primary : this.theme().onSurfaceVariant)
              .margin({ top: 3 })
          } else {
            Text(TimeFormat.short(r.millis))
              .fontSize(12)
              .fontColor(this.theme().onSurfaceVariant)
              .margin({ top: 3 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (r.interval !== null) {
          Text(TimeFormat.relative(r.interval.start))
            .fontSize(13)
            .fontColor(this.theme().primary)
            .margin({ left: 10 })
            .maxLines(1)
        } else {
          Text(TimeFormat.relative(r.millis))
            .fontSize(13)
            .fontColor(this.theme().primary)
            .margin({ left: 10 })
            .maxLines(1)
        }
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
        // ⚠️ 本 builder 现在挂在 Tabs.tabBar 上：根 Column 需显式撑满 bar 高度，
        //    否则 tabBar 内自适应高度会让胶囊岛贴顶、底部 navBar 留白丢失。
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
          .onClick(() => this.tapTab(0))

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
            .onClick(() => this.tapFab())
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
          .onClick(() => this.tapTab(1))
        }
        .width('100%')
        .height('100%')
        .padding({ left: 6, right: 6 })
      }
      .width('100%')
      .height(ISLAND_H)
      // 液态玻璃悬浮岛：本组件挂在 Tabs.tabBar 上（= 系统认定的底部 TabBar），inScope=true
      // → API 26 走 ImmersiveMaterial 真·跟随系统沉浸光感；范围外/低版本降级实时高斯模糊。
      .attributeModifier(new GlassStackModifier(this.theme().glassBar, 28, true))
      .borderRadius(28)
      // ⚠️ systemMaterial 的材质层按组件矩形渲染、**不跟随 borderRadius** → 不加 clip 会露出方形玻璃块。
      //    clip(true) 让材质/背景一起按 28 圆角裁剪，胶囊岛才是真·悬浮圆角岛。
      .clip(true)
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
    .height('100%')
    .padding({ bottom: this.navBarH })
    // 底栏拖拽：按住胶囊岛横向拖动即可切换页面（滑块 1:1 跟手，松手吸附）
    .onTouch((e: TouchEvent) => this.onIslandTouch(e))
  }

  // ==================== 新建 / 编辑事件弹层 ====================

  /** 类型选择（点时刻 / 时间段），对齐 Android dialog_edit_event 的 Chip 与 EventDetail.TypeChips */
  @Builder
  TypeChips() {
    Row() {
      this.TypeChip('点时刻', TYPE_POINT)
      this.TypeChip('时间段', TYPE_INTERVAL)
    }
    .width('100%')
    .margin({ top: 16, bottom: 4 })
  }

  @Builder
  TypeChip(label: string, type: number) {
    Text(label)
      .fontSize(14)
      .fontColor(this.editType === type ? '#FFFFFF' : this.theme().onSurface)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(this.editType === type ? this.theme().primary : this.theme().inputBg)
      .margin({ right: 10 })
      .onClick(() => {
        this.editType = type;
      })
  }

  @Builder
  AddSheet() {
    Column() {
      // ⚠️ 卡片外包 Scroll 并限高：色盘展开 hex 面板后内容会超过屏高，必须可滚动
      Scroll() {
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

        this.TypeChips()

        Text('选择颜色')
          .fontSize(13)
          .fontColor(this.theme().onSurfaceVariant)
          .width('100%')
          .margin({ top: 16, bottom: 4 })

        ColorPickerPanel({
          selected: this.editColor,
          onPick: (c: number) => {
            this.editColor = c;
          }
        })
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
      .constraintSize({ maxHeight: '92%' })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme().mask)
  }
}
