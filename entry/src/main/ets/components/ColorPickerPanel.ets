/**
 * 共享取色面板：事件编辑弹层与卡片配置页两处复用。
 *
 * 行为对齐 Android 的「23 色板 + 第 0 格自定义」方案，但本组件只做「色板 + hex 输入」这一档
 * （不内置 HSV 取色器，成本高）。第 0 格「自定义」在组件内以末尾一个中性格呈现，点击后就地
 * 展开一个小面板（条件渲染，不用弹窗 API，便于嵌入任意容器）。
 *
 * 深浅色走 getTheme，跟随 AppStorage('isDark')。
 */
import { EVENT_COLORS, colorToHex, hexToColor, isValidHex } from '../model/TimestampEvent';
import { getTheme, KEY_IS_DARK, ThemeColors } from '../util/Theme';

@Component
export struct ColorPickerPanel {
  /** 当前选中色（有符号 int），由父组件通过状态传入 */
  @Prop selected: number = 0;
  /** 选中回调：点击色块或确认自定义色时触发 */
  onPick: (color: number) => void = () => {};

  @State private showCustom: boolean = false;
  @State private hexText: string = '';
  @State private hexErr: string = '';

  private isDark(): boolean {
    return AppStorage.get<boolean>(KEY_IS_DARK) ?? false;
  }

  private theme(): ThemeColors {
    return getTheme(this.isDark());
  }

  /** 自定义面板内预览色：空串回退当前选中，非法串回退安全默认蓝 */
  private previewColor(): number {
    if (this.hexText.trim() === '') {
      return this.selected;
    }
    if (!isValidHex(this.hexText)) {
      return 0xFF1E88E5 | 0;
    }
    return hexToColor(this.hexText);
  }

  private openCustom(): void {
    this.hexText = colorToHex(this.selected);
    this.hexErr = '';
    this.showCustom = true;
  }

  private closeCustom(): void {
    this.showCustom = false;
    this.hexErr = '';
  }

  private confirmCustom(): void {
    if (!isValidHex(this.hexText)) {
      return;
    }
    this.onPick(hexToColor(this.hexText));
    this.closeCustom();
  }

  build() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        // 23 个预设色块
        ForEach(EVENT_COLORS, (c: number) => {
          Stack() {
            if (this.selected === c) {
              Text('✓')
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width(40)
          .height(40)
          .margin(6)
          .borderRadius(20)
          .backgroundColor(colorToHex(c))
          .border({ width: this.selected === c ? 2 : 0, color: this.theme().onSurface })
          .onClick(() => {
            this.onPick(c);
          })
        }, (c: number) => `${c}`)

        // 末尾一格「自定义」：中性底 + # 符号
        Stack() {
          Text('#')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().onSurfaceVariant)
        }
        .width(40)
        .height(40)
        .margin(6)
        .borderRadius(20)
        .backgroundColor(this.theme().inputBg)
        .border({ width: this.showCustom ? 2 : 1, color: this.theme().outline })
        .onClick(() => {
          this.openCustom();
        })
      }
      .width('100%')

      // 自定义小面板：就地展开（不用弹窗 API，便于嵌入）
      if (this.showCustom) {
        Column() {
          Row() {
            TextInput({ text: this.hexText, placeholder: '#RRGGBB' })
              .layoutWeight(1)
              .height(40)
              .backgroundColor(this.theme().inputBg)
              .fontColor(this.theme().onSurface)
              .placeholderColor(this.theme().outline)
              .borderRadius(10)
              .onChange((v: string) => {
                this.hexText = v;
                if (isValidHex(v)) {
                  this.hexErr = '';
                } else {
                  this.hexErr = '格式应为 #RRGGBB 或 #RGB';
                }
              })
            Stack()
              .width(40)
              .height(40)
              .margin({ left: 10 })
              .borderRadius(20)
              .backgroundColor(colorToHex(this.previewColor()))
              .border({ width: 1, color: this.theme().outline })
          }
          .width('100%')
          .margin({ top: 10 })

          if (this.hexErr !== '') {
            Text(this.hexErr)
              .fontSize(12)
              .fontColor(this.theme().danger)
              .width('100%')
              .margin({ top: 6 })
          }

          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .height(40)
              .backgroundColor(this.theme().cancelBtn)
              .fontColor(this.theme().onSurface)
              .borderRadius(20)
              .onClick(() => {
                this.closeCustom();
              })
            Button('确定')
              .layoutWeight(1)
              .height(40)
              .enabled(this.hexErr === '' && isValidHex(this.hexText))
              .backgroundColor(this.theme().primary)
              .fontColor('#FFFFFF')
              .borderRadius(20)
              .onClick(() => {
                this.confirmCustom();
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding({ top: 10 })
      }
    }
    .width('100%')
  }
}
