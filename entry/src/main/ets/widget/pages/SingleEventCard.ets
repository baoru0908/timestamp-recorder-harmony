import { CARD_TEXT, CARD_TEXT_SUB, CARD_TX_MISSING, CARD_TX_CLICK_HINT, cardCountText } from '../../model/CardData';

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

  build() {
    Column() {
      if (this.dimension === '1*2') {
        // ── 横条（BAR）──
        Row() {
          Text(this.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(CARD_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank().layoutWeight(1)
          Text(this.lastText)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(CARD_TEXT_SUB)
            .maxLines(1)
            .margin({ left: 8, right: 8 })
          Text('＋')
            .fontSize(22)
            .fontColor(CARD_TEXT)
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 18, right: 16 })
        .alignItems(VerticalAlign.Center)
      } else {
        // ── 卡片（CARD）──
        Column() {
          Text(this.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(CARD_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.lastText)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor(CARD_TEXT_SUB)
            .width('100%')
            .margin({ top: 6 })
          Blank()
          // 计数：时间段 = 段数，点时刻 = 条数（对齐 Android widget_single_count「共 %d 次」）
          Text(cardCountText(this.count))
            .fontSize(12)
            .fontColor(CARD_TEXT_SUB)
            .width('100%')
          Text(this.hint)
            .fontSize(11)
            .fontColor(CARD_TEXT_SUB)
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 14 })
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
