import {
  CARD_TEXT,
  CARD_TEXT_SUB,
  CARD_TX_MISSING,
  CARD_TX_CLICK_HINT,
  cardCountText,
  CardMetrics,
  cardMetricsOf
} from '../../model/CardData';

/**
 * 单事件服务卡片（对齐 Android WidgetSingleProvider 三档布局）：
 * - 1*2 横条：事件色底 + 名称 + 最近时间 + 「＋」
 * - 2*2 / 4*4 卡片：名称 / 最近时间 /（够高时）计数 / 提示
 * 整卡点击即记录（**时间段事件由 FormAbility 分派为「开始 / 结束」切换**）；
 * 未绑定或事件已删除时显示「已删除」。
 */
let storage = new LocalStorage();
@Entry(storage)
@Component
struct SingleEventCard {
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('eventId') eventId: number = 0;
  @LocalStorageProp('name') name: string = CARD_TX_MISSING;
  @LocalStorageProp('color') color: string = '#546E7A';
  @LocalStorageProp('lastText') lastText: string = '';
  @LocalStorageProp('count') count: number = 0;
  /** 底部提示：时间段「点击开始 / 结束」，点时刻「点击记录」 */
  @LocalStorageProp('hint') hint: string = CARD_TX_CLICK_HINT;

  /** 排版档位（与多事件卡片同源，保证全卡片族字号梯度一致） */
  private m(): CardMetrics {
    return cardMetricsOf(this.dimension);
  }

  /** 主标题字号：大按钮形态突出事件名（1*2 扁条适当收敛） */
  private hero(): number {
    return this.dimension === '1*2' ? this.m().nameSize + 4 : this.m().nameSize + 7;
  }

  /** 次信息字号（最近时间 / 计数） */
  private sub(): number {
    return this.m().timeSize + 2;
  }

  build() {
    Column() {
      if (this.dimension === '1*2') {
        // ── 横条（BAR）──
        Row() {
          Text(this.name)
            .fontSize(this.hero())
            .fontWeight(FontWeight.Bold)
            .fontColor(CARD_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank().layoutWeight(1)
          Text(this.lastText)
            .fontSize(this.sub())
            .fontFamily('monospace')
            .fontColor(CARD_TEXT_SUB)
            .maxLines(1)
            .margin({ left: this.m().dotGap, right: this.m().dotGap })
          Text('＋')
            .fontSize(22)
            .fontColor(CARD_TEXT)
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.m().rowPadH + 6, right: this.m().rowPadH + 4 })
        .alignItems(VerticalAlign.Center)
      } else {
        // ── 卡片（CARD）──
        Column() {
          Text(this.name)
            .fontSize(this.hero())
            .fontWeight(FontWeight.Bold)
            .fontColor(CARD_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.lastText)
            .fontSize(this.sub())
            .fontFamily('monospace')
            .fontColor(CARD_TEXT_SUB)
            .width('100%')
            .margin({ top: 6 })
          Blank()
          // 计数：时间段 = 段数，点时刻 = 条数（对齐 Android widget_single_count「共 %d 次」）
          Text(cardCountText(this.count))
            .fontSize(this.sub() - 1)
            .fontColor(CARD_TEXT_SUB)
            .width('100%')
          Text(this.hint)
            .fontSize(this.sub() - 2)
            .fontColor(CARD_TEXT_SUB)
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
        .height('100%')
        .padding({
          left: this.m().rowPadH + 6,
          right: this.m().rowPadH + 6,
          top: this.m().rowPadH + 4,
          bottom: this.m().rowPadH + 2
        })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.color)
    .onClick(() => postCardAction(this, {
      action: 'message',
      params: { 'action': 'record', 'eventId': this.eventId }
    }))
  }
}
