import { bundleManager, common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import router from '@ohos.router';
import { getTheme, ThemeColors } from '../util/Theme';

const URL_PROFILE: string = 'https://github.com/baoru0908';
// ⚠️ 本 App（鸿蒙版）的源码仓库是 timestamp-recorder-harmony，不是 Android 版那个仓库：
//    跳过去要能看到「当前这个 App」的源码、README、Release。
const URL_REPO: string = 'https://github.com/baoru0908/timestamp-recorder-harmony';
const URL_ISSUES: string = 'https://github.com/baoru0908/timestamp-recorder-harmony/issues';

/**
 * 关于页（对齐 Android `AboutActivity`）：版本信息、开发者卡片、项目说明、开源与隐私说明、GitHub 入口。
 * 开发者头像与署名离线打包（App 零网络权限场景也能展示），点击交给系统浏览器。
 */
@Entry
@Component
struct About {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('statusBarHeight') statusBarH: number = 0;
  @StorageProp('navBarHeight') navBarH: number = 0;

  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  private versionText(): string {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return `版本 ${info.versionName}（${info.versionCode}）`;
    } catch (err) {
      return '版本 1.0.0（1）';
    }
  }

  private openUrl(url: string): void {
    // ⚠️ startAbility 在 UIAbilityContext 上，common.Context 没有该方法（编译期就会报）；
    //    且 getHostContext() 可能为空，直接 as 强转后调用会崩 → 先判空。
    const host: common.Context | undefined = this.getUIContext().getHostContext();
    if (host === undefined) {
      promptAction.showToast({ message: '打开链接失败，请稍后再试' });
      return;
    }
    const ctx: common.UIAbilityContext = host as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    // 无浏览器等场景：原先静默吞掉 → 用户以为「点了没反应」；这里明确提示并可复制地址
    ctx.startAbility(want).catch(() => {
      promptAction.showToast({ message: `未能打开浏览器，请手动访问：${url}`, duration: 4000 });
    });
  }

  build() {
    Column() {
      // ---------- 顶栏（玻璃，沉浸式延伸到状态栏） ----------
      Row() {
        Text('←')
          .fontSize(26)
          .fontColor(this.theme().onSurface)
          .padding({ left: 16, right: 8, top: 6, bottom: 6 })
          .onClick(() => router.back())
        Text('关于')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
      }
      .width('100%')
      .padding({ left: 4, right: 12, top: this.statusBarH + 6, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

      Scroll() {
        Column() {
          // ---------- 头部：图标 + 名称 + 版本 ----------
          Column() {
            Image($r('app.media.startIcon'))
              .width(84)
              .height(84)
              .borderRadius(22)
              .border({ width: 1, color: this.theme().glassStroke })
            Text('时间戳记录器')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().onSurface)
              .margin({ top: 14 })
            Text(this.versionText())
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .margin({ top: 4 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })

          // ---------- 开发者卡片 ----------
          Row() {
            Image($r('app.media.dev_avatar'))
              .width(56)
              .height(56)
              .borderRadius(28)
              .border({ width: 1, color: this.theme().glassStroke })
            Column() {
              Text('开发者')
                .fontSize(11)
                .fontColor(this.theme().onSurfaceVariant)
              Text('Bao_ru')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme().onSurface)
                .margin({ top: 2 })
              Text('GitHub @baoru0908')
                .fontSize(13)
                .fontColor(this.theme().primary)
                .margin({ top: 2 })
              Text('独立开发者 · 主贡献者 · 灵感来源')
                .fontSize(12)
                .fontColor(this.theme().onSurfaceVariant)
                .margin({ top: 4 })
              Text('点此查看我的 GitHub 主页')
                .fontSize(11)
                .fontColor(this.theme().onSurfaceVariant)
                .margin({ top: 6 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 14 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.theme().glassCard)
          .borderRadius(16)
          .border({ width: 1, color: this.theme().glassStroke })
          .margin({ top: 12 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.openUrl(URL_PROFILE))

          // ---------- 关于本项目 ----------
          this.InfoCard('关于本项目',
            '一款完全离线、零权限的时间戳记录工具：在 App 内或桌面卡片单击，即可为任意事件快速记下一笔当前时间。')

          // ---------- 开源与隐私 ----------
          Column() {
            Text('开源与隐私')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().onSurface)
              .width('100%')
            // ⚠️ 此处曾写「界面字体采用小米 MiSans」，但本工程**没有内置任何字体文件**（用的是系统字体，
            //    MiSans 是 Android 版的做法）→ 文案与实际不符，2026-09-16 修正。
            Text('界面使用系统默认字体，未内置任何字体文件；代码均为原创、不依赖任何第三方库，图标为自绘矢量图。欢迎在 GitHub 查看源码、提交反馈或参与改进。')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .lineHeight(20)
              .width('100%')
              .margin({ top: 8 })
            Text('应用不申请任何权限、不发起网络请求，所有数据只保存在本机；打开外部链接时交给系统浏览器处理。')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .lineHeight(20)
              .width('100%')
              .margin({ top: 8 })
          }
          .width('100%')
          .padding(18)
          .backgroundColor(this.theme().glassCard)
          .borderRadius(16)
          .border({ width: 1, color: this.theme().glassStroke })
          .margin({ top: 12 })

          // ---------- 操作 ----------
          Text('在 GitHub 查看源码')
            .fontSize(16)
            .fontColor(this.theme().white)
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(56)
            .borderRadius(12)
            .backgroundColor(this.theme().primary)
            .margin({ top: 16 })
            .onClick(() => this.openUrl(URL_REPO))

          Text('问题反馈 / 建议')
            .fontSize(16)
            .fontColor(this.theme().onSurface)
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(56)
            .borderRadius(12)
            .border({ width: 1, color: this.theme().glassStroke })
            .margin({ top: 12 })
            .onClick(() => this.openUrl(URL_ISSUES))

          Text('时间戳记录器 · 完全离线 · 无广告')
            .fontSize(11)
            .fontColor(this.theme().onSurfaceVariant)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 16, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 28 + this.navBarH })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
    })
  }

  /** 通用内容卡：标题 + 正文 */
  @Builder
  InfoCard(title: string, body: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().onSurface)
        .width('100%')
      Text(body)
        .fontSize(13)
        .fontColor(this.theme().onSurfaceVariant)
        .lineHeight(20)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.theme().glassCard)
    .borderRadius(16)
    .border({ width: 1, color: this.theme().glassStroke })
    .margin({ top: 12 })
  }
}
