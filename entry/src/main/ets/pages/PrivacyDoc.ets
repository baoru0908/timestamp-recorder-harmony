import router from '@ohos.router';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 《隐私政策》阅读页（纯本地文本，不联网、不申请任何权限）。
 *
 * 合规说明：
 * - 正文来自项目已对外托管的 `release/privacy.html`（主人确认过的正式文案），此处为应用内离线副本；
 *   两端（网页与应用内）文案需保持一致，改动时请同步 `release/privacy.html` 与 GitHub Pages。
 * - **《用户协议》已于 2026-09-21 暂时撤下**：原正文为草案占位，待主人/法务确认正式文本后再恢复入口。
 *   草案正文可从 git 历史找回（v1.3.0 的 `pages/PrivacyDoc.ets`，含 `AGREEMENT_BLOCKS`）。
 *   恢复时需同步三处：本页分支、`pages/PrivacyGate` 的入口与勾选文案、设置页入口。
 */

interface DocBlock {
  title: string;
  body: string;
}

/** 隐私政策正文（与 release/privacy.html 一致，更新日期 2026-09-16） */
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
    title: '2. 数据完全存储在本地',
    body: '你创建的事件（如"喝水""吃药""打卡"）和每一次记录的时间戳，仅保存在你设备的应用沙箱私有存储中，不会上传到任何服务器。本应用不参与系统的数据备份与恢复，换机迁移请通过「设置 → 数据备份 → 导出 JSON」自行完成。卸载应用会删除这些数据。'
  },
  {
    title: '3. 不申请任何权限',
    body: '本应用为纯本地工具，不申请网络、存储、相机、位置等任何敏感权限。桌面卡片为系统服务卡片能力，仅用于在桌面展示你的事件信息并提供点击记录，不涉及个人信息收集。'
  },
  {
    title: '4. 无第三方 SDK',
    body: '本应用不含任何广告、统计、推送等第三方 SDK，不存在数据共享、出售或跨境传输行为。'
  },
  {
    title: '5. 你的数据控制权',
    body: '· 随时可删除单个事件、单条记录或全部数据；\n· 支持一键导出全部数据为 JSON 备份文件；\n· 卸载应用即彻底清除本地数据。'
  },
  {
    title: '6. 未成年人保护',
    body: '本应用不涉及任何用户注册与内容提交，对未成年人同样无任何信息收集行为。'
  },
  {
    title: '7. 政策更新',
    body: '如本政策发生变化，我们将在应用内更新并标注新的生效日期，并在版本更新后重新征得你的同意。'
  },
  {
    title: '8. 联系我们',
    body: '如有任何疑问，可通过 GitHub 仓库 github.com/baoru0908/timestamp-recorder-harmony 提交 Issue 与我们联系（此地址仅作文本展示，应用内不提供跳转）。'
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

          Text('更新日期：2026-09-16')
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
