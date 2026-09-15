import { ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 配置页读取的卡片添加 Want（FormConfig 页 import 使用） */
export let formConfigWant: Want | null = null;

/**
 * 服务卡片配置能力（formConfigAbility 指向本能力）：
 * 用户添加单事件 / 胶囊卡片时，桌面拉起本能力 → 加载 pages/FormConfig 选择事件绑定。
 */
export default class FormConfigAbility extends UIAbility {
  onCreate(want: Want): void {
    formConfigWant = want;
    // 独立能力场景（EntryAbility 未启动）也要保证主题标志存在
    AppStorage.setOrCreate<boolean>('isDark',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(0x0001, 'FormConfigAbility', 'onCreate want=%{public}s', JSON.stringify(want));
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/FormConfig', (err) => {
      if (err.code) {
        return;
      }
    });
  }
}
