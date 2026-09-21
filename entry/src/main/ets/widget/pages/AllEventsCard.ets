import {
  CardEventJson,
  CardMetrics,
  cardMetricsOf,
  contentInset,
  CARD_DARK,
  CARD_TEXT,
  CARD_TEXT_SUB,
  CARD_TEXT_DIM
} from '../../model/CardData';

/**
 * 全部事件服务卡片（多事件场景主力卡，对齐 Android widget_timestamp.xml）。
 *
 * 排版规范（详见 `release/CARD_LAYOUT_SPEC.md`）：
 * - **三段式**：标题区（固定）/ 事件列表（弹性，行数由尺寸档位决定）/ 溢出提示（仅溢出时）
 * - **左基线**：标题、行内文本、溢出提示统一缩进到 `contentInset = padH + rowPadH`
 * - **行块**：左右外距 `padH`、内部左右内距 `rowPadH`、高 `rowH`、间距 `rowGap`、圆角 `rowRadius`
 * - **行内对齐**：色点 + 名称左对齐，时间右对齐（Blank 撑开），全部垂直居中
 * - **响应式**：整套参数按 `dimension` 取档（1*2 / 2*2 / 2*4 / 4*4），字号与间距同步缩放
 */
let storage = new LocalStorage();

@Entry(storage)
@Component
struct AllEventsCard {
  @LocalStorageProp('formName') formName: string = '';
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('events') events: CardEventJson[] = [];
  @LocalStorageProp('rest') rest: number = 0;

  /** 当前尺寸档位的排版参数 */
  private m(): CardMetrics {
    return cardMetricsOf(this.dimension);
  }

  build() {
    Column() {
      // ── 标题区（L1 标题 + L3 提示，左基线对齐 contentInset）──
      Row() {
        Text('时间戳记录')
          .fontSize(this.m().titleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(CARD_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text('点击记录')
          .fontSize(this.m().hintSize)
          .fontColor(CARD_TEXT_SUB)
          .maxLines(1)
      }
      .width('100%')
      .padding({
        left: contentInset(this.m()),
        right: contentInset(this.m()),
        top: this.m().padTop,
        bottom: this.m().rowGap + 2
      })
      .alignItems(VerticalAlign.Center)

      if (!this.hasData) {
        // 空状态：整块可点，打开 App 添加
        Column() {
          Text('暂无事件')
            .fontSize(this.m().nameSize)
            .fontColor(CARD_TEXT)
          Text('点击打开 App 添加')
            .fontSize(this.m().timeSize)
            .fontColor(CARD_TEXT_SUB)
            .margin({ top: this.m().rowGap })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: {} }))
      } else {
        // ── 事件列表（弹性区）──
        ForEach(this.events, (ev: CardEventJson) => {
          Row() {
            // 色点（用圆角方块，兼容 API 24：Circle 的 fill 为 API 26 新增）
            Row()
              .width(this.m().dotSize)
              .height(this.m().dotSize)
              .borderRadius(this.m().dotSize / 2)
              .backgroundColor(ev.color)
            Text(ev.name)
              .fontSize(this.m().nameSize)
              .fontColor(CARD_TEXT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: this.m().dotGap })
            Text(ev.lastText)
              .fontSize(this.m().timeSize)
              .fontColor(CARD_TEXT_SUB)
              .maxLines(1)
              .margin({ left: this.m().dotGap })
          }
          .width('100%')
          .height(this.m().rowH)
          .padding({ left: this.m().rowPadH, right: this.m().rowPadH })
          .margin({ left: this.m().padH, right: this.m().padH, bottom: this.m().rowGap })
          .borderRadius(this.m().rowRadius)
          .backgroundColor('#26FFFFFF')
          .alignItems(VerticalAlign.Center)
          .onClick(() => postCardAction(this, {
            action: 'message',
            params: { 'action': 'record', 'eventId': ev.id }
          }))
        }, (ev: CardEventJson) => `${ev.id}-${ev.lastText}`)

        // ── 溢出提示（L4，左基线与其他内容对齐）──
        if (this.rest > 0) {
          Text(`还有 ${this.rest} 个事件`)
            .fontSize(this.m().hintSize)
            .fontColor(CARD_TEXT_DIM)
            .maxLines(1)
            .width('100%')
            .padding({ left: contentInset(this.m()), right: contentInset(this.m()) })
            .margin({ top: 2 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: this.m().padBottom })
    .backgroundColor(CARD_DARK)
  }
}
