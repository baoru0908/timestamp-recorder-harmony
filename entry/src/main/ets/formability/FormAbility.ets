import formBindingData from '@ohos.app.form.formBindingData';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BuildProfile from 'BuildProfile';
import { EventRepository } from '../data/EventRepository';
import { TimestampEvent } from '../model/TimestampEvent';
import { PREF_FORM_META } from '../model/CardData';
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
    // ⚠️ 持久化 formId → 「formName|dimension」映射：
    //    onFormEvent 只拿到 formId，若每次都靠 getPublishedRunningFormInfos() 异步反查，
    //    刷新链路过长，FormExtensionAbility 进程被回收时会**刷新失败**（卡片停留在旧数据，
    //    表现为"点了没反应/内容回退"）。落盘映射后可以一步直接 updateForm。
    const formId: string = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    if (formId.length > 0) {
      new EventRepository(this.context).setPrefStr(`${PREF_FORM_META}${formId}`, `${name}|${dim}`);
    }
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
        // ⚠️ 必按事件类型分派（对齐 Android `TimestampWidgetProvider.onReceive`）：
        //    点时刻 → 记一条；时间段 → **开始 / 结束切换**。
        //    旧实现一律 addRecord，会让时间段卡片点一次就多一条错误的「点时刻」记录。
        const repo = new EventRepository(this.context);
        const ev: TimestampEvent | null = repo.getEvent(eventId);
        if (BuildProfile.DEBUG) {
          hilog.info(DOMAIN, 'FormAbility', 'tap eventId=%{public}d found=%{public}s type=%{public}d',
            eventId, ev !== null ? 'yes' : 'no', ev !== null ? ev.type : -1);
        }
        if (ev !== null) {
          if (ev.isInterval()) {
            const wasOngoing: boolean = repo.getOngoingInterval(ev.id) !== null;
            if (wasOngoing) {
              repo.stopInterval(ev.id);
            } else {
              repo.startInterval(ev.id);
            }
            if (BuildProfile.DEBUG) {
              hilog.info(DOMAIN, 'FormAbility', 'interval %{public}s', wasOngoing ? 'stopped' : 'started');
            }
          } else {
            repo.addRecord(ev.id);
          }
        }
      } else if (action === 'record' && BuildProfile.DEBUG) {
        // 取证：卡片上报的 eventId 无效（未绑定 / 事件已删除 / 参数丢失）
        hilog.info(DOMAIN, 'FormAbility', 'tap with invalid eventId=%{public}d, ignored', eventId);
      }
    } catch (err) {
      // 非 JSON 消息忽略
    }
    // 刷新本次交互的卡片（最短链路，避免进程回收导致刷新丢失）
    this.refreshOne(formId);
  }

  onRemoveForm(formId: string): void {
    // 回收该卡片占用的图片 fd；图片文件按 formName 共用，不在此删除（同名卡片可能仍有实例存活）
    closeTrackedFds(formId);
    // 清理实例元信息，避免 preferences 残留
    try {
      new EventRepository(this.context).setPrefStr(`${PREF_FORM_META}${formId}`, '');
    } catch (err) {
    }
  }

  /**
   * 刷新单张卡片（**最短异步链**）：
   * 用 onAddForm 落盘的 `form_meta_<formId>` 直接定位卡片类型，一步 updateForm。
   * 映射缺失（本次版本之前添加的卡片）时回退到全量刷新。
   */
  private refreshOne(formId: string): void {
    const meta: string = new EventRepository(this.context).getPrefStr(`${PREF_FORM_META}${formId}`, '');
    if (meta.length === 0) {
      this.refreshAll();
      return;
    }
    const sep: number = meta.indexOf('|');
    const name: string = sep > 0 ? meta.substring(0, sep) : meta;
    const dim: number = sep > 0 ? Number(meta.substring(sep + 1)) : 2;
    updateOneForm(this.context, formId, name, dim).catch(() => {});
  }

  private refreshAll(): void {
    formProvider.getPublishedRunningFormInfos().then((infos) => {
      infos.forEach((info) => {
        updateOneForm(this.context, info.formId, info.formName, info.dimension).catch(() => {});
      });
    }).catch(() => {});
  }
}
