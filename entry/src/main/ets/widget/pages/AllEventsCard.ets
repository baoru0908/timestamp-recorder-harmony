import { CardEventJson, CARD_DARK, CARD_TEXT, CARD_TEXT_SUB, CARD_TEXT_DIM } from '../../model/CardData';

/**
 * 全事件服务卡片（对齐 Android widget_timestamp.xml）：
 * 标题行 + 最多 4 行（4*4 时 6 行）「色点 + 名称 + 最近时间」，点行即记录；空状态可点开 App。
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

  build() {
    Column() {
      // 标题行（对齐 Android：标题 15sp bold + 右「点击记录」10sp）
      Row() {
        Text('时间戳记录')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(CARD_TEXT)
        Blank()
        Text('点击记录')
          .fontSize(10)
          .fontColor(CARD_TEXT_SUB)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: 8 })

      if (!this.hasData) {
        // 空状态：点击打开 App 添加
        Column() {
          Text('暂无事件')
            .fontSize(14)
            .fontColor(CARD_TEXT)
          Text('点击打开 App 添加')
            .fontSize(11)
            .fontColor(CARD_TEXT_SUB)
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: {} }))
      } else {
        // 事件行（固定行渲染，不依赖 List）
        ForEach(this.events, (ev: CardEventJson) => {
          Row() {
            Circle()
              .width(10)
              .height(10)
              .fill(ev.color)
            Text(ev.name)
              .fontSize(13)
              .fontColor(CARD_TEXT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 8 })
            Blank().layoutWeight(1)
            Text(ev.lastText)
              .fontSize(11)
              .fontColor(CARD_TEXT_SUB)
              .maxLines(1)
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .margin({ left: 12, right: 12, bottom: 6 })
          .borderRadius(12)
          .backgroundColor('#26FFFFFF')
          .onClick(() => postCardAction(this, {
            action: 'message',
            params: { 'action': 'record', 'eventId': ev.id }
          }))
        }, (ev: CardEventJson) => `${ev.id}-${ev.lastText}`)

        if (this.rest > 0) {
          Text(`还有 ${this.rest} 个事件`)
            .fontSize(10)
            .fontColor(CARD_TEXT_DIM)
            .margin({ top: 4 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: 12 })
    .backgroundColor(CARD_DARK)
  }
}
