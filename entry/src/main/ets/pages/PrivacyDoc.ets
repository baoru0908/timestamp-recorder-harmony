import router from '@ohos.router';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 《隐私声明》阅读页（纯本地文本，不联网、不申请任何权限）。
 *
 * ⚠️⚠️ **本页正文必须与华为「标准化隐私声明托管服务」页面逐字一致**（主人 2026-09-21 明确要求）。
 *   托管页（AGC 提审所填链接）：
 *   https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2040662224829215808
 *   - 三处副本须同步：根 `privacy.html` → `release/privacy.html` → 本文件 `PRIVACY_BLOCKS`
 *   - 改动流程：先改 `privacy.html`（单一事实源）→ `cp privacy.html release/privacy.html` →
 *     同步本文件 → 推送（GitHub Pages）
 *
 * 🔥 **核验方式红线**：托管页是 SPA，**不能用 `--dump-dom` 判断"显示了什么"** ——
 *   DOM 里含大量 `display:none` 隐藏模板节点（例如 `undefined 信息访问`、`2. 设备权限调用`
 *   标题是 JS 通过样式表隐藏的，inline style 上根本看不出来）。判断可见内容**必须以截图为权威**：
 *   `msedge --headless=new --window-size=1200,2600 --screenshot=out.png "<url>"`
 *   另：该页 `Cache-Control: max-age=600`，改动后要等 10 分钟再核验。
 *
 * 2026-09-21（v1.4.5）：正文按托管页可见内容**逐字重写**为 4 节结构
 * （1 收集使用 / 2 管理您的个人信息 / 3 信息存储地点及期限 / 4 如何联系我们）。
 * - **《用户协议》已于 2026-09-21 暂时撤下**：草案正文可从 git 历史找回（v1.3.0 的
 *   `pages/PrivacyDoc.ets`，含 `AGREEMENT_BLOCKS`）。恢复时需同步三处：本页分支、
 *   `pages/PrivacyGate` 的入口与勾选文案、设置页入口。
 */

interface DocBlock {
  title: string;
  body: string;
}

/**
 * 隐私声明正文（**与托管页可见内容逐字一致**，更新/生效日期 2026.9.21）。
 * `title` 为空表示该块在托管页没有标题（仅前言段），渲染时只出正文。
 */
const PRIVACY_BLOCKS: DocBlock[] = [
  {
    title: '',
    body: '时间戳记录器 是由 李保如 （以下简称"我们"）为您提供的，用于随手记录事件时间（段）的应用。本隐私声明由我们为处理您的个人信息而制定。\n\n我们非常重视您的个人信息和隐私保护，将会按照法律要求和业界成熟的安全标准，为您的个人信息提供相应的安全保护措施。'
  },
  {
    title: '1. 我们如何收集和使用您的个人信息',
    body: '我们仅在有合法性基础的情形下才会使用您的个人信息。根据适用的法律，我们可能会基于您的同意、为履行/订立您与我们的合同所必需、履行法定义务所必需等合法性基础，使用您的个人信息。\n\n1.1 基于履行法定义务或其他法律法规规定的情形，我们可能会处理您的以下个人信息：\n\n为了实现应用功能，在获取您的同意后我们需要收集您的事件操作记录。\n\n数据仅存储在设备本地应用私有空间，不通过网络传输'
  },
  {
    title: '2. 管理您的个人信息',
    body: '如您对您的数据主体权利有进一步要求或存在任何疑问、意见或建议，可通过本声明中"如何联系我们"章节中所述方式与我们取得联系，并行使您的相关权利。'
  },
  {
    title: '3. 信息存储地点及期限',
    body: '3.1 我们承诺，除法律法规另有规定外，我们对您的信息的保存期限应当为实现处理目的所必要的最短时间。\n\n3.2 上述信息将会传输并保存至您本地的服务器。'
  },
  {
    title: '4. 如何联系我们',
    body: '您可通过以下方式联系我们，并行使您的相关权利，我们会尽快回复。\n\n邮箱：2433283150@qq.com\n\n如果您对我们的回复不满意, 特别是当个人信息处理行为损害了您的合法权益时您还可以通过向有管辖权的人民法院提起诉讼、向行业自律协会或政府相关管理机构投诉等外部途径进行解决。 您也可以向我们了解可能适用的相关投诉途径的信息。'
  }
];

@Entry
@Component
struct PrivacyDoc {
  @StorageProp('isDark') isDark: boolean = false;

  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  build() {
    Column() {
      // ---------- 顶栏 ----------
      Row() {
        Text('←')
          .fontSize(26)
          .fontColor(this.theme().onSurface)
          .padding({ left: 16, right: 8, top: 6, bottom: 6 })
          .onClick(() => router.back())
        Text('隐私声明')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
          .layoutWeight(1)
          .margin({ left: 4 })
      }
      .width('100%')
      .padding({ left: 4, right: 12, top: 30, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

      Scroll() {
        Column() {
          // 标题与「更新日期」——与托管页一致
          Text('关于时间戳记录器与隐私的声明')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().onSurface)
            .width('100%')
            .margin({ top: 4, bottom: 4 })
          Text('更新日期：2026.9.21')
            .fontSize(12)
            .fontColor(this.theme().onSurfaceVariant)
            .width('100%')
            .margin({ bottom: 6 })

          ForEach(PRIVACY_BLOCKS, (b: DocBlock) => {
            Column() {
              // 前言块在托管页没有标题 → title 为空时不出标题
              if (b.title.length > 0) {
                Text(b.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme().onSurface)
                  .width('100%')
                  .margin({ top: 18, bottom: 6 })
              }
              Text(b.body)
                .fontSize(14)
                .fontColor(this.theme().onSurfaceVariant)
                .width('100%')
                .lineHeight(22)
                .margin({ top: b.title.length > 0 ? 0 : 6 })
            }
            .width('100%')
          }, (b: DocBlock) => b.title + b.body.substring(0, 8))

          Text('生效日期：2026.9.21')
            .fontSize(12)
            .fontColor(this.theme().onSurfaceVariant)
            .width('100%')
            .margin({ top: 24, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 28 })
      }
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
}
