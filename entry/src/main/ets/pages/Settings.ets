import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { picker } from '@kit.CoreFileKit';
import fileIo from '@ohos.file.fs';
import util from '@ohos.util';
import formProvider from '@ohos.app.form.formProvider';
import { EventRepository, BackupData } from '../data/EventRepository';
import { syncAllForms } from '../util/FormSync';
import { TimeFormat } from '../util/TimeFormat';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 设置页（对齐 Android SettingsActivity）：
 * 排序方式（手动 / 按最近记录）+ 备份导入导出 + 教程 / 关于。
 */
@Entry
@Component
struct Settings {
  @State sortMode: string = 'manual';
  @StorageProp('isDark') isDark: boolean = false;
  /** App 回到前台时由 EntryAbility.onForeground 递增 → 触发从磁盘重载（卡片进程可能已写入） */
  @StorageProp('fgReloadTick') @Watch('onForegroundReload') fgReloadTick: number = 0;
  private repo: EventRepository | null = null;

  /** 当前语义色板（ArkUI struct 内必须用普通方法，不能用 getter） */
  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.repo = new EventRepository(ctx);
    this.repo.onChanged = () => syncAllForms(ctx);
    this.sortMode = this.repo.getSortMode();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  /**
   * 回到本页 / App 回到前台：丢弃进程内 Preferences 缓存后重读。
   * 设置页会写 sort_mode；若持有过期缓存实例，写入可能把卡片进程刚写入的数据覆盖回去，
   * 因此进入本页与回前台时都必须先刷新缓存。
   */
  private refreshRepo(): void {
    if (this.repo !== null) {
      this.repo.refresh();
      this.sortMode = this.repo.getSortMode();
    }
  }

  onPageShow(): void {
    this.refreshRepo();
  }

  onForegroundReload(): void {
    this.refreshRepo();
  }

  // ---------- 备份导出 ----------

  private exportBackup(): void {
    if (this.repo === null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context;
    const documentPicker = new picker.DocumentViewPicker(ctx);
    const now: string = TimeFormat.full(Date.now()).replace(/:/g, '-').replace(/ /g, '_');
    documentPicker.save({
      newFileNames: [`TimestampRecorder_backup_${now}.json`]
    }).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      try {
        const file = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        const json: string = this.repo !== null ? this.repo.exportJson() : '{}';
        fileIo.writeSync(file.fd, json);
        fileIo.closeSync(file);
        this.toast('备份已导出');
      } catch (e) {
        this.toast('导出失败');
      }
    }).catch(() => {});
  }

  // ---------- 备份导入 ----------

  private importBackup(): void {
    if (this.repo === null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context;
    const documentPicker = new picker.DocumentViewPicker(ctx);
    documentPicker.select({
      maxSelectNumber: 1
    }).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      try {
        // readTextSync 不支持 picker URI，改用 openSync + readSync + TextDecoder
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        fileIo.closeSync(file);
        const json: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
        const data: BackupData | null = this.repo !== null ? this.repo.parseBackup(json) : null;
        if (data === null) {
          this.toast('备份文件无效');
          return;
        }
        let total: number = 0;
        data.records.forEach((list: number[]) => {
          total += list.length;
        });
        this.getUIContext().showAlertDialog({
          title: '导入备份',
          message: `将导入 ${data.events.length} 个事件、${total} 条记录，并覆盖当前全部数据。`,
          autoCancel: true,
          alignment: DialogAlignment.Center,
          primaryButton: {
            value: '导入',
            fontColor: this.theme().primary,
            action: () => {
              this.repo?.replaceAllData(data.events, data.records);
              this.toast('备份已导入');
            }
          },
          secondaryButton: {
            value: '取消',
            fontColor: this.theme().outline,
            action: () => {}
          }
        });
      } catch (e) {
        this.toast('导入失败');
      }
    }).catch(() => {});
  }

  // ---------- 排序模式 ----------

  private selectSort(mode: string): void {
    if (this.repo === null || mode === this.sortMode) {
      return;
    }
    this.sortMode = mode;
    this.repo.setSortMode(mode);
    this.toast(mode === 'recent' ? '已切换：按最近记录排序' : '已切换：手动排序');
  }

  // ---------- 桌面卡片 ----------

  private openFormManager(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    formProvider.openFormManager({
      bundleName: 'com.timestamp.recorder',
      abilityName: 'FormAbility',
      parameters: {
        'ohos.extra.param.key.module_name': 'entry'
      }
    });
  }

  // ---------- 工具行 ----------

  @Builder
  SectionTitle(t: string) {
    Text(t)
      .fontSize(13)
      .fontColor(this.theme().onSurfaceVariant)
      .margin({ left: 20, top: 18, bottom: 8 })
      .width('100%')
  }

  @Builder
  RowAction(icon: string, title: string, sub: string, onClick: () => void) {
    Row() {
      Circle()
        .width(12)
        .height(12)
        .fill(this.theme().primary)
        .opacity(0.25)
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme().onSurface)
        Text(sub)
          .fontSize(12)
          .fontColor(this.theme().onSurfaceVariant)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      Text('›')
        .fontSize(22)
        .fontColor(this.theme().outline)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.theme().glassCard)
    .borderRadius(16)
    .border({ width: 1, color: this.theme().glassStroke })
    .margin({ left: 16, right: 16, bottom: 10 })
    .onClick(onClick)
  }

  @Builder
  SortRow(mode: string, title: string, sub: string) {
    Row() {
      // 单选框（选中 / 未选中统一为圆形）：选中 = 主色实心圆 + 白色圆心；未选中 = 灰色圆环。
      // ⚠️ 未选中态不能用 .border() —— border 是矩形边框属性，画在 Circle 上会渲染成方框。
      //    必须用 Shape 的 .stroke() / .strokeWidth() 描边才是真正的圆环。
      Stack() {
        if (mode === this.sortMode) {
          Circle()
            .width(18)
            .height(18)
            .fill(this.theme().primary)
          Circle()
            .width(8)
            .height(8)
            .fill(this.theme().white)
        } else {
          Circle()
            .width(18)
            .height(18)
            .fill('#00000000')
            .stroke(this.theme().outline)
            .strokeWidth(2)
        }
      }
      .width(18)
      .height(18)
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme().onSurface)
        Text(sub)
          .fontSize(12)
          .fontColor(this.theme().onSurfaceVariant)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.theme().glassCard)
    .borderRadius(16)
    .border({ width: 1, color: this.theme().glassStroke })
    .margin({ left: 16, right: 16, bottom: 10 })
    .onClick(() => this.selectSort(mode))
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
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
      }
      .width('100%')
      .padding({ left: 4, right: 12, top: 30, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

      Scroll() {
        Column() {
          // ---------- 排序方式 ----------
          this.SectionTitle('排序方式')
          this.SortRow('manual', '手动排序', '在主页长按拖动调整事件顺序')
          this.SortRow('recent', '按最近记录', '按最近记录时间自动排列')

          // ---------- 数据备份 ----------
          this.SectionTitle('数据备份')
          this.RowAction('', '导出备份', '导出全部事件与记录为 JSON 文件',
            () => this.exportBackup())
          this.RowAction('', '导入备份', '从备份文件恢复，将覆盖当前数据',
            () => this.importBackup())

          // ---------- 桌面卡片 ----------
          this.SectionTitle('桌面卡片')
          this.RowAction('', '管理桌面卡片', '打开卡片管理：全部事件 / 单事件 / 胶囊 / 自定义卡片',
            () => this.openFormManager())


          // ---------- 其他 ----------
          this.SectionTitle('其他')
          this.RowAction('', '使用教程', '在线图文教程（无网时显示内置简明版）',
            () => router.pushUrl({ url: 'pages/Tutorial' }))

          // ---------- 隐私（关于页已移除；《用户协议》待法务确认文本后恢复入口） ----------
          this.SectionTitle('隐私')
          this.RowAction('', '隐私政策', '数据仅存本机 · 不申请权限 · 无第三方 SDK',
            () => router.pushUrl({ url: 'pages/PrivacyDoc' }))
        }
        .width('100%')
        .padding({ top: 4, bottom: 40 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
    })
  }
}
