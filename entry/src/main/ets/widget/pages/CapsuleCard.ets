import { CARD_TEXT, CARD_TEXT_SUB, CARD_TX_RECORDING, CARD_TX_MISSING } from '../../model/CardData';

/**
 * 胶囊服务卡片：1*2 横向胶囊，事件色填充，左侧名称 + 右侧动作。
 *
 * 时间段支持（对齐 Android 单事件横条的语义）：
 * - 点时刻事件 → 右侧「＋ 记录」
 * - 时间段事件 → 进行中时右侧「结束」，否则「开始」；名称旁显示「● 进行中」
 *   （点击一律交给 FormAbility 按事件类型分派，见 formability/FormAbility.onFormEvent）
 */
let storage = new LocalStorage();
@Entry(storage)
@Component
struct CapsuleCard {
  @LocalStorageProp('eventId') eventId: number = 0;
  @LocalStorageProp('name') name: string = CARD_TX_MISSING;
  @LocalStorageProp('color') color: string = '#546E7A';
  @LocalStorageProp('lastText') lastText: string = '';
  @LocalStorageProp('isInterval') isInterval: boolean = false;

  /** 是否正在计时（数据层下发「● 进行中」即为进行中） */
  private ongoing(): boolean {
    return this.lastText === CARD_TX_RECORDING;
  }

  /** 右侧动作文案 */
  private actionText(): string {
    if (!this.isInterval) {
      return '记录';
    }
    return this.ongoing() ? '结束' : '开始';
  }

  build() {
    Row() {
      Text(this.name)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(CARD_TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 时间段进行中：名称旁给出状态（与行内文案同一套表达）
      if (this.isInterval && this.ongoing()) {
        Text(CARD_TX_RECORDING)
          .fontSize(10)
          .fontColor(CARD_TEXT_SUB)
          .maxLines(1)
          .margin({ left: 8 })
      }

      Blank().layoutWeight(1)
      // 加号图标仅「记录」场景显示；开始 / 结束用「● / ■」形状区分
      if (this.isInterval) {
        Text(this.ongoing() ? '■' : '▶')
          .fontSize(13)
          .fontColor(CARD_TEXT)
      } else {
        Text('+')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(CARD_TEXT)
      }
      Text(this.actionText())
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
