import formBindingData from '@ohos.app.form.formBindingData';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BuildProfile from 'BuildProfile';
import { EventRepository } from '../data/EventRepository';
import { buildFormData, closeTrackedFds, updateOneForm } from '../util/FormSync';

const DOMAIN = 0x0001;

/**
 * 服务卡片扩展（对齐 Android 四套 WidgetProvider）：
 * - all_events   全事件卡片（最多 4 行 / 4*4 时 6 行，点行即记录）
 * - single_event 单事件卡片（1*2 横条 / 2*2+ 卡片，整卡点击记录）
 * - capsule      胶囊卡片（1*2 横条，事件色填充，点击记录）
 * - custom       自定义卡片（标题 + 背景色/背景图 + 勾选多事件）
 *
 * 事件绑定：单事件 / 胶囊在添加时经 formConfigAbility 配置页选择事件，
 * 绑定存 preferences `form_bind_<formName>` → eventId；自定义卡片配置存
 * `form_custom_title / _bgcolor / _bgimage / _events`。
 */
export default class FormAbility extends FormExtensionAbility {

  onAddForm(want: Want): formBindingData.FormBindingData {
    const name: string = String(want.parameters?.[formInfo.FormParam.NAME_KEY] ?? 'all_events');
    const dim: number = (want.parameters?.[formInfo.FormParam.DIMENSION_KEY] as number) ?? 2;
    const data: Record<string, Object> = buildFormData(this.context, name, dim);
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshAll();
  }

  onFormEvent(formId: string, message: string): void {
    // 合规：卡片消息含卡片实例与事件参数，仅 debug 包输出
    if (BuildProfile.DEBUG) {
      hilog.info(DOMAIN, 'FormAbility', 'onFormEvent formId=%{public}s message=%{public}s', formId, message);
    }
    try {
      const obj: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      // 系统投递格式：{...params, params:{...}, action:"message"}，指令在 params 里
      const params: Record<string, Object> = (obj['params'] as Record<string, Object>) ?? {};
      const action: string = String(params['action'] ?? obj['action'] ?? '');
      const eventId: number = Number(params['eventId'] ?? obj['eventId'] ?? -1);
      if (BuildProfile.DEBUG) {
        hilog.info(DOMAIN, 'FormAbility', 'parsed action=%{public}s eventId=%{public}d', action, eventId);
      }
      if (action === 'record' && eventId > 0) {
        new EventRepository(this.context).addRecord(eventId);
      }
    } catch (err) {
      // 非 JSON 消息忽略
    }
    this.refreshAll();
  }

  onRemoveForm(formId: string): void {
    // 回收该卡片占用的图片 fd；图片文件按 formName 共用，不在此删除（同名卡片可能仍有实例存活）
    closeTrackedFds(formId);
  }

  private refreshAll(): void {
    formProvider.getPublishedRunningFormInfos().then((infos) => {
      infos.forEach((info) => {
        updateOneForm(this.context, info.formId, info.formName, info.dimension).catch(() => {});
      });
    }).catch(() => {});
  }
}
