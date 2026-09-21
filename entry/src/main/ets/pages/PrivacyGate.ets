import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { Privacy } from '../util/Privacy';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 开屏隐私合规门（应用市场合规要求：同意前不得进入应用，且不得默认勾选）。
 *
 * 出现时机：
 * - 首次启动：从未同意过 → 显示
 * - 版本更新：已同意的版本号 ≠ 当前 versionName → 重新显示并再次征得同意
 * - 已同意当前版本：EntryAbility 不会加载本页，直接进主页
 *
 * 同意后写入 `privacy_agreed_version = 当前 versionName`，再用 replaceUrl 进主页（不留返回栈）。
 */
@Entry
@Component
struct PrivacyGate {
  @State agreed: boolean = false;
  @StorageProp('isDark') isDark: boolean = false;

  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  private openDoc(doc: string): void {
    router.pushUrl({ url: 'pages/PrivacyDoc', params: { doc: doc } });
  }

  private onAgree(): void {
    if (!this.agreed) {
      this.getUIContext().getPromptAction().showToast({ message: '请先阅读并勾选同意' });
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context;
    Privacy.setAgreed(ctx);
    router.replaceUrl({ url: 'pages/Index' });
  }

  private onDecline(): void {
    this.getUIContext().showAlertDialog({
      title: '需要你的同意',
      message: '根据应用隐私合规要求，未同意《隐私政策》将无法使用本应用。确定退出吗？',
      buttons: [
        {
          value: '退出应用',
          fontColor: this.theme().danger,
          action: () => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            ctx.terminateSelf();
          }
        },
        { value: '返回', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  /** 自绘勾选框（⚠️ Circle 上加 .border() 会渲染成方框，必须用 Shape 的 stroke） */
  @Builder
  CheckBox() {
    Stack() {
      if (this.agreed) {
        Circle()
          .width(22)
          .height(22)
          .fill(this.theme().primary)
        Text('✓')
          .fontSize(14)
          .fontColor('#FFFFFF')
      } else {
        Circle()
          .width(22)
          .height(22)
          .fill('#00000000')
          .stroke(this.theme().outline)
          .strokeWidth(1.6)
      }
    }
    .width(40)
    .height(40)
    .onClick(() => {
      this.agreed = !this.agreed;
    })
  }

  /** 摘要要点（产品行为说明，不是法律文本） */
  @Builder
  BulletLine(text: string) {
    Row() {
      Text('·')
        .fontSize(14)
        .fontColor(this.theme().primary)
        .margin({ right: 6 })
      Text(text)
        .fontSize(14)
        .fontColor(this.theme().onSurfaceVariant)
        .layoutWeight(1)
        .lineHeight(21)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 8 })
  }

  /** 文档入口按钮 */
  @Builder
  DocLink(label: string, doc: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.theme().primary)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(this.theme().inputBg)
      .onClick(() => this.openDoc(doc))
  }

  build() {
    Column() {
      Column() {
        Text('欢迎使用')
          .fontSize(14)
          .fontColor(this.theme().onSurfaceVariant)
          .width('100%')
        Text('时间戳记录器')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
          .width('100%')
          .margin({ top: 4, bottom: 18 })

        Text('在开始使用前，请先阅读并同意以下协议。我们重视你的隐私：')
          .fontSize(14)
          .fontColor(this.theme().onSurface)
          .width('100%')
          .lineHeight(21)
          .margin({ bottom: 14 })

        this.BulletLine('所有数据仅保存在本机，不会上传到任何服务器')
        this.BulletLine('不申请网络、存储、相机、位置等任何系统权限')
        this.BulletLine('不含任何广告、统计、推送等第三方 SDK')
        this.BulletLine('你可随时删除数据，或导出 JSON 备份自行保管')

        Row() {
          this.DocLink('《隐私政策》', 'privacy')
        }
        .width('100%')
        .margin({ top: 8, bottom: 20 })

        // ---------- 勾选行（默认不勾选，合规红线） ----------
        Row() {
          this.CheckBox()
          Text('我已阅读并同意《隐私政策》')
            .fontSize(14)
            .fontColor(this.theme().onSurface)
            .layoutWeight(1)
            .lineHeight(20)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.agreed = !this.agreed;
        })
        .margin({ bottom: 18 })

        // ---------- 操作按钮 ----------
        Text('同意并继续')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width('100%')
          .height(48)
          .textAlign(TextAlign.Center)
          .borderRadius(24)
          .backgroundColor(this.agreed ? this.theme().primary : this.theme().cancelBtn)
          .onClick(() => this.onAgree())

        Text('不同意，退出应用')
          .fontSize(14)
          .fontColor(this.theme().onSurfaceVariant)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 8 })
          .onClick(() => this.onDecline())
      }
      .width('100%')
      .padding(22)
      .borderRadius(20)
      .backgroundColor(this.theme().glassCard)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 60, bottom: 40 })
    .justifyContent(FlexAlign.Center)
    .linearGradient({
      angle: 135,
      colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
    })
  }
}
