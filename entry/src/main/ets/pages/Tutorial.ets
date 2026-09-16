import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import router from '@ohos.router';
import { getTheme, ThemeColors } from '../util/Theme';

/** GitHub 完整图文（联网时的补充入口） */
const TUTORIAL_URL: string = 'https://github.com/baoru0908/timestamp-recorder-harmony#tutorial';

/**
 * 使用教程（App 内置原生页，离线可读）。
 *
 * 对齐 Android v4.1.0 `TutorialActivity`：把最常用、最短的内容内置进来 ——
 * 三步上手 + 桌面卡片重点引导（本 App 核心特色），GitHub 仅作联网时的补充入口。
 * （旧版是 WebView 加载 GitHub，国内常连不上，已弃用。）
 */
@Entry
@Component
struct Tutorial {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('statusBarHeight') statusBarH: number = 0;
  @StorageProp('navBarHeight') navBarH: number = 0;

  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  /** 用系统浏览器打开外链 */
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
        Text('使用教程')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
      }
      .width('100%')
      .padding({ left: 4, right: 12, top: this.statusBarH + 6, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

      // ---------- 内容 ----------
      Scroll() {
        Column() {
          // 1. 三步上手
          this.InfoCard('三步上手', [
            '① 新建事件：点底部正中间的圆形「＋」，输入名字（如「喝水」「吃药」），选个颜色，保存。',
            '② 记一条：点事件卡片最右边的彩色按钮，立刻写入当前时间（毫秒级），不用进详情页。',
            '③ 看记录：左右滑动切到「时间线」，所有记录按事件颜色串成一条线；右上角「⋮」里还有统计图表。'
          ])

          // 2. 桌面卡片（核心特色，重点引导）
          Column() {
            Text('桌面卡片 · 点一下就记')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().primary)
              .width('100%')
            Text('把记录按钮直接放到桌面上 —— 不用打开 App，点一下就写好一条时间戳。三种形态：\n\n· 全部事件：列表按钮，点哪行记哪个\n· 单事件：大按钮，可拉伸换版式\n· 胶囊：横条，省地方')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .lineHeight(20)
              .width('100%')
              .margin({ top: 8 })

            Text('怎么加到桌面')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().onSurface)
              .width('100%')
              .margin({ top: 14 })

            Text('方式一 · 一键添加（推荐先试）')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().primary)
              .width('100%')
              .margin({ top: 8 })
            Text('在设置 → 桌面卡片里，点「管理桌面卡片」按引导添加。部分桌面不支持该接口，没反应就换方式二。')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .lineHeight(20)
              .width('100%')
              .margin({ top: 4 })

            Text('方式二 · 手动添加（通用）')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme().primary)
              .width('100%')
              .margin({ top: 12 })
            Text('① 桌面双指捏合 / 长按空白处 →「服务卡片」；\n② 找到「时间戳记录器」，按住想要的卡片拖到桌面；\n③「单事件 / 胶囊」添加后可长按「编辑」绑定事件。')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .lineHeight(20)
              .width('100%')
              .margin({ top: 4 })

            Text('去设置管理卡片')
              .fontSize(14)
              .fontColor(this.theme().onSurface)
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(44)
              .borderRadius(12)
              .border({ width: 1, color: this.theme().glassStroke })
              .margin({ top: 14 })
              .onClick(() => router.pushUrl({ url: 'pages/Settings' }))
          }
          .width('100%')
          .padding(18)
          .backgroundColor(this.theme().glassCard)
          .borderRadius(16)
          .border({ width: 1, color: this.theme().glassStroke })
          .margin({ top: 12 })

          // 3. 事件卡片四个可点区
          this.InfoCard('事件卡片：四个可点区', [
            '· 最左「≡」：按住拖动排序（手动排序模式）\n· 中间：打开事件详情页\n· 竖排「⋮」：编辑 / 删除事件\n· 最右彩色按钮：直接记一条'
          ])

          // 4. 记录管理
          this.InfoCard('记录管理', [
            '详情页里：点某一行复制时间、长按删除单条；「撤销上一条」救回手滑；右上角「⋮」可批量管理、导出 CSV。删除事件会连同它的全部记录一起删（有确认）。'
          ])

          // 5. 数据安全
          this.InfoCard('数据安全', [
            '数据只存在本机，App 不联网。换机或重装前：设置 → 数据备份 → 导出 JSON；恢复是整体覆盖（恢复前会提示数量）。'
          ])

          // 补充：GitHub 完整文档（联网时可用）
          Text('GitHub 上有更完整的图文说明（需联网）')
            .fontSize(14)
            .fontColor(this.theme().onSurface)
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(48)
            .borderRadius(12)
            .backgroundColor(this.theme().glassCard)
            .border({ width: 1, color: this.theme().glassStroke })
            .margin({ top: 16 })
            .onClick(() => this.openUrl(TUTORIAL_URL))
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

  /** 通用内容卡：标题 + 若干正文段 */
  @Builder
  InfoCard(title: string, lines: string[]) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().onSurface)
        .width('100%')
      ForEach(lines, (line: string) => {
        Text(line)
          .fontSize(13)
          .fontColor(this.theme().onSurfaceVariant)
          .lineHeight(20)
          .width('100%')
          .margin({ top: 8 })
      }, (line: string) => line)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.theme().glassCard)
    .borderRadius(16)
    .border({ width: 1, color: this.theme().glassStroke })
    .margin({ top: 12 })
  }
}
