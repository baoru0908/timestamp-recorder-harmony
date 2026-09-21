import { bundleManager, common } from '@kit.AbilityKit';
import { EventRepository } from '../data/EventRepository';

/** 隐私同意状态持久化的键（存已同意时的 versionName） */
const KEY_AGREED_VERSION: string = 'privacy_agreed_version';

/**
 * 隐私合规工具：判断用户是否已同意当前版本的《隐私政策》。
 *
 * 触发规则（鸿蒙应用市场合规要求）：
 * - 首次启动：从未同意过 → 必须弹出
 * - 版本更新后：已同意的版本号 ≠ 当前版本号 → 重新弹出并再次征得同意
 * - 已同意当前版本：直接进主页
 */
export class Privacy {
  /** 当前应用版本名（versionName）；取不到返回空串 */
  static currentVersion(): string {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (err) {
      return '';
    }
  }

  /** 是否已同意当前版本 */
  static hasAgreed(ctx: common.Context): boolean {
    const cur: string = Privacy.currentVersion();
    if (cur.length === 0) {
      // 取不到版本号时降级为「只需同意一次」，避免用户永远卡在弹窗
      return new EventRepository(ctx).getPrefStr(KEY_AGREED_VERSION, '').length > 0;
    }
    return new EventRepository(ctx).getPrefStr(KEY_AGREED_VERSION, '') === cur;
  }

  /** 记录已同意当前版本 */
  static setAgreed(ctx: common.Context): void {
    const cur: string = Privacy.currentVersion();
    new EventRepository(ctx).setPrefStr(KEY_AGREED_VERSION, cur.length === 0 ? 'agreed' : cur);
  }

  /**
   * 清除同意状态并回到合规门。
   *
   * 调用方：`pages/Settings` 的「撤回隐私同意」（经二次确认弹窗）。
   * 依据《华为应用市场审核指南》7.6「提供简单的撤销同意方式」—— 必须给用户可撤回的途径，
   * 同时用二次确认避免误触导致无谓地重新过一遍合规门。
   * 仅清除同意标记，不触碰任何本地数据。
   */
  static reset(ctx: common.Context): void {
    new EventRepository(ctx).setPrefStr(KEY_AGREED_VERSION, '');
  }
}
