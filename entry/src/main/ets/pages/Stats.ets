import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { EventRepository } from '../data/EventRepository';
import { colorToHex, formatDuration, TimeInterval, TimestampEvent } from '../model/TimestampEvent';
import { getTheme, ThemeColors } from '../util/Theme';

const C_TREND: string = '#1E88E5';
const DAY_MS: number = 86400000;

/** 柱状图数据项 */
class BarItem {
  label: string;
  value: number;
  color: string;

  constructor(label: string, value: number, color: string) {
    this.label = label;
    this.value = value;
    this.color = color;
  }
}

/**
 * 统计页：概览 + 各事件记录数柱状图 + 近 N 天趋势（Canvas 自绘，零依赖）
 * 对齐 Android 版 StatsActivity（总事件/总记录/最忙事件 + 两张柱状图 + 时长汇总）。
 */
@Entry
@Component
struct Stats {
  @State totalEvents: number = 0;
  @State totalRecords: number = 0;
  @State busiestName: string = '';
  @State busiestCount: number = 0;
  @State busiestColor: string = '#CCCCCC';
  @State hasData: boolean = false;
  @State trendDays: number = 14;                 // 趋势天数：7 / 14 / 30，默认 14
  @State focusEventId: number = -1;               // 聚焦事件 id；-1 表示「全部」
  @State focusEventName: string = '';            // 聚焦事件名（顶栏展示用）
  // 时长汇总（仅区间事件且存在已结束段时展示）
  @State hasIntervals: boolean = false;
  @State intervalCount: number = 0;
  @State intervalTotalMs: number = 0;
  @State intervalAvgMs: number = 0;
  @State intervalMaxMs: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  /** App 回到前台时由 EntryAbility.onForeground 递增 → 触发从磁盘重载（卡片进程可能已写入） */
  @StorageProp('fgReloadTick') @Watch('onForegroundReload') fgReloadTick: number = 0;

  private repo: EventRepository | null = null;
  private eventsCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private daysCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private eventBars: BarItem[] = [];
  private dayBars: BarItem[] = [];

  /** 当前语义色板（ArkUI struct 内必须用普通方法，不能用 getter） */
  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.repo = new EventRepository(ctx);
    // 读取聚焦参数（来自事件详情页 pushUrl 的 focusEventId）
    const params: Object | undefined = router.getParams();
    if (params !== undefined && params !== null) {
      const p: Record<string, Object> = params as Record<string, Object>;
      const fid: Object | undefined = p['focusEventId'];
      if (fid !== undefined && fid !== null) {
        const num: number = fid as number;
        if (!isNaN(num)) {
          this.focusEventId = num;
          const ev: TimestampEvent | null = this.repo.getEvent(num);
          this.focusEventName = ev !== null ? ev.name : '';
        }
      }
    }
    this.compute();
  }

  /** 回到本页 / App 回到前台：丢弃进程内 Preferences 缓存后重读（卡片进程可能已写入） */
  onPageShow(): void {
    if (this.repo !== null) {
      this.repo.refresh();
      this.compute();
    }
  }

  onForegroundReload(): void {
    this.onPageShow();
  }

  /** 聚焦模式下只取指定事件，否则取全部 */
  private getFilteredEvents(): TimestampEvent[] {
    if (this.repo === null) {
      return [];
    }
    const all: TimestampEvent[] = this.repo.getEvents();
    if (this.focusEventId > 0) {
      return all.filter((e: TimestampEvent) => e.id === this.focusEventId);
    }
    return all;
  }

  private compute(): void {
    if (this.repo === null) {
      return;
    }
    const events: TimestampEvent[] = this.getFilteredEvents();
    this.totalEvents = events.length;

    const bars: BarItem[] = [];
    let total: number = 0;
    let busiest: TimestampEvent | null = null;
    let busiestCount: number = 0;
    for (let i: number = 0; i < events.length; i++) {
      const ev: TimestampEvent = events[i];
      const c: number = this.repo.recordCount(ev.id);
      total += c;
      bars.push(new BarItem(ev.name, c, colorToHex(ev.color)));
      if (c > busiestCount) {
        busiest = ev;
        busiestCount = c;
      }
    }
    this.totalRecords = total;
    if (busiest !== null && busiestCount > 0) {
      this.busiestName = busiest.name;
      this.busiestCount = busiestCount;
      this.busiestColor = colorToHex(busiest.color);
    } else {
      this.busiestName = '';
      this.busiestCount = 0;
      this.busiestColor = '#CCCCCC';
    }
    this.eventBars = bars;
    this.dayBars = this.computeDaily(events);
    this.computeIntervals(events);
    this.hasData = total > 0;
  }

  /** 时长汇总：统计已结束的时间段（进行中的段不计入） */
  private computeIntervals(events: TimestampEvent[]): void {
    let count: number = 0;
    let total: number = 0;
    let max: number = 0;
    for (let i: number = 0; i < events.length; i++) {
      const list: TimeInterval[] = this.repo!.getIntervals(events[i].id);
      for (let j: number = 0; j < list.length; j++) {
        const it: TimeInterval = list[j];
        if (!it.isOngoing()) {
          const d: number = it.duration();
          count++;
          total += d;
          if (d > max) {
            max = d;
          }
        }
      }
    }
    this.intervalCount = count;
    this.intervalTotalMs = total;
    this.intervalMaxMs = max;
    this.intervalAvgMs = count > 0 ? total / count : 0;
    this.hasIntervals = count > 0;
  }

  /** 近 N 天（含今天）按天归桶；柱标只标「日」（1..31，最多两位） */
  private computeDaily(events: TimestampEvent[]): BarItem[] {
    const now: Date = new Date();
    const todayStart: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const starts: number[] = [];
    for (let i: number = this.trendDays - 1; i >= 0; i--) {
      starts.push(todayStart - i * DAY_MS);
    }
    const counts: number[] = new Array<number>(this.trendDays).fill(0);
    if (this.repo !== null) {
      events.forEach((ev: TimestampEvent) => {
        this.repo!.getRecords(ev.id).forEach((m: number) => {
          for (let k: number = 0; k < starts.length; k++) {
            if (m >= starts[k] && m < starts[k] + DAY_MS) {
              counts[k]++;
              break;
            }
          }
        });
      });
    }
    const bars: BarItem[] = [];
    for (let i: number = 0; i < this.trendDays; i++) {
      const d: Date = new Date(starts[i]);
      bars.push(new BarItem(`${d.getDate()}`, counts[i], C_TREND));
    }
    return bars;
  }

  /** 切换趋势天数：重算并按天重绘 */
  private onTrendDaysChange(days: number): void {
    if (this.trendDays === days) {
      return;
    }
    this.trendDays = days;
    this.compute();
    this.drawChart(this.eventsCtx, this.eventBars, true);
    this.drawChart(this.daysCtx, this.dayBars, true);
  }

  /** 返回全部：退出聚焦模式 */
  private onExitFocus(): void {
    this.focusEventId = -1;
    this.focusEventName = '';
    this.compute();
    this.drawChart(this.eventsCtx, this.eventBars, true);
    this.drawChart(this.daysCtx, this.dayBars, true);
  }

  private drawChart(ctx: CanvasRenderingContext2D, bars: BarItem[], showLabels: boolean): void {
    const w: number = ctx.width;
    const h: number = ctx.height;
    if (w <= 0 || h <= 0 || bars.length === 0) {
      return;
    }
    ctx.clearRect(0, 0, w, h);
    const padL: number = 6;
    const padR: number = 6;
    const padT: number = 24;
    const padB: number = showLabels ? 26 : 14;
    const chartW: number = w - padL - padR;
    const chartH: number = h - padT - padB;
    let maxV: number = 1;
    bars.forEach((b: BarItem) => {
      if (b.value > maxV) {
        maxV = b.value;
      }
    });
    const n: number = bars.length;
    const slot: number = chartW / n;
    const barW: number = Math.min(slot * 0.6, 44);
    ctx.textAlign = 'center';
    bars.forEach((b: BarItem, i: number) => {
      const x: number = padL + slot * i + (slot - barW) / 2;
      const barH: number = b.value > 0 ? (b.value / maxV) * chartH : 0;
      const y: number = padT + chartH - barH;
      // 柱体（圆角）
      ctx.fillStyle = b.color;
      if (barH > 0) {
        ctx.beginPath();
        ctx.roundRect(x, y, barW, Math.max(barH, 2), 4);
        ctx.fill();
      }
      // 数值（柱顶）
      ctx.fillStyle = this.theme().onSurface;
      ctx.font = '11vp sans-serif';
      ctx.fillText(`${b.value}`, x + barW / 2, y - 4);
      // 标签（柱底，事件名过长自动截断）
      if (showLabels) {
        ctx.fillStyle = this.theme().onSurfaceVariant;
        ctx.fillText(b.label, x + barW / 2, h - 8, barW + 6);
      }
    });
  }

  build() {
    Column() {
      // ---------- 顶栏 ----------
      Row() {
        Text('←')
          .fontSize(26)
          .fontColor(this.theme().onSurface)
          .padding({ left: 16, right: 8, top: 6, bottom: 6 })
          .onClick(() => router.back())

        Text('统计')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
      }
      .width('100%')
      .padding({ left: 4, right: 12, top: 30, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

      // ---------- 聚焦模式提示条 ----------
      if (this.focusEventId > 0) {
        Row() {
          Text(`当前：${this.focusEventName}`)
            .fontSize(14)
            .fontColor(this.theme().onSurface)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('返回全部')
            .fontSize(13)
            .fontColor(this.theme().onPrimary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.theme().primary)
            .onClick(() => this.onExitFocus())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })
        .alignItems(VerticalAlign.Center)
      }

      if (this.hasData) {
        Scroll() {
          Column() {
            // ---------- 概览：事件数 / 记录总数 两卡并排（对齐 Android 渐变卡） ----------
            Row({ space: 12 }) {
              this.GradStatCell('事件数', `${this.totalEvents}`, ['#42A5F5', '#1565C0'])
              this.GradStatCell('记录总数', `${this.totalRecords}`, ['#66BB6A', '#2E7D32'])
            }
            .width('100%')

            // ---------- 记录最多的事件（整宽橙渐变卡，聚焦模式下隐藏） ----------
            if (this.focusEventId <= 0) {
              Column() {
                Text('记录最多的事件')
                  .fontSize(12)
                  .fontColor('#E6FFFFFF')
                  .width('100%')
                Text(this.busiestCount > 0 ? this.busiestName : '—')
                  .fontSize(30)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 6 })
                Text(this.busiestCount > 0 ? `${this.busiestCount} 次记录` : '暂无记录')
                  .fontSize(12)
                  .fontColor('#E6FFFFFF')
                  .width('100%')
                  .margin({ top: 2 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(16)
              .margin({ top: 12 })
              .borderRadius(16)
              .linearGradient({ angle: 135, colors: [['#FFA726', 0.0], ['#E65100', 1.0]] })
            }

            // ---------- 各事件记录数 ----------
            Text('各事件记录数')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().onSurface)
              .width('100%')
              .margin({ top: 18, bottom: 8 })

            Column() {
              Canvas(this.eventsCtx)
                .width('100%')
                .height(180)
                .onReady(() => this.drawChart(this.eventsCtx, this.eventBars, true))
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.theme().glassCard)
            .borderRadius(14)

            // ---------- 趋势天数切换 ----------
            Row({ space: 8 }) {
              this.RangeChip(7)
              this.RangeChip(14)
              this.RangeChip(30)
            }
            .width('100%')
            .margin({ top: 18, bottom: 4 })
            .alignItems(VerticalAlign.Center)

            // ---------- 近 N 天趋势 ----------
            Text(`近 ${this.trendDays} 天趋势`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().onSurface)
              .width('100%')
              .margin({ top: 8, bottom: 8 })

            Column() {
              Canvas(this.daysCtx)
                .width('100%')
                .height(160)
                .onReady(() => this.drawChart(this.daysCtx, this.dayBars, true))
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.theme().glassCard)
            .borderRadius(14)

            // ---------- 时长汇总（仅区间事件且存在已结束段时展示） ----------
            if (this.hasIntervals) {
              Text('时长汇总')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme().onSurface)
                .width('100%')
                .margin({ top: 18, bottom: 8 })

              Column() {
                Row({ space: 12 }) {
                  this.DurationCell('时段总数', `${this.intervalCount}`, ['#26C6DA', '#00838F'])
                  this.DurationCell('总时长', formatDuration(this.intervalTotalMs), ['#AB47BC', '#6A1B9A'])
                }
                .width('100%')

                Row({ space: 12 }) {
                  this.DurationCell('平均时长', formatDuration(this.intervalAvgMs), ['#FF7043', '#E64A19'])
                  this.DurationCell('最长时长', formatDuration(this.intervalMaxMs), ['#EC407A', '#AD1457'])
                }
                .width('100%')
                .margin({ top: 12 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.theme().glassCard)
              .borderRadius(14)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      } else {
        Column() {
          Text('还没有记录')
            .fontSize(16)
            .fontColor(this.theme().onSurfaceVariant)
          Text('先到「事件」页记录几条再看统计吧')
            .fontSize(13)
            .fontColor(this.theme().onSurfaceVariant)
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
    })
  }

  /** 渐变统计卡（对齐 Android stat 卡：大数字 30sp 白字 + 12sp 标签） */
  @Builder
  GradStatCell(title: string, value: string, grad: string[]) {
    Column() {
      Text(value)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(title)
        .fontSize(12)
        .fontColor('#E6FFFFFF')
        .width('100%')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .linearGradient({ angle: 135, colors: [[grad[0], 0.0], [grad[1], 1.0]] })
  }

  /** 趋势天数切换 Chip（分段控件） */
  @Builder
  RangeChip(days: number) {
    Text(days === 7 ? '近 7 天' : days === 14 ? '近 14 天' : '近 30 天')
      .fontSize(13)
      .fontColor(this.trendDays === days ? this.theme().onPrimary : this.theme().onSurface)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.trendDays === days ? this.theme().primary : this.theme().glassCard)
      .onClick(() => this.onTrendDaysChange(days))
  }

  /** 时长汇总卡片（值可能是较长的时长文本，故字号略小、可折行） */
  @Builder
  DurationCell(title: string, value: string, grad: string[]) {
    Column() {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(title)
        .fontSize(12)
        .fontColor('#E6FFFFFF')
        .width('100%')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(14)
    .linearGradient({ angle: 135, colors: [[grad[0], 0.0], [grad[1], 1.0]] })
  }
}
