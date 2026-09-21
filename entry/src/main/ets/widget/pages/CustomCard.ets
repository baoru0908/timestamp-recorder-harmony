import {
  CardEventJson,
  CardMetrics,
  cardMetricsOf,
  contentInset,
  isLightHex,
  CARD_TEXT_DIM
} from '../../model/CardData';

/**
 * 自定义服务卡片（对齐 Android WidgetCustomProvider）：
 * 用户可设「标题 + 背景色 或 背景图」，并勾选多个事件；点行即记录该事件。
 *
 * 排版与「全部事件」卡片**共用同一套规范**（`CardData.cardMetricsOf`），
 * 保证多事件场景下两卡的层级、间距、对齐完全一致；差异仅在配色来源：
 * - 文字色由数据层按底色亮度下发（浅底自动转深字）
 * - 行块底色：有背景图或深底 → 半透明白；浅底 → 半透明黑
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

  /** 当前尺寸档位的排版参数（与全部事件卡片同源） */
  private m(): CardMetrics {
    return cardMetricsOf(this.dimension);
  }

  /** 底色是否偏浅（浅底行底用深色半透明，保证层次） */
  private isLight(): boolean {
    return isLightHex(this.bgColor);
  }

  /** 事件行底色：深底/有图 → 半透明白；浅底 → 半透明黑 */
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

      // 第三层：内容（三段式，与全部事件卡片同规范）
      Column() {
        // ── 标题区 ──
        Row() {
          Text(this.title)
            .fontSize(this.m().titleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.titleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Text('点击记录')
            .fontSize(this.m().hintSize)
            .fontColor(this.subTextColor)
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
          // 空态：点击打开 App 配置
          Column() {
            Text('暂无事件')
              .fontSize(this.m().nameSize)
              .fontColor(this.textColor)
            Text('点击打开 App 添加')
              .fontSize(this.m().timeSize)
              .fontColor(this.subTextColor)
              .margin({ top: this.m().rowGap })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .onClick(() => postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: {} }))
        } else {
          // ── 事件列表 ──
          ForEach(this.events, (ev: CardEventJson) => {
            Row() {
              Row()
                .width(this.m().dotSize)
                .height(this.m().dotSize)
                .borderRadius(this.m().dotSize / 2)
                .backgroundColor(ev.color)
              Text(ev.name)
                .fontSize(this.m().nameSize)
                .fontColor(this.textColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .margin({ left: this.m().dotGap })
              Text(ev.lastText)
                .fontSize(this.m().timeSize)
                .fontColor(this.subTextColor)
                .maxLines(1)
                .margin({ left: this.m().dotGap })
            }
            .width('100%')
            .height(this.m().rowH)
            .padding({ left: this.m().rowPadH, right: this.m().rowPadH })
            .margin({ left: this.m().padH, right: this.m().padH, bottom: this.m().rowGap })
            .borderRadius(this.m().rowRadius)
            .backgroundColor(this.rowBg())
            .alignItems(VerticalAlign.Center)
            .onClick(() => postCardAction(this, {
              action: 'message',
              params: { 'action': 'record', 'eventId': ev.id }
            }))
          }, (ev: CardEventJson) => `${ev.id}-${ev.lastText}`)

          // ── 溢出提示（L4）──
          if (this.rest > 0) {
            Text(`还有 ${this.rest} 个事件`)
              .fontSize(this.m().hintSize)
              .fontColor(this.subTextColor)
              .opacity(0.72)
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
    }
    .width('100%')
    .height('100%')
  }
}
