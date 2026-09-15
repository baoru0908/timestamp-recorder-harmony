import { CARD_TEXT, CARD_TEXT_SUB } from '../../model/CardData';

/**
 * 单事件服务卡片（对齐 Android WidgetSingleProvider 三档布局）：
 * - 1*2 横条：事件色底 + 名称 + 最近时间 + 「＋」
 * - 2*2 / 4*4 卡片：名称 / 最近时间 /（够高时）累计次数 / 提示
 * 整卡点击即记录；未绑定事件时显示「未绑定事件」。
 */
let storage = new LocalStorage();
@Entry(storage)
@Component
struct SingleEventCard {
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('eventId') eventId: number = 0;
  @LocalStorageProp('name') name: string = '未绑定事件';
  @LocalStorageProp('color') color: string = '#546E7A';
  @LocalStorageProp('lastText') lastText: string = '';
  @LocalStorageProp('count') count: number = 0;

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
          Text(`累计 ${this.count} 次`)
            .fontSize(12)
            .fontColor(CARD_TEXT_SUB)
            .width('100%')
          Text('点击记录')
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
