import formBindingData from '@ohos.app.form.formBindingData';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BuildProfile from 'BuildProfile';
import { EventRepository } from '../data/EventRepository';
import { TimestampEvent } from '../model/TimestampEvent';
import { PREF_FORM_META, PREF_FORM_SIZE } from '../model/CardData';
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

  /** 补刷一轮正在进行中（配合 {@link refreshRest} 做连点合并） */
  private restRunning: boolean = false;
  /** 补刷飞行期间又来了新请求：记下它的 skipFormId，本轮结束后再补一次 */
  private restPendingSkip: string = '';

  onAddForm(want: Want): formBindingData.FormBindingData {
    const name: string = String(want.parameters?.[formInfo.FormParam.NAME_KEY] ?? 'all_events');
    const dim: number = (want.parameters?.[formInfo.FormParam.DIMENSION_KEY] as number) ?? 2;
    // ⚠️ 持久化 formId → 「formName|dimension」映射：
    //    onFormEvent 只拿到 formId，若每次都靠 getPublishedRunningFormInfos() 异步反查，
    //    刷新链路过长，FormExtensionAbility 进程被回收时会**刷新失败**（卡片停留在旧数据，
    //    表现为"点了没反应/内容回退"）。落盘映射后可以一步直接 updateForm。
    const formId: string = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    // 宿主下发的真实卡片高度（vp）。卡片页内无法测量自身尺寸（onAreaChange 在 form 中不支持），
    // 落盘后由 buildFormData 按真实高度截断行数，避免固定行数在不同设备 / 字体大小的卡片上溢出。
    const cardH: number = Number(want.parameters?.[formInfo.FormParam.HEIGHT_KEY] ?? 0);
    if (BuildProfile.DEBUG) {
      hilog.info(DOMAIN, 'FormAbility',
        'onAddForm name=%{public}s dim=%{public}d formId=%{public}s cardH=%{public}d', name, dim, formId, cardH);
    }
    if (formId.length > 0) {
      const repo = new EventRepository(this.context);
      repo.setPrefStr(`${PREF_FORM_META}${formId}`, `${name}|${dim}`);
      if (!Number.isNaN(cardH) && cardH > 0) {
        repo.setPrefNum(`${PREF_FORM_SIZE}${formId}`, cardH);
      }
    }
    const data: Record<string, Object> = buildFormData(this.context, name, dim, formId);
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
        // ⚠️ 先从磁盘重读：本卡片进程与 App（UIAbility）进程各自缓存 preferences，互不可见。
        //    App 内刚记录过（如「开始计时」）时，若沿用本进程旧缓存会导致点击判定错误。
        repo.refresh();
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
    // 刷新卡片（两目标同时满足）：
    // 1) 被点击的卡走**最短链**先刷 —— 保持 v1.4.2 修复效果（点击响应不丢）；
    // 2) 再**补刷其余已添加卡片** —— 恢复跨卡一致（v1.4.2 缩短链路时丢失：
    //    一张卡记录后其他卡不更新）。
    // ⚠️ 仅当 refreshOne 确实走了最短链时才补刷：若它已回退到 refreshAll，
    //    全量刷新本身就覆盖了所有卡片，再补刷会让同一批卡被刷 2~3 遍。
    const usedFastPath: boolean = this.refreshOne(formId);
    if (usedFastPath) {
      this.refreshRest(formId);
    }
  }

  onRemoveForm(formId: string): void {
    // 回收该卡片占用的图片 fd；图片文件按 formName 共用，不在此删除（同名卡片可能仍有实例存活）
    closeTrackedFds(formId);
    // 清理实例元信息，避免 preferences 残留
    try {
      const repo = new EventRepository(this.context);
      repo.setPrefStr(`${PREF_FORM_META}${formId}`, '');
      repo.setPrefNum(`${PREF_FORM_SIZE}${formId}`, 0);
    } catch (err) {
    }
  }

  /**
   * 刷新单张卡片（**最短异步链**）：
   * 用 onAddForm 落盘的 `form_meta_<formId>` 直接定位卡片类型，一步 updateForm。
   * 映射缺失（本次版本之前添加的卡片）时回退到全量刷新。
   *
   * @returns true = 走了最短链（调用方需自行补刷其余卡）；false = 已回退全量刷新（无需再补刷）
   */
  private refreshOne(formId: string): boolean {
    const meta: string = new EventRepository(this.context).getPrefStr(`${PREF_FORM_META}${formId}`, '');
    if (meta.length === 0) {
      this.refreshAll();
      return false;
    }
    const sep: number = meta.indexOf('|');
    const name: string = sep > 0 ? meta.substring(0, sep) : meta;
    const dim: number = sep > 0 ? Number(meta.substring(sep + 1)) : 2;
    updateOneForm(this.context, formId, name, dim).catch(() => {});
    return true;
  }

  /**
   * 补刷「其余」已添加卡片（**跨卡一致性**）。
   *
   * 背景：v1.4.2 为修「点击后刷新丢失」把刷新链路缩短为只刷被点击的卡，
   * 副作用是**一张卡记录后其他卡不更新**。此方法枚举已发布运行中的卡片，
   * 跳过被点击的 `skipFormId`（它已由 {@link refreshOne} 以最短链刷过），对余下卡片补刷。
   *
   * 说明：枚举依赖 `getPublishedRunningFormInfos`（异步），但**只影响"其余卡"的刷新时机**，
   * 不影响被点卡的响应链路（那条仍是一步 `updateForm`），故不会退回 v1.4.2 之前的刷新丢失问题。
   */
  private refreshRest(skipFormId: string): void {
    // ⚠️ 防连刷：用户连续点击 / 多条消息同时到达时，枚举+批量 updateForm 会被重复触发，
    //    同一批卡片被刷 2~3 遍（每遍都要重读 preferences + 重建绑定数据）。
    //    做法：飞行中不再新起一轮，只记 pending，本轮结束后用**最后一次**的 skipFormId 补刷一次。
    if (this.restRunning) {
      this.restPendingSkip = skipFormId;
      return;
    }
    this.restRunning = true;
    formProvider.getPublishedRunningFormInfos().then((infos) => {
      let refreshed: number = 0;
      infos.forEach((info) => {
        if (info.formId === skipFormId) {
          return;
        }
        updateOneForm(this.context, info.formId, info.formName, info.dimension).catch(() => {});
        refreshed++;
      });
      if (BuildProfile.DEBUG) {
        hilog.info(DOMAIN, 'FormAbility', 'refreshRest skip=%{public}s refreshed=%{public}d',
          skipFormId, refreshed);
      }
    }).catch(() => {}).then(() => {
      this.restRunning = false;
      if (this.restPendingSkip.length > 0) {
        const pending: string = this.restPendingSkip;
        this.restPendingSkip = '';
        this.refreshRest(pending);
      }
    });
  }

  private refreshAll(): void {
    formProvider.getPublishedRunningFormInfos().then((infos) => {
      infos.forEach((info) => {
        updateOneForm(this.context, info.formId, info.formName, info.dimension).catch(() => {});
      });
    }).catch(() => {});
  }
}
