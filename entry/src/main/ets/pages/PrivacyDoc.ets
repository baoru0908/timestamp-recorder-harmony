import router from '@ohos.router';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 《隐私政策》/《用户协议》阅读页（纯本地文本，不联网、不申请任何权限）。
 *
 * 合规说明：
 * - **隐私政策正文**来自项目已对外托管的 `release/privacy.html`（主人确认过的正式文案），此处为应用内离线副本；
 *   两端（网页与应用内）文案需保持一致，改动时请同步 `release/privacy.html` 与 GitHub Pages。
 * - **用户协议**目前是**草案占位**，顶部有醒目警示条。正式发布前必须由主人/法务确认并替换正文，
 *   当前文本仅用于说明协议范围与结构，不构成正式法律文本。
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
    body: '你创建的事件（如"喝水""吃药""打卡"）和每一次记录的时间戳，仅保存在你设备的应用沙箱私有存储中，不会上传到任何服务器。卸载应用会删除这些数据，请提前使用应用内"数据备份"功能导出。'
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
    body: '如有任何疑问，可通过 GitHub 仓库 github.com/baoru0908/timestamp-recorder-harmony 提交 Issue 与我们联系。'
  }
];

/**
 * 用户协议正文 —— ⚠️ 草案占位，非最终法律文本。
 * 正式发布前必须由主人/法务确认替换；此处仅说明范围与结构，避免开发期出现空文档。
 */
const AGREEMENT_BLOCKS: DocBlock[] = [
  {
    title: '1. 服务内容',
    body: '本应用是一款本地时间戳记录工具，提供事件创建、时间戳记录、时间线查看、统计图表、桌面卡片与数据备份导出等功能。全部功能均在你的设备本机完成，不依赖任何服务器。'
  },
  {
    title: '2. 使用规范',
    body: '你应自行负责所创建事件名称等内容的合法性，不得将本应用用于记录或传播违反法律法规的信息。'
  },
  {
    title: '3. 数据与备份',
    body: '数据仅存储于本机；导出备份时由你自行选择保存位置并自行保管。因设备损坏、卸载应用、备份文件丢失等原因造成的数据损失，本应用不承担责任，请定期自行导出备份。'
  },
  {
    title: '4. 免责声明',
    body: '本应用按"现状"提供，不对记录数据的准确性、完整性、连续性作任何明示或默示担保。'
  },
  {
    title: '5. 协议变更',
    body: '如本协议发生更新，我们将在应用内提示，并在版本更新后重新征得你的同意。若你不同意更新后的协议，可停止使用并卸载本应用。'
  }
];

@Entry
@Component
struct PrivacyDoc {
  @State isPrivacy: boolean = true;
  @StorageProp('isDark') isDark: boolean = false;

  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    const doc: string = (params['doc'] as string) ?? 'privacy';
    this.isPrivacy = doc !== 'agreement';
  }

  private title(): string {
    return this.isPrivacy ? '隐私政策' : '用户协议';
  }

  private blocks(): DocBlock[] {
    return this.isPrivacy ? PRIVACY_BLOCKS : AGREEMENT_BLOCKS;
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
        Text(this.title())
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
          // 用户协议：醒目草案警示（隐私政策为正式文案，不显示）
          if (!this.isPrivacy) {
            Column() {
              Text('⚠️ 本文档为草案占位')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme().danger)
                .width('100%')
              Text('正式发布前需替换为经确认的法律文本。当前内容仅用于说明协议范围与结构，不构成正式法律文本。')
                .fontSize(13)
                .fontColor(this.theme().onSurfaceVariant)
                .width('100%')
                .margin({ top: 6 })
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor(this.theme().glassCard)
            .border({ width: 1, color: this.theme().danger })
            .margin({ bottom: 16 })
          }

          ForEach(this.blocks(), (b: DocBlock) => {
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

          Text(this.isPrivacy ? '更新日期：2026-09-16' : '状态：草案 · 待确认')
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
