import router from '@ohos.router';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 《隐私政策》阅读页（纯本地文本，不联网、不申请任何权限）。
 *
 * 合规说明：
 * - 正文来自项目已对外托管的 `privacy.html`（主人确认过的正式文案），此处为应用内离线副本；
 *   两端（网页与应用内）文案需保持一致，改动时请同步 `privacy.html`（根目录 + `release/`）与 GitHub Pages。
 * - **《用户协议》已于 2026-09-21 暂时撤下**：原正文为草案占位，待主人/法务确认正式文本后再恢复入口。
 *   草案正文可从 git 历史找回（v1.3.0 的 `pages/PrivacyDoc.ets`，含 `AGREEMENT_BLOCKS`）。
 *   恢复时需同步三处：本页分支、`pages/PrivacyGate` 的入口与勾选文案、设置页入口。
 *
 * 2026-09-21 按《华为应用市场审核指南》(doc/app/50104) 第 7 章补齐：
 * - 7.x「双清单」→ 第 2、3 条显式列出「已收集个人信息清单」「第三方共享个人信息清单」
 * - 7.6 撤销同意 → 第 8 条写明「设置 → 隐私 → 撤回隐私同意」路径（设置页已提供入口）
 * - 7.3 投诉时效 → 第 11 条承诺 15 个工作日内回复处理
 * - 7.1 / 11.2 真实开发者与联系方式 → 第 11 条（⚠️ 主体名称与邮箱待主人填写，否则信息不实有风险）
 * - 7.3 账号注销 → 第 8 条声明「本应用无账号体系，不涉及注销」
 */

interface DocBlock {
  title: string;
  body: string;
}

/** 隐私政策正文（与 privacy.html 一致，更新日期 2026-09-21） */
const PRIVACY_BLOCKS: DocBlock[] = [
  {
    title: '前言',
    body: '本隐私政策适用于「时间戳记录器」（包名 com.timestamp.recorder，以下简称"本应用"）。我们深知个人信息的重要性，并致力于保护你的隐私。本政策用通俗语言说明本应用如何处理你的数据。'
  },
  {
    title: '1. 我们不收集任何个人信息',
    body: '本应用不收集、不传输、不存储任何个人身份信息、位置信息、通讯录、相册、设备标识（如 OAID/IMEI）等数据。应用内没有任何账号体系、没有云同步、没有行为统计。'
  },
  {
    title: '2. 已收集个人信息清单',
    body: '依据相关法律法规要求，我们以清单形式列明本应用收集的个人信息：\n\n【已收集个人信息清单】\n· 无。本应用为纯本地单机工具，不收集任何个人信息。\n\n需要说明的是，你创建的事件名称、事件颜色，以及每一次记录的时间戳，属于你自己的本地数据，仅保存在你的设备中，我们不会读取、上传、收集或共享。'
  },
  {
    title: '3. 第三方共享个人信息清单',
    body: '【第三方共享个人信息清单】\n· 无。本应用未接入任何第三方 SDK，不存在向任何第三方共享、转让、公开披露或出售个人信息的行为，也不存在个人信息出境情形。'
  },
  {
    title: '4. 数据完全存储在本地',
    body: '你创建的事件（如"喝水""吃药""打卡"）和每一次记录的时间戳，仅保存在你设备的应用沙箱私有存储中，不会上传到任何服务器。本应用不参与系统的数据备份与恢复，换机迁移请通过「设置 → 数据备份 → 导出 JSON」自行完成。卸载应用会删除这些数据。'
  },
  {
    title: '5. 不申请任何权限',
    body: '本应用为纯本地工具，不申请网络、存储、相机、位置等任何敏感权限。桌面卡片为系统服务卡片能力，仅用于在桌面展示你的事件信息并提供点击记录，不涉及个人信息收集。'
  },
  {
    title: '6. 无第三方 SDK',
    body: '本应用不含任何广告、统计、推送等第三方 SDK，不存在数据共享、出售或跨境传输行为。'
  },
  {
    title: '7. 你的数据控制权',
    body: '· 随时可删除单个事件、单条记录或全部数据；\n· 支持一键导出全部数据为 JSON 备份文件；\n· 卸载应用即彻底清除本地数据。'
  },
  {
    title: '8. 你的权利与行使方式',
    body: '· 撤回同意：进入「设置 → 隐私 → 撤回隐私同意」即可撤回你对本隐私政策的同意。撤回后本应用会重新展示本政策并再次征得你的同意；撤回不影响撤回前基于你的同意已进行的处理。\n· 查询与更正：你可在应用内直接查看、修改事件名称与颜色。\n· 删除：可删除单个事件、单条记录，或在设置中清除全部数据；卸载应用将彻底删除本地数据。\n· 导出：进入「设置 → 数据备份 → 导出备份」，可将全部数据导出为 JSON 文件。\n· 注销账号：本应用无账号体系，不涉及账号注册与注销。'
  },
  {
    title: '9. 未成年人保护',
    body: '本应用不涉及任何用户注册与内容提交，对未成年人同样无任何信息收集行为。'
  },
  {
    title: '10. 政策更新',
    body: '如本政策发生变化，我们将在应用内更新并标注新的生效日期，并在版本更新后重新征得你的同意。'
  },
  {
    title: '11. 联系我们',
    body: '开发者：【待填 · 开发者主体名称】\n联系邮箱：【待填 · 联系邮箱】\n\n你也可以通过 GitHub 仓库 github.com/baoru0908/timestamp-recorder-harmony 提交 Issue 反馈（此地址仅作文本展示，应用内不提供跳转）。\n\n我们将在收到你的请求后 15 个工作日内予以回复与处理。'
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
        Text('隐私政策')
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
