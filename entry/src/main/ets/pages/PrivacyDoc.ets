import router from '@ohos.router';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 《隐私声明》阅读页（纯本地文本，不联网、不申请任何权限）。
 *
 * 合规说明：
 * - **单一事实源 = 根目录 `privacy.html`**；本页是其离线副本，两端文案须一致。
 *   改动流程：改 `privacy.html` → `cp privacy.html release/privacy.html` → 本文件 → 推送（GitHub Pages）。
 * - **《用户协议》已于 2026-09-21 暂时撤下**：原正文为草案占位，待主人/法务确认正式文本后再恢复入口。
 *   草案正文可从 git 历史找回（v1.3.0 的 `pages/PrivacyDoc.ets`，含 `AGREEMENT_BLOCKS`）。
 *   恢复时需同步三处：本页分支、`pages/PrivacyGate` 的入口与勾选文案、设置页入口。
 *
 * 2026-09-21（v1.4.5）**与华为托管页对齐重写**：
 * - 标题与结构改为与托管页同构：《关于时间戳记录器与隐私的声明》→ 1 收集使用 / 2 权利行使 /
 *   3 存储地点及期限 / 4 联系我们 / 5 第三方共享与 SDK / 6 未成年人保护 / 7 政策更新
 * - 采纳托管页的关键表述：「数据仅存储在设备本地应用私有空间，不通过网络传输」「保存期限为实现处理
 *   目的所必要的最短时间」「上述信息仅保存在您的设备本地」
 * - **补足托管页缺的 3 项**（应用内更严谨，两边核心事实一致、措辞可不同）：
 *   ① 权利行使途径（7.3 / 7.6）② 第三方共享与 SDK 声明（7.2 + 双清单）③ 未成年人保护（第 8 章）
 * - **修掉托管页 2 处措辞问题**：① 托管页写「需要收集您的事件操作记录」→ 本页明确「不收集任何个人信息」；
 *   ② 托管页写「传输并保存至您本地的服务器」→ 本页写「仅保存在您的设备本地，不会传输至任何服务器」
 *
 * 对外托管声明（AGC 提审时填此链接）：
 *   https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2040662224829215808
 *   ⚠️ 应用零联网，故应用内必须自带正文（不引用外链）。
 */

interface DocBlock {
  title: string;
  body: string;
}

/** 隐私声明正文（与根目录 `privacy.html` 一致，生效日期 2026-09-21） */
const PRIVACY_BLOCKS: DocBlock[] = [
  {
    title: '前言',
    body: '时间戳记录器 是由 李保如（以下简称"我们"）为您提供的，用于随手记录事件时间（段）的应用。本隐私声明由我们为处理您的个人信息而制定。\n\n我们非常重视您的个人信息和隐私保护，并将按照法律要求和业界成熟的安全标准，为您的个人信息提供相应的安全保护措施。'
  },
  {
    title: '1. 我们如何收集和使用您的个人信息',
    body: '本应用不收集您的任何个人信息。\n\n您创建的事件、每一次记录的时间戳，以及事件名称与颜色等设置，属于您自己的数据，我们不会读取、上传、收集或共享。\n\n1.1 数据仅存储在设备本地应用私有空间，不通过网络传输，也不参与系统级备份与恢复。卸载应用即彻底删除这些数据。'
  },
  {
    title: '2. 您的权利与行使方式',
    body: '您可以在应用内直接行使以下权利：\n\n· 查询与更正：在应用内查看并修改事件名称与颜色；\n· 删除数据：进入「设置 → 数据备份」清除全部数据，也可删除单个事件或单条记录；卸载应用即彻底删除本地数据；\n· 导出：进入「设置 → 数据备份 → 导出备份」，可将全部数据导出为 JSON 文件；\n· 撤回同意：进入「设置 → 隐私 → 撤回隐私同意」，撤回后我们会重新征得您的同意；撤回不影响撤回前基于您的同意已进行的处理；\n· 账号注销：本应用无账号体系，不涉及账号注册与注销。\n\n如您对您的数据主体权利有进一步要求，或存在任何疑问、意见或建议，可通过本声明第 4 节所述方式与我们取得联系，并行使您的相关权利。'
  },
  {
    title: '3. 信息存储地点及期限',
    body: '3.1 我们承诺，除法律法规另有规定外，我们对您信息的保存期限应当为实现处理目的所必要的最短时间。\n\n3.2 上述信息仅保存在您的设备本地，我们不会将其传输至任何服务器。'
  },
  {
    title: '4. 如何联系我们',
    body: '开发者：李保如（个人开发者）\n联系邮箱：2433283150@qq.com\n\n您可通过以上方式联系我们，并行使您的相关权利，我们将在收到您的请求后 15 个工作日内予以回复与处理。\n\n如果您对我们的回复不满意，特别是当个人信息处理行为损害了您的合法权益时，您还可以通过向有管辖权的人民法院提起诉讼、向行业自律协会或政府相关管理机构投诉等外部途径进行解决。您也可以向我们了解可能适用的相关投诉途径的信息。'
  },
  {
    title: '5. 第三方共享与 SDK',
    body: '本应用未接入任何第三方 SDK，不含任何广告、统计或推送服务，不存在向任何第三方共享、转让或公开披露您个人信息的行为，也不存在个人信息出境情形。\n\n【第三方共享个人信息清单】\n· 无。'
  },
  {
    title: '6. 未成年人保护',
    body: '本应用不涉及用户注册与内容提交，不收集任何未成年人个人信息。'
  },
  {
    title: '7. 政策更新',
    body: '如本声明发生变化，我们将在应用内与对外页面同步更新并标注新的生效日期，并在版本更新后重新征得您的同意。'
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
          Text('关于时间戳记录器与隐私的声明')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().onSurface)
            .width('100%')
            .margin({ top: 4, bottom: 4 })

          ForEach(PRIVACY_BLOCKS, (b: DocBlock) => {
            Column() {
              Text(b.title)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme().onSurface)
                .width('100%')
                .margin({ top: 18, bottom: 6 })
              Text(b.body)
                .fontSize(14)
                .fontColor(this.theme().onSurfaceVariant)
                .width('100%')
                .lineHeight(22)
            }
            .width('100%')
          }, (b: DocBlock) => b.title)

          Text('更新日期：2026-09-21')
            .fontSize(12)
            .fontColor(this.theme().onSurfaceVariant)
            .width('100%')
            .margin({ top: 24, bottom: 4 })
          Text('生效日期：2026-09-21')
            .fontSize(12)
            .fontColor(this.theme().onSurfaceVariant)
            .width('100%')
            .margin({ bottom: 8 })
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
