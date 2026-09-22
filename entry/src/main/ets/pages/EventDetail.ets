import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { picker } from '@kit.CoreFileKit';
import fileIo from '@ohos.file.fs';
import pasteboard from '@ohos.pasteboard';
import { EventRepository } from '../data/EventRepository';
import { syncAllForms } from '../util/FormSync';
import {
  colorToHex,
  formatDuration,
  TimeInterval,
  TimestampEvent,
  TYPE_INTERVAL,
  TYPE_POINT
} from '../model/TimestampEvent';
import { ColorPickerPanel } from '../components/ColorPickerPanel';
import { TimeFormat } from '../util/TimeFormat';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 事件详情页（对齐 Android EventDetailActivity + activity_event_detail.xml + item_record.xml）。
 *
 * 支持两种事件形态（对齐 Android type 0/1）：
 * - **点时刻**：「记录此刻」写毫秒时间戳；列表显示序号 / 完整时间 / Unix 秒。
 * - **时间段**：「开始 / 结束」成对写入 `intervals_<id>`；进行中的段显示秒表，列表显示起止与时长。
 *
 * 其余：撤销 / 复制 / 长按删单条 / 顶栏批量管理（多选删除）/ ⋮ 菜单（编辑、导出、清空、删除、统计、时间线）。
 */
@Entry
@Component
struct EventDetail {
  @State eventId: number = 0;
  @State ev: TimestampEvent | null = null;
  @State records: number[] = [];
  @State intervals: TimeInterval[] = [];
  @State ongoing: TimeInterval | null = null;
  @State count: number = 0;
  @State last: number = -1;
  /** 秒表驱动：每 1s +1 触发重渲染，仅进行中的时间段需要 */
  @State tick: number = 0;
  // 批量选择模式
  @State selectMode: boolean = false;
  @State selected: number[] = [];
  // 编辑事件弹层
  @State showEdit: boolean = false;
  @State editName: string = '';
  @State editColor: number = 0;
  @State editType: number = TYPE_POINT;
  @StorageProp('isDark') isDark: boolean = false;
  /** App 回到前台时由 EntryAbility.onForeground 递增 → 触发从磁盘重载（卡片进程可能已写入） */
  @StorageProp('fgReloadTick') @Watch('onForegroundReload') fgReloadTick: number = 0;

  private repo: EventRepository | null = null;
  private timerId: number = -1;

  /** 当前语义色板（ArkUI struct 内必须用普通方法，不能用 getter） */
  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  /** 是否时间段类型事件 */
  private isIntervalEvent(): boolean {
    return this.ev !== null && this.ev.isInterval();
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.repo = new EventRepository(ctx);
    this.repo.onChanged = () => syncAllForms(ctx);
    const params = router.getParams() as Record<string, Object>;
    this.eventId = params['eventId'] as number;
    this.reload();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  onPageHide(): void {
    this.stopTimer();
  }

  onPageShow(): void {
    this.reload();
  }

  /** App 回到前台：卡片（独立 `:form` 进程）可能刚写过数据 → 直接从磁盘重载 */
  onForegroundReload(): void {
    this.reload();
  }

  private reload(): void {
    if (this.repo === null) {
      return;
    }
    // ⚠️ 先丢弃进程内 Preferences 缓存、从磁盘重读：卡片由独立 `:form` 进程写入，
    //    本进程缓存不会自动失效（否则详情页在卡片记录后仍显示旧列表）。
    this.repo.refresh();
    this.ev = this.repo.getEvent(this.eventId);
    if (this.isIntervalEvent()) {
      this.intervals = this.repo.getIntervals(this.eventId);
      this.ongoing = this.repo.getOngoingInterval(this.eventId);
      this.count = this.intervals.length;
      this.last = this.intervals.length > 0 ? this.intervals[this.intervals.length - 1].start : -1;
    } else {
      this.records = this.repo.getRecords(this.eventId);
      this.ongoing = null;
      this.count = this.records.length;
      const l: number | null = this.repo.lastRecord(this.eventId);
      this.last = l === null ? -1 : l;
    }
    this.syncTimer();
  }

  // ---------- 秒表（仅进行中的时间段需要逐秒刷新） ----------

  private syncTimer(): void {
    if (this.ongoing !== null) {
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

  // ---------- 主操作 ----------

  /** 主按钮：点时刻 = 记一条；时间段 = 开始 / 结束切换 */
  private onPrimaryAction(): void {
    if (this.isIntervalEvent()) {
      this.toggleInterval();
    } else {
      this.recordOnce();
    }
  }

  private recordOnce(): void {
    const m: number = this.repo?.addRecord(this.eventId) ?? 0;
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: `已记录 ${TimeFormat.hm(m)}` });
  }

  private toggleInterval(): void {
    if (this.ongoing !== null) {
      const ok: boolean = this.repo?.stopInterval(this.eventId) ?? false;
      if (ok) {
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '已结束，时长已记录' });
      }
      return;
    }
    const started: boolean = this.repo?.startInterval(this.eventId) ?? false;
    if (started) {
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已开始计时' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已有进行中的时段' });
    }
  }

  private undoLast(): void {
    let ok: boolean = false;
    if (this.isIntervalEvent()) {
      ok = this.repo?.undoLastInterval(this.eventId) ?? false;
    } else {
      ok = this.repo?.undoLast(this.eventId) ?? false;
    }
    if (ok) {
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已撤销上一条' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '没有可撤销的记录' });
    }
  }

  // ---------- 复制 / 删除 ----------

  private copyRecord(m: number): void {
    const it: TimeInterval | null = this.findInterval(m);
    let text: string = '';
    if (it !== null) {
      if (it.isOngoing()) {
        text = `${TimeFormat.full(it.start)}  起（进行中，已 ${formatDuration(it.duration())}）`;
      } else {
        text = `${TimeFormat.full(it.start)} → ${TimeFormat.full(it.end ?? it.start)}  (时长 ${formatDuration(it.duration())})`;
      }
    } else {
      text = `${TimeFormat.full(m)}  (Unix 秒: ${Math.floor(m / 1000)})`;
    }
    const pb = pasteboard.getSystemPasteboard();
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pb.setData(data);
    this.getUIContext().getPromptAction().showToast({ message: '已复制时间' });
  }

  private findInterval(start: number): TimeInterval | null {
    let found: TimeInterval | null = null;
    for (let i: number = 0; i < this.intervals.length; i++) {
      if (this.intervals[i].start === start) {
        found = this.intervals[i];
      }
    }
    return found;
  }

  private deleteRecordAt(pos: number): void {
    if (this.isIntervalEvent()) {
      const it: TimeInterval = this.intervals[pos];
      this.confirmDelete('删除时段', '确定删除这个时间段吗？', () => {
        this.repo?.deleteIntervalByStart(this.eventId, it.start);
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      });
      return;
    }
    this.confirmDelete('删除记录', '确定删除这条记录吗？', () => {
      this.repo?.deleteRecord(this.eventId, pos);
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
    });
  }

  private confirmDelete(title: string, message: string, onOk: () => void): void {
    this.getUIContext().showAlertDialog({
      title: title,
      message: message,
      buttons: [
        { value: '删除', fontColor: this.theme().danger, action: onOk },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  private deleteEvent(): void {
    this.getUIContext().showAlertDialog({
      title: '删除事件',
      message: `确定删除「${this.ev?.name ?? ''}」及其全部记录吗？此操作不可恢复。`,
      buttons: [
        {
          value: '删除',
          fontColor: this.theme().danger,
          action: () => {
            this.repo?.deleteEvent(this.eventId);
            router.back();
          }
        },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  // ---------- CSV 导出 ----------

  private buildCsv(): string {
    if (this.isIntervalEvent()) {
      const lines: string[] = ['序号,开始时间,结束时间,时长秒'];
      for (let i: number = 0; i < this.intervals.length; i++) {
        const it: TimeInterval = this.intervals[i];
        const endText: string = it.isOngoing() ? '进行中' : TimeFormat.full(it.end ?? it.start);
        lines.push(`${i + 1},${TimeFormat.full(it.start)},${endText},${Math.floor(it.duration() / 1000)}`);
      }
      return lines.join('\n');
    }
    const lines: string[] = ['序号,时间,Unix秒'];
    for (let i: number = 0; i < this.records.length; i++) {
      const m: number = this.records[i];
      lines.push(`${i + 1},${TimeFormat.full(m)},${Math.floor(m / 1000)}`);
    }
    return lines.join('\n');
  }

  private sanitize(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_');
  }

  private exportCsv(): void {
    if (this.ev === null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context;
    const documentPicker = new picker.DocumentViewPicker(ctx);
    const fileName: string = `${this.sanitize(this.ev.name)}.csv`;
    documentPicker.save({
      newFileNames: [fileName]
    }).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      try {
        const file = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        // 对齐 Android：写 UTF-8 BOM，Excel 直接打开中文不乱码
        fileIo.writeSync(file.fd, '\uFEFF' + this.buildCsv());
        fileIo.closeSync(file);
        this.getUIContext().getPromptAction().showToast({ message: 'CSV 已导出' });
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
      }
    }).catch(() => {});
  }

  /** 清空该事件全部记录（两种形态各自清理） */
  private clearAllRecords(): void {
    const unit: string = this.isIntervalEvent() ? '段' : '条';
    this.getUIContext().showAlertDialog({
      title: '清空记录',
      message: `确定清空「${this.ev?.name ?? ''}」的全部 ${this.count} ${unit}记录吗？此操作不可恢复。`,
      buttons: [
        {
          value: '清空',
          fontColor: this.theme().danger,
          action: () => {
            if (this.isIntervalEvent()) {
              this.repo?.clearIntervals(this.eventId);
            } else {
              this.repo?.clearRecords(this.eventId);
            }
            this.reload();
            this.getUIContext().getPromptAction().showToast({ message: '已清空记录' });
          }
        },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  // ---------- 批量选择（对齐 Android selectionBar） ----------

  private enterSelectMode(): void {
    if (this.count === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无记录' });
      return;
    }
    this.selected = [];
    this.selectMode = true;
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selected = [];
  }

  private isSelected(key: number): boolean {
    return this.selected.includes(key);
  }

  private toggleSelect(key: number): void {
    const next: number[] = this.selected.slice();
    const idx: number = next.indexOf(key);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(key);
    }
    this.selected = next;
  }

  /** 当前形态下全部条目的 key 集合（点记录 = 毫秒值；时间段 = start 值） */
  private allKeys(): number[] {
    if (this.isIntervalEvent()) {
      const out: number[] = [];
      for (let i: number = 0; i < this.intervals.length; i++) {
        out.push(this.intervals[i].start);
      }
      return out;
    }
    return this.records.slice();
  }

  private toggleSelectAll(): void {
    this.selected = this.selected.length === this.count ? [] : this.allKeys();
  }

  private deleteSelected(): void {
    if (this.selected.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '未选择记录' });
      return;
    }
    const n: number = this.selected.length;
    const target: number[] = this.selected.slice();
    this.getUIContext().showAlertDialog({
      title: '删除选中记录',
      message: `确定删除选中的 ${n} 条记录吗？`,
      buttons: [
        {
          value: '删除',
          fontColor: this.theme().danger,
          action: () => {
            if (this.isIntervalEvent()) {
              this.repo?.deleteIntervals(this.eventId, target);
            } else {
              this.repo?.deleteRecords(this.eventId, target);
            }
            this.exitSelectMode();
            this.reload();
            this.getUIContext().getPromptAction().showToast({ message: `已删除 ${n} 条` });
          }
        },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  // ---------- 编辑事件 ----------

  private openEdit(): void {
    if (this.ev === null) {
      return;
    }
    this.editName = this.ev.name;
    this.editColor = this.ev.color;
    this.editType = this.ev.type;
    this.showEdit = true;
  }

  private saveEdit(): void {
    const name: string = this.editName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '名称不能为空' });
      return;
    }
    this.repo?.updateEvent(this.eventId, name, this.editColor, this.editType);
    this.showEdit = false;
    this.reload();
    const ctx = this.getUIContext().getHostContext() as common.Context;
    syncAllForms(ctx);
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
  }

  private gotoStats(): void {
    // 对齐 Android EXTRA_FOCUS_EVENT_ID：进统计页即聚焦本事件
    router.pushUrl({ url: 'pages/Stats', params: { focusEventId: this.eventId } });
  }

  private gotoTimeline(): void {
    // 回主页并请求打开时间线 tab（Index.onPageShow 读取后清除）
    AppStorage.setOrCreate('detailOpenTimeline', true);
    router.back();
  }

  /** 详情 ⋮ 菜单（对齐 Android 七项：编辑 / 导出 / 清空 / 删除 / 统计 / 时间线） */
  private showDetailMenu(): void {
    this.getUIContext().showAlertDialog({
      title: this.ev?.name ?? '操作',
      message: '选择操作',
      buttons: [
        { value: '编辑事件', fontColor: this.theme().onSurface, action: () => this.openEdit() },
        { value: '导出记录 CSV', fontColor: this.theme().primary, action: () => this.exportCsv() },
        { value: '清空记录', fontColor: this.theme().onSurface, action: () => this.clearAllRecords() },
        { value: '删除事件', fontColor: this.theme().danger, action: () => this.deleteEvent() },
        { value: '统计', fontColor: this.theme().onSurface, action: () => this.gotoStats() },
        { value: '时间线', fontColor: this.theme().onSurface, action: () => this.gotoTimeline() },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  // ---------- 文案 ----------

  private primaryLabel(): string {
    if (this.isIntervalEvent()) {
      if (this.ongoing !== null) {
        // 读取 tick 以建立依赖：秒表每 1s 触发重渲染，duration() 随之刷新
        const beat: number = this.tick;
        return `结束 · 已 ${formatDuration(this.ongoing.duration() + (beat - beat))}`;
      }
      return '开始计时';
    }
    return '记录此刻';
  }

  private summaryText(): string {
    if (this.isIntervalEvent()) {
      if (this.count === 0) {
        return '暂无时段';
      }
      const beat: number = this.tick; // 同上：建立 tick 依赖
      const total: number = (this.repo?.totalIntervalDuration(this.eventId) ?? 0) + (beat - beat);
      const base: string = `共 ${this.count} 段 · 总时长 ${formatDuration(total)}`;
      return this.ongoing !== null ? `${base} · 进行中 ${formatDuration(this.ongoing.duration())}` : base;
    }
    return this.count === 0 ? '暂无记录' : `共 ${this.count} 条 · 最近 ${TimeFormat.relative(this.last)}`;
  }

  // ---------- 图标与子组件 ----------

  /** 时钟图标（对齐 Android ic_clock，白色描边 + 两指针） */
  @Builder
  ClockIcon() {
    Stack() {
      Circle()
        .width(20)
        .height(20)
        .fill('#00000000')
        .stroke('#FFFFFF')
        .strokeWidth(1.8)
      Rect() // 指向 12
        .width(1.8)
        .height(7)
        .fill('#FFFFFF')
        .borderRadius(1)
        .offset({ y: -3.2 })
      Rect() // 指向 3
        .width(7)
        .height(1.8)
        .fill('#FFFFFF')
        .borderRadius(1)
        .offset({ x: 3.2 })
    }
    .width(22)
    .height(22)
  }

  /** 批量管理入口图标（对齐 Android ic_check_box：方框 + 对勾） */
  @Builder
  BatchEntryIcon() {
    Stack() {
      Rect()
        .width(20)
        .height(20)
        .radius(4)
        .fill('#00000000')
        .stroke(this.theme().onSurfaceVariant)
        .strokeWidth(1.8)
      Text('✓')
        .fontSize(14)
        .fontColor(this.theme().onSurfaceVariant)
    }
    .width(44)
    .height(44)
    .onClick(() => this.enterSelectMode())
  }

  /** 行内勾选框（批量模式） */
  @Builder
  RowCheckBox(key: number) {
    Stack() {
      if (this.isSelected(key)) {
        Rect().width(20).height(20).radius(4).fill(this.theme().primary)
        Text('✓').fontSize(14).fontColor('#FFFFFF')
      } else {
        Rect()
          .width(20)
          .height(20)
          .radius(4)
          .fill('#00000000')
          .stroke(this.theme().outline)
          .strokeWidth(1.6)
      }
    }
    .width(28)
    .height(28)
  }

  /** 底部批量操作栏（对齐 Android selectionBar） */
  @Builder
  SelectionBar() {
    Row() {
      Text(this.selected.length === this.count && this.count > 0 ? '取消全选' : '全选')
        .fontSize(14)
        .fontColor(this.theme().primary)
        .padding({ left: 8, right: 8, top: 10, bottom: 10 })
        .onClick(() => this.toggleSelectAll())
      Text(`已选 ${this.selected.length} 条`)
        .fontSize(14)
        .fontColor(this.theme().onSurface)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(`删除 ${this.selected.length}`)
        .fontSize(14)
        .fontColor(this.theme().danger)
        .padding({ left: 8, right: 4, top: 10, bottom: 10 })
        .onClick(() => this.deleteSelected())
      Text('取消')
        .fontSize(14)
        .fontColor(this.theme().onSurfaceVariant)
        .padding({ left: 8, right: 12, top: 10, bottom: 10 })
        .onClick(() => this.exitSelectMode())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 18 })
    .backgroundColor(this.theme().glassToolbar)
    .border({ width: { top: 1 }, color: this.theme().divider })
  }

  /** 类型选择（点时刻 / 时间段），对齐 Android dialog_edit_event 的 Chip */
  @Builder
  TypeChips() {
    Row() {
      this.TypeChip('点时刻', TYPE_POINT)
      this.TypeChip('时间段', TYPE_INTERVAL)
    }
    .width('100%')
    .margin({ bottom: 16 })
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

  /** 编辑事件弹层（改名 + 改色 + 改类型，对齐 Android showEditDialog） */
  @Builder
  EditSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme().mask)
        .onClick(() => {
          this.showEdit = false;
        })
      // 面板（⚠️ 内容区可滚动：色盘展开 hex 面板后总高会超过屏幕，按钮必须固定可见）
      Column() {
        Scroll() {
          Column() {
            Text('编辑事件')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().onSurface)
              .width('100%')
              .margin({ bottom: 14 })

            TextInput({ text: this.editName, placeholder: '事件名称' })
              .fontSize(16)
              .fontColor(this.theme().onSurface)
              .backgroundColor(this.theme().inputBg)
              .borderRadius(12)
              .height(48)
              .margin({ bottom: 12 })
              .onChange((v: string) => {
                this.editName = v;
              })

            this.TypeChips()

            ColorPickerPanel({
              selected: this.editColor,
              onPick: (c: number) => {
                this.editColor = c;
              }
            })
              .margin({ bottom: 6 })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

        Row() {
          Text('取消')
            .fontSize(16)
            .fontColor(this.theme().onSurfaceVariant)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .height(46)
            .borderRadius(23)
            .backgroundColor(this.theme().cancelBtn)
            .onClick(() => {
              this.showEdit = false;
            })
          Text('保存')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .height(46)
            .borderRadius(23)
            .backgroundColor(this.theme().primary)
            .margin({ left: 12 })
            .onClick(() => this.saveEdit())
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('100%')
      .height('82%')
      .padding(20)
      .padding({ bottom: 30 })
      .backgroundColor(this.theme().glassMenu)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // ---------- 顶栏（玻璃）：返回 + 纯文本标题 + 批量入口 + ⋮ ----------
        Row() {
          Text('←')
            .fontSize(26)
            .fontColor(this.theme().onSurface)
            .padding({ left: 16, right: 8, top: 6, bottom: 6 })
            .onClick(() => router.back())

          Text(this.ev?.name ?? '')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().onSurface)
            .layoutWeight(1)
            .margin({ left: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (!this.selectMode) {
            this.BatchEntryIcon()
          }
          Text('⋮')
            .fontSize(24)
            .fontColor(this.theme().onSurfaceVariant)
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick(() => this.showDetailMenu())
        }
        .width('100%')
        .padding({ left: 4, right: 12, top: 30, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

        // ---------- 主按钮（点时刻 = 记录此刻；时间段 = 开始 / 结束 + 秒表） ----------
        Button() {
          Row() {
            this.ClockIcon()
            Text(this.primaryLabel())
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .margin({ left: 10 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(64)
        .fontColor('#FFFFFF')
        .backgroundColor(this.ev !== null ? colorToHex(this.ev.color) : this.theme().primary)
        .borderRadius(32)
        .margin({ left: 20, right: 20, top: 12, bottom: 4 })
        .onClick(() => this.onPrimaryAction())

        // ---------- 统计（居中） ----------
        Text(this.summaryText())
          .fontSize(13)
          .fontColor(this.theme().onSurfaceVariant)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })

        // ---------- 撤销（居中文字按钮；批量模式下隐藏） ----------
        if (!this.selectMode) {
          Text('撤销上一条')
            .fontSize(14)
            .fontColor(this.theme().primary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(8)
            .onClick(() => this.undoLast())
        }

        // ---------- 记录列表 ----------
        if (this.count === 0) {
          Column() {
            Text('还没有记录')
              .fontSize(16)
              .fontColor(this.theme().onSurfaceVariant)
            Text(this.isIntervalEvent() ? '点上方「开始计时」记一段吧' : '点上方「记录此刻」记一条吧')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 6 }) {
            // 点时刻：序号 + 完整时间 + Unix 秒
            ForEach(this.records, (m: number, i: number) => {
              ListItem() {
                Row() {
                  if (this.selectMode) {
                    this.RowCheckBox(m)
                  }
                  Text(`#${i + 1}`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme().primary)
                    .constraintSize({ minWidth: 34 })

                  Column() {
                    Text(TimeFormat.full(m))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.theme().onSurface)
                      .fontFamily('monospace')
                    Text(`Unix 秒：${Math.floor(m / 1000)}`)
                      .fontSize(12)
                      .fontColor(this.theme().onSurfaceVariant)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  if (!this.selectMode) {
                    Text('复制')
                      .fontSize(14)
                      .fontColor(this.theme().primary)
                      .padding({ left: 12, right: 4, top: 8, bottom: 8 })
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 10, top: 12, bottom: 12 })
                .backgroundColor(this.theme().glassCard)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  if (this.selectMode) {
                    this.toggleSelect(m);
                  } else {
                    this.copyRecord(m);
                  }
                })
                .gesture(
                  LongPressGesture()
                    .onAction(() => {
                      if (!this.selectMode) {
                        this.deleteRecordAt(i);
                      }
                    })
                )
              }
            }, (m: number) => `${m}`)

            // 时间段：序号 + 起止 + 时长
            ForEach(this.intervals, (it: TimeInterval, i: number) => {
              ListItem() {
                Row() {
                  if (this.selectMode) {
                    this.RowCheckBox(it.start)
                  }
                  Text(`#${i + 1}`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme().primary)
                    .constraintSize({ minWidth: 34 })

                  Column() {
                    Text(TimeFormat.full(it.start))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.theme().onSurface)
                      .fontFamily('monospace')
                    if (it.isOngoing()) {
                      Text(`进行中 · 已 ${formatDuration(it.duration())}`)
                        .fontSize(12)
                        .fontColor(this.theme().primary)
                        .margin({ top: 2 })
                    } else {
                      Text(`→ ${TimeFormat.hm(it.end ?? it.start)} · ${formatDuration(it.duration())}`)
                        .fontSize(12)
                        .fontColor(this.theme().onSurfaceVariant)
                        .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  if (!this.selectMode) {
                    Text('复制')
                      .fontSize(14)
                      .fontColor(this.theme().primary)
                      .padding({ left: 12, right: 4, top: 8, bottom: 8 })
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 10, top: 12, bottom: 12 })
                .backgroundColor(this.theme().glassCard)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  if (this.selectMode) {
                    this.toggleSelect(it.start);
                  } else {
                    this.copyRecord(it.start);
                  }
                })
                .gesture(
                  LongPressGesture()
                    .onAction(() => {
                      if (!this.selectMode) {
                        this.deleteRecordAt(i);
                      }
                    })
                )
              }
            }, (it: TimeInterval) => `${it.start}-${it.end ?? -1}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20, right: 20, top: 8, bottom: this.selectMode ? 96 : 24 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 135,
        colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
      })

      // 批量操作底栏
      if (this.selectMode) {
        this.SelectionBar()
      }
      // 编辑事件弹层
      if (this.showEdit) {
        this.EditSheet()
      }
    }
    .width('100%')
    .height('100%')
  }
}
