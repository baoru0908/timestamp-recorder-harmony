import { common } from '@kit.AbilityKit';
import formProvider from '@ohos.app.form.formProvider';
import { EventRepository } from '../data/EventRepository';
import { TimestampEvent, colorToHex } from '../model/TimestampEvent';
import { PREF_BIND_PREFIX, FORM_SINGLE, FORM_CAPSULE } from '../model/CardData';
import { formConfigWant } from '../entryability/FormConfigAbility';
import { syncAllForms } from '../util/FormSync';
import { getTheme, ThemeColors } from '../util/Theme';

class RowItem {
  ev: TimestampEvent;
  count: number;
  last: number;
  constructor(ev: TimestampEvent, count: number, last: number) {
    this.ev = ev;
    this.count = count;
    this.last = last;
  }
}

/** 服务卡片绑定配置页：选择要绑定到卡片的事件（单事件 / 胶囊共用） */
@Entry
@Component
struct FormConfig {
  @State rows: RowItem[] = [];
  @State formName: string = FORM_SINGLE;
  @StorageProp('isDark') isDark: boolean = false;
  private repo: EventRepository | null = null;

  /** 当前语义色板（ArkUI struct 内必须用普通方法，不能用 getter） */
  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.repo = new EventRepository(ctx);
    const want = formConfigWant;
    if (want !== null) {
      const params: Record<string, Object> = (want.parameters as Record<string, Object>) ?? {};
      const name = String(params['ohos.extra.param.key.form_name'] ?? '');
      if (name === FORM_SINGLE || name === FORM_CAPSULE) {
        this.formName = name;
      } else {
        // 桌面（SCB）编辑流程只传 formId，按 formId 反查 formName
        const fid = String(params['formId'] ?? '');
        if (fid.length > 0) {
          formProvider.getPublishedRunningFormInfos().then((infos) => {
            for (let i = 0; i < infos.length; i++) {
              if (infos[i].formId === fid &&
                (infos[i].formName === FORM_SINGLE || infos[i].formName === FORM_CAPSULE)) {
                this.formName = infos[i].formName;
                this.reload();
                return;
              }
            }
          }).catch(() => {});
        }
      }
    }
    this.reload();
  }

  private reload(): void {
    if (this.repo === null) {
      return;
    }
    const next: RowItem[] = [];
    this.repo.getEvents().forEach((ev: TimestampEvent) => {
      const last: number | null = this.repo!.lastRecord(ev.id);
      next.push(new RowItem(ev, this.repo!.recordCount(ev.id), last === null ? -1 : last));
    });
    this.rows = next;
  }

  private bindEvent(id: number): void {
    if (this.repo === null) {
      return;
    }
    this.repo.setPrefNum(`${PREF_BIND_PREFIX}${this.formName}`, id);
    // 回刷所有已添加卡片（绑定即刻反映到桌面）
    try {
      const ctx0 = this.getUIContext().getHostContext() as common.Context;
      syncAllForms(ctx0);
    } catch (e) {
    }
    this.getUIContext().getPromptAction().showToast({ message: `已绑定：${this.formName}` });
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  private cancel(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('绑定事件')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
          .layoutWeight(1)
        Text('取消')
          .fontSize(15)
          .fontColor(this.theme().primary)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => this.cancel())
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 32, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

      Text('选择该小组件要绑定的目标事件：桌面将显示事件色大按钮，点击即记录该事件。')
        .fontSize(13)
        .fontColor(this.theme().onSurfaceVariant)
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      if (this.rows.length === 0) {
        Column() {
          Text('还没有事件')
            .fontSize(15)
            .fontColor(this.theme().onSurface)
          Text('请先在 App 里添加事件')
            .fontSize(12)
            .fontColor(this.theme().onSurfaceVariant)
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rows, (r: RowItem) => {
            ListItem() {
              Row() {
                Circle()
                  .width(14)
                  .height(14)
                  .fill(colorToHex(r.ev.color))
                Column() {
                  Text(r.ev.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme().onSurface)
                  Text(`${r.count} 条记录`)
                    .fontSize(12)
                    .fontColor(this.theme().onSurfaceVariant)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 12 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(this.theme().glassCard)
              .borderRadius(16)
              .border({ width: 1, color: this.theme().glassStroke })
              .onClick(() => this.bindEvent(r.ev.id))
            }
            .margin({ left: 16, right: 16, bottom: 10 })
          }, (r: RowItem) => `${r.ev.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
    })
  }
}
