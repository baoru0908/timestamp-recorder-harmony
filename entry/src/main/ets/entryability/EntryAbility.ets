/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import BuildProfile from 'BuildProfile';
import { Privacy } from '../util/Privacy';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  /** 合规：生命周期类调试日志只在 debug 包输出，release 包静默 */
  private logInfo(msg: string): void {
    if (BuildProfile.DEBUG) {
      hilog.info(DOMAIN, 'appTag', '%{public}s', msg);
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'appTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 初始化全局深浅色标志（跟随系统），页面用 @StorageProp('isDark') 绑定
    AppStorage.setOrCreate<boolean>('isDark',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.logInfo('Ability onCreate');
  }

  /** 系统深浅色切换时全局更新，驱动所有页面换肤 */
  onConfigurationUpdate(newConfig: Configuration): void {
    const dark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate<boolean>('isDark', dark);
    this.applyImmersive(); // 深浅色切换时同步刷新状态栏 / 导航条图标颜色
    this.logInfo(`colorMode changed, isDark=${dark}`);
  }

  onDestroy(): void {
    this.logInfo('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    this.logInfo('Ability onWindowStageCreate');

    // 隐私合规门：未同意当前版本则先弹《隐私政策》《用户协议》，同意后再进主页
    const target: string = Privacy.hasAgreed(this.context) ? 'pages/Index' : 'pages/PrivacyGate';
    windowStage.loadContent(target, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'appTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.logInfo('Succeeded in loading the content.');
    });

    // 沉浸式：内容延伸到状态栏 / 导航条之下，系统栏透明；避让区高度写入 AppStorage 供页面 padding
    windowStage.getMainWindow().then((win: window.Window) => {
      this.mainWindow = win;
      win.setWindowLayoutFullScreen(true).then(() => {
        this.applyImmersive();
      }).catch(() => {
        hilog.error(DOMAIN, 'appTag', '%{public}s', 'setWindowLayoutFullScreen failed');
      });
      win.on('avoidAreaChange', () => this.applyImmersive());
    }).catch(() => {
      hilog.error(DOMAIN, 'appTag', '%{public}s', 'getMainWindow failed');
    });
  }

  /**
   * 沉浸式：全屏布局 + 系统栏透明，并把避让区高度（状态栏 / 小白条）写入 AppStorage。
   * 页面用 @StorageProp('statusBarHeight') / @StorageProp('navBarHeight') 读去做 padding，
   * 从而实现「内容顶到状态栏、时间线穿透头尾」，且交互元素不被遮挡。
   */
  private applyImmersive(): void {
    const win: window.Window | null = this.mainWindow;
    if (win === null) {
      return;
    }
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const d: number = density > 0 ? density : 1;
      const statusPx: number = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const navPx: number = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height;
      AppStorage.setOrCreate<number>('statusBarHeight', statusPx / d);
      AppStorage.setOrCreate<number>('navBarHeight', navPx / d);
      const dark: boolean = AppStorage.get<boolean>('isDark') ?? false;
      const icon: string = dark ? '#FFFFFF' : '#000000';
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: icon,
        navigationBarColor: '#00000000',
        navigationBarContentColor: icon
      }).catch(() => {});
    } catch (err) {
      hilog.error(DOMAIN, 'appTag', 'applyImmersive failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    this.logInfo('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    this.logInfo('Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    this.logInfo('Ability onBackground');
  }
}