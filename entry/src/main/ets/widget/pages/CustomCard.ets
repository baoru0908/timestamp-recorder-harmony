import { CardEventJson, CARD_TEXT_DIM, isLightHex } from '../../model/CardData';

/**
 * 自定义服务卡片（对齐 Android WidgetCustomProvider）：
 * 用户可设「标题 + 背景色 或 背景图」，并勾选多个事件；点行即记录该事件。
 *
 * 数据来源：FormAbility 构建 payload → formBindingData（含 formImages 的 fd）→ @LocalStorageProp。
 * 背景图走 `Image('memory://<bgImageKey>')`：鸿蒙卡片**不能直接读沙箱路径**，必须由
 * FormExtensionAbility 侧把图片以 fd 形式下发（详见 util/FormSync.ets 与官方 FAQ faqs-form-14）。
 */
let storage = new LocalStorage();

@Entry(storage)
@Component
struct CustomCard {
  @LocalStorageProp('formName') formName: string = '';
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('title') title: string = '我的记录';
  @LocalStorageProp('bgColor') bgColor: string = '#1A1C1E';
  @LocalStorageProp('hasBgImage') hasBgImage: boolean = false;
  @LocalStorageProp('bgImageKey') bgImageKey: string = 'custombg';
  @LocalStorageProp('titleColor') titleColor: string = '#FFFFFF';
  @LocalStorageProp('textColor') textColor: string = '#FFFFFF';
  @LocalStorageProp('subTextColor') subTextColor: string = '#CCFFFFFF';
  @LocalStorageProp('events') events: CardEventJson[] = [];
  @LocalStorageProp('rest') rest: number = 0;

  /** 底色是否偏浅（浅底行底用深色半透明，保证层次） */
  private isLight(): boolean {
    return isLightHex(this.bgColor);
  }

  /** 事件行底色：深底用半透明白，浅底用半透明黑 */
  private rowBg(): string {
    return this.isLight() && !this.hasBgImage ? '#14000000' : '#26FFFFFF';
  }

  build() {
    Stack() {
      // 第一层：兜底底色（背景图缺失/加载失败时的降级，不会白屏）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.bgColor)

      // 第二层：背景图（有图时铺满）+ 压暗遮罩，保证文字可读
      if (this.hasBgImage) {
        Image(`memory://${this.bgImageKey}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#59000000')
      }

      // 第三层：内容
      Column() {
        // 标题行
        Row() {
          Text(this.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.titleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Text('点击记录')
            .fontSize(10)
            .fontColor(this.subTextColor)
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 14, bottom: 8 })

        if (!this.hasData) {
          // 空态：点击打开 App 配置
          Column() {
            Text('暂无事件')
              .fontSize(14)
              .fontColor(this.textColor)
            Text('点击打开 App 添加')
              .fontSize(11)
              .fontColor(this.subTextColor)
              .margin({ top: 4 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .onClick(() => postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: {} }))
        } else {
          // 事件行（固定行渲染，不依赖 List；色点用圆角方块，兼容 API 24）
          ForEach(this.events, (ev: CardEventJson) => {
            Row() {
              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor(ev.color)
              Text(ev.name)
                .fontSize(13)
                .fontColor(this.textColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 8 })
              Blank().layoutWeight(1)
              Text(ev.lastText)
                .fontSize(11)
                .fontColor(this.subTextColor)
                .maxLines(1)
                .margin({ left: 6 })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .margin({ left: 12, right: 12, bottom: 6 })
            .borderRadius(12)
            .backgroundColor(this.rowBg())
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
    }
    .width('100%')
    .height('100%')
  }
}
