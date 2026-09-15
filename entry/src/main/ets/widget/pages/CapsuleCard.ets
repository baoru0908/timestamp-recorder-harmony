import { CARD_TEXT, CARD_TEXT_SUB } from '../../model/CardData';

/**
 * 胶囊服务卡片（对齐 Android WidgetCapsuleProvider）：
 * 1*2 横向胶囊，事件色填充，左侧名称 + 右侧「记录」，点击即记录。
 */
let storage = new LocalStorage();
@Entry(storage)
@Component
struct CapsuleCard {
  @LocalStorageProp('eventId') eventId: number = 0;
  @LocalStorageProp('name') name: string = '未绑定事件';
  @LocalStorageProp('color') color: string = '#546E7A';

  build() {
    Row() {
      Text(this.name)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(CARD_TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank().layoutWeight(1)
      // 加号图标（对齐 Android ic_record_plus 22dp）+「记录」14sp bold（常显）
      Text('+')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(CARD_TEXT)
      Text('记录')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(CARD_TEXT)
        .margin({ left: 6 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.color)
    .onClick(() => postCardAction(this, {
      action: 'message',
      params: { 'action': 'record', 'eventId': this.eventId }
    }))
  }
}
