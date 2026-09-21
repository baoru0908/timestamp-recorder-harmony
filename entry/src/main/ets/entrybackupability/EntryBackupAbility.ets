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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0000;

/**
 * 备份恢复扩展。
 *
 * 合规：`backup_config.json` 的 `allowToBackupRestore` 已置 **false** ——
 * 本应用承诺「数据仅存本机、不上传任何服务器」，因此不参与系统级备份/恢复
 * （换机迁移由用户主动「设置 → 数据备份 → 导出 JSON」完成）。
 * 日志同样只在 debug 包输出。
 */
export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    if (BuildProfile.DEBUG) {
      hilog.info(DOMAIN, 'appTag', 'onBackup ok');
    }
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    if (BuildProfile.DEBUG) {
      hilog.info(DOMAIN, 'appTag', 'onRestore ok %{public}s', JSON.stringify(bundleVersion));
    }
    await Promise.resolve();
  }
}