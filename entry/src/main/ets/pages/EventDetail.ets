import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { picker } from '@kit.CoreFileKit';
import fileIo from '@ohos.file.fs';
import pasteboard from '@ohos.pasteboard';
import { EventRepository } from '../data/EventRepository';
import { syncAllForms } from '../util/FormSync';
import { colorToHex, EVENT_COLORS, TimestampEvent } from '../model/TimestampEvent';
import { TimeFormat } from '../util/TimeFormat';
import { getTheme, ThemeColors } from '../util/Theme';

/**
 * 事件详情页（对齐 Android EventDetailActivity + activity_event_detail.xml + item_record.xml）：
 * 记录此刻（事件色 + 时钟图标）/ 撤销 / 记录列表（直角玻璃行、#序号、等宽时间、Unix、复制）/
 * 长按删单条 / 顶栏批量管理入口（多选删除）/ ⋮ 菜单（编辑、导出、清空、删除、统计、时间线）。
 */
@Entry
@Component
struct EventDetail {
  @State eventId: number = 0;
  @State ev: TimestampEvent | null = null;
  @State records: number[] = [];
  @State count: number = 0;
  @State last: number = -1;
  // 批量选择模式
  @State selectMode: boolean = false;
  @State selected: number[] = [];
  // 编辑事件弹层
  @State showEdit: boolean = false;
  @State editName: string = '';
  @State editColor: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  private repo: EventRepository | null = null;

  /** 当前语义色板（ArkUI struct 内必须用普通方法，不能用 getter） */
  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.repo = new EventRepository(ctx);
    this.repo.onChanged = () => syncAllForms(ctx);
    const params = router.getParams() as Record<string, Object>;
    this.eventId = params['eventId'] as number;
    this.reload();
  }

  private reload(): void {
    if (this.repo === null) {
      return;
    }
    this.ev = this.repo.getEvent(this.eventId);
    this.records = this.repo.getRecords(this.eventId);
    this.count = this.records.length;
    const l: number | null = this.repo.lastRecord(this.eventId);
    this.last = l === null ? -1 : l;
  }

  private recordOnce(): void {
    const m: number = this.repo?.addRecord(this.eventId) ?? 0;
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: `已记录 ${TimeFormat.hm(m)}` });
  }

  private undoLast(): void {
    const ok: boolean = this.repo?.undoLast(this.eventId) ?? false;
    if (ok) {
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已撤销上一条' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '没有可撤销的记录' });
    }
  }

  private copyRecord(m: number): void {
    const text: string = `${TimeFormat.full(m)}  (Unix 秒: ${Math.floor(m / 1000)})`;
    const pb = pasteboard.getSystemPasteboard();
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pb.setData(data);
    this.getUIContext().getPromptAction().showToast({ message: '已复制时间' });
  }

  private deleteRecordAt(pos: number): void {
    this.getUIContext().showAlertDialog({
      title: '删除记录',
      message: '确定删除这条记录吗？',
      buttons: [
        {
          value: '删除',
          fontColor: this.theme().danger,
          action: () => {
            this.repo?.deleteRecord(this.eventId, pos);
            this.reload();
            this.getUIContext().getPromptAction().showToast({ message: '已删除' });
          }
        },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  private deleteEvent(): void {
    this.getUIContext().showAlertDialog({
      title: '删除事件',
      message: `确定删除「${this.ev?.name ?? ''}」及其全部记录吗？此操作不可恢复。`,
      buttons: [
        {
          value: '删除',
          fontColor: this.theme().danger,
          action: () => {
            this.repo?.deleteEvent(this.eventId);
            router.back();
          }
        },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  private buildCsv(): string {
    const lines: string[] = ['序号,时间,Unix秒'];
    this.records.forEach((m: number, i: number) => {
      lines.push(`${i + 1},${TimeFormat.full(m)},${Math.floor(m / 1000)}`);
    });
    return lines.join('\n');
  }

  private sanitize(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_');
  }

  private exportCsv(): void {
    if (this.ev === null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context;
    const documentPicker = new picker.DocumentViewPicker(ctx);
    const fileName: string = `${this.sanitize(this.ev.name)}.csv`;
    documentPicker.save({
      newFileNames: [fileName]
    }).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      try {
        const file = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(file.fd, this.buildCsv());
        fileIo.closeSync(file);
        this.getUIContext().getPromptAction().showToast({ message: 'CSV 已导出' });
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
      }
    }).catch(() => {});
  }

  /** 清空该事件全部记录（对齐 Android 详情 ⋮「清空记录」） */
  private clearAllRecords(): void {
    this.getUIContext().showAlertDialog({
      title: '清空记录',
      message: `确定清空「${this.ev?.name ?? ''}」的全部 ${this.count} 条记录吗？此操作不可恢复。`,
      buttons: [
        {
          value: '清空',
          fontColor: this.theme().danger,
          action: () => {
            this.repo?.clearRecords(this.eventId);
            this.reload();
            this.getUIContext().getPromptAction().showToast({ message: '已清空记录' });
          }
        },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  // ---------- 批量选择（对齐 Android selectionBar） ----------

  private enterSelectMode(): void {
    if (this.records.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无记录' });
      return;
    }
    this.selected = [];
    this.selectMode = true;
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selected = [];
  }

  private isSelected(m: number): boolean {
    return this.selected.includes(m);
  }

  private toggleSelect(m: number): void {
    const next: number[] = this.selected.slice();
    const idx: number = next.indexOf(m);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(m);
    }
    this.selected = next;
  }

  private toggleSelectAll(): void {
    this.selected = this.selected.length === this.records.length ? [] : this.records.slice();
  }

  private deleteSelected(): void {
    if (this.selected.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '未选择记录' });
      return;
    }
    const n: number = this.selected.length;
    const target: number[] = this.selected.slice();
    this.getUIContext().showAlertDialog({
      title: '删除选中记录',
      message: `确定删除选中的 ${n} 条记录吗？`,
      buttons: [
        {
          value: '删除',
          fontColor: this.theme().danger,
          action: () => {
            this.repo?.deleteRecords(this.eventId, target);
            this.exitSelectMode();
            this.reload();
            this.getUIContext().getPromptAction().showToast({ message: `已删除 ${n} 条` });
          }
        },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  // ---------- 编辑事件 ----------

  private openEdit(): void {
    if (this.ev === null) {
      return;
    }
    this.editName = this.ev.name;
    this.editColor = this.ev.color;
    this.showEdit = true;
  }

  private saveEdit(): void {
    const name: string = this.editName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '名称不能为空' });
      return;
    }
    this.repo?.updateEvent(this.eventId, name, this.editColor);
    this.showEdit = false;
    this.reload();
    const ctx = this.getUIContext().getHostContext() as common.Context;
    syncAllForms(ctx);
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
  }

  private gotoStats(): void {
    router.pushUrl({ url: 'pages/Stats' });
  }

  private gotoTimeline(): void {
    // 回主页并请求打开时间线 tab（Index.onPageShow 读取后清除）
    AppStorage.setOrCreate('detailOpenTimeline', true);
    router.back();
  }

  /** 详情 ⋮ 菜单（对齐 Android 七项：编辑 / 导出 / 清空 / 删除 / 统计 / 时间线；批量为顶栏图标单独入口） */
  private showDetailMenu(): void {
    this.getUIContext().showAlertDialog({
      title: this.ev?.name ?? '操作',
      message: '选择操作',
      buttons: [
        { value: '编辑事件', fontColor: this.theme().onSurface, action: () => this.openEdit() },
        { value: '导出记录 CSV', fontColor: this.theme().primary, action: () => this.exportCsv() },
        { value: '清空记录', fontColor: this.theme().onSurface, action: () => this.clearAllRecords() },
        { value: '删除事件', fontColor: this.theme().danger, action: () => this.deleteEvent() },
        { value: '统计', fontColor: this.theme().onSurface, action: () => this.gotoStats() },
        { value: '时间线', fontColor: this.theme().onSurface, action: () => this.gotoTimeline() },
        { value: '取消', fontColor: this.theme().onSurfaceVariant, action: () => {} }
      ]
    });
  }

  /** 时钟图标（对齐 Android ic_clock，白色描边 + 两指针） */
  @Builder
  ClockIcon() {
    Stack() {
      Circle()
        .width(20)
        .height(20)
        .fill('#00000000')
        .stroke('#FFFFFF')
        .strokeWidth(1.8)
      Rect() // 指向 12
        .width(1.8)
        .height(7)
        .fill('#FFFFFF')
        .borderRadius(1)
        .offset({ y: -3.2 })
      Rect() // 指向 3
        .width(7)
        .height(1.8)
        .fill('#FFFFFF')
        .borderRadius(1)
        .offset({ x: 3.2 })
    }
    .width(22)
    .height(22)
  }

  /** 批量管理入口图标（对齐 Android ic_check_box：方框 + 对勾） */
  @Builder
  BatchEntryIcon() {
    Stack() {
      Rect()
        .width(20)
        .height(20)
        .radius(4)
        .fill('#00000000')
        .stroke(this.theme().onSurfaceVariant)
        .strokeWidth(1.8)
      Text('✓')
        .fontSize(14)
        .fontColor(this.theme().onSurfaceVariant)
    }
    .width(44)
    .height(44)
    .onClick(() => this.enterSelectMode())
  }

  /** 行内勾选框（批量模式） */
  @Builder
  RowCheckBox(m: number) {
    Stack() {
      if (this.isSelected(m)) {
        Rect().width(20).height(20).radius(4).fill(this.theme().primary)
        Text('✓').fontSize(14).fontColor('#FFFFFF')
      } else {
        Rect()
          .width(20)
          .height(20)
          .radius(4)
          .fill('#00000000')
          .stroke(this.theme().outline)
          .strokeWidth(1.6)
      }
    }
    .width(28)
    .height(28)
  }

  /** 底部批量操作栏（对齐 Android selectionBar） */
  @Builder
  SelectionBar() {
    Row() {
      Text(this.selected.length === this.records.length && this.records.length > 0 ? '取消全选' : '全选')
        .fontSize(14)
        .fontColor(this.theme().primary)
        .padding({ left: 8, right: 8, top: 10, bottom: 10 })
        .onClick(() => this.toggleSelectAll())
      Text(`已选 ${this.selected.length} 条`)
        .fontSize(14)
        .fontColor(this.theme().onSurface)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(`删除 ${this.selected.length}`)
        .fontSize(14)
        .fontColor(this.theme().danger)
        .padding({ left: 8, right: 4, top: 10, bottom: 10 })
        .onClick(() => this.deleteSelected())
      Text('取消')
        .fontSize(14)
        .fontColor(this.theme().onSurfaceVariant)
        .padding({ left: 8, right: 12, top: 10, bottom: 10 })
        .onClick(() => this.exitSelectMode())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 18 })
    .backgroundColor(this.theme().glassToolbar)
    .border({ width: { top: 1 }, color: this.theme().divider })
  }

  /** 编辑事件弹层（改名 + 选色，对齐 Android showEditDialog） */
  @Builder
  EditSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme().mask)
        .onClick(() => {
          this.showEdit = false;
        })
      // 面板
      Column() {
        Text('编辑事件')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().onSurface)
          .width('100%')
          .margin({ bottom: 14 })

        TextInput({ text: this.editName, placeholder: '事件名称' })
          .fontSize(16)
          .fontColor(this.theme().onSurface)
          .backgroundColor(this.theme().inputBg)
          .borderRadius(12)
          .height(48)
          .margin({ bottom: 16 })
          .onChange((v: string) => {
            this.editName = v;
          })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(EVENT_COLORS, (c: number) => {
            Stack() {
              if (this.editColor === c) {
                Text('✓').fontSize(14).fontColor('#FFFFFF')
              }
            }
            .width(40)
            .height(40)
            .margin(6)
            .borderRadius(20)
            .backgroundColor(colorToHex(c))
            .border({ width: this.editColor === c ? 2 : 0, color: this.theme().onSurface })
            .onClick(() => {
              this.editColor = c;
            })
          }, (c: number) => `${c}`)
        }
        .width('100%')
        .margin({ bottom: 18 })

        Row() {
          Text('取消')
            .fontSize(16)
            .fontColor(this.theme().onSurfaceVariant)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .height(46)
            .borderRadius(23)
            .backgroundColor(this.theme().cancelBtn)
            .onClick(() => {
              this.showEdit = false;
            })
          Text('保存')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .height(46)
            .borderRadius(23)
            .backgroundColor(this.theme().primary)
            .margin({ left: 12 })
            .onClick(() => this.saveEdit())
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .padding({ bottom: 30 })
      .backgroundColor(this.theme().glassMenu)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // ---------- 顶栏（玻璃）：返回 + 纯文本标题（Android 无色点）+ 批量入口 + ⋮ ----------
        Row() {
          Text('←')
            .fontSize(26)
            .fontColor(this.theme().onSurface)
            .padding({ left: 16, right: 8, top: 6, bottom: 6 })
            .onClick(() => router.back())

          Text(this.ev?.name ?? '')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().onSurface)
            .layoutWeight(1)
            .margin({ left: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 批量管理入口（对齐 Android toolbar 上常驻的 ic_check_box）
          if (!this.selectMode) {
            this.BatchEntryIcon()
          }
          // ⋮ 更多
          Text('⋮')
            .fontSize(24)
            .fontColor(this.theme().onSurfaceVariant)
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick(() => this.showDetailMenu())
        }
        .width('100%')
        .padding({ left: 4, right: 12, top: 30, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })

        // ---------- 大记录按钮（对齐 Android btnRecord：64dp / 圆角32 / 19sp bold / 时钟图标在文字前） ----------
        Button() {
          Row() {
            this.ClockIcon()
            Text('记录此刻')
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .margin({ left: 10 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(64)
        .fontColor('#FFFFFF')
        .backgroundColor(this.ev !== null ? colorToHex(this.ev.color) : this.theme().primary)
        .borderRadius(32)
        .margin({ left: 20, right: 20, top: 12, bottom: 4 })
        .onClick(() => this.recordOnce())

        // ---------- 统计（居中） ----------
        Text(this.count === 0 ? '暂无记录' : `共 ${this.count} 条 · 最近 ${TimeFormat.relative(this.last)}`)
          .fontSize(13)
          .fontColor(this.theme().onSurfaceVariant)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })

        // ---------- 撤销（居中文字按钮，对齐 Android btnUndo；批量模式下隐藏） ----------
        if (!this.selectMode) {
          Text('撤销上一条')
            .fontSize(14)
            .fontColor(this.theme().primary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(8)
            .onClick(() => this.undoLast())
        }

        // ---------- 记录列表（对齐 Android item_record：直角玻璃行、无描边） ----------
        if (this.records.length === 0) {
          Column() {
            Text('还没有记录')
              .fontSize(16)
              .fontColor(this.theme().onSurfaceVariant)
            Text('点上方「记录此刻」记一条吧')
              .fontSize(13)
              .fontColor(this.theme().onSurfaceVariant)
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 6 }) {
            ForEach(this.records, (m: number, i: number) => {
              ListItem() {
                Row() {
                  // 批量模式勾选框
                  if (this.selectMode) {
                    this.RowCheckBox(m)
                  }
                  // #序号（品牌色 bold）
                  Text(`#${i + 1}`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme().primary)
                    .constraintSize({ minWidth: 34 })

                  Column() {
                    Text(TimeFormat.full(m))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.theme().onSurface)
                      .fontFamily('monospace')
                    Text(`Unix 秒：${Math.floor(m / 1000)}`)
                      .fontSize(12)
                      .fontColor(this.theme().onSurfaceVariant)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  if (!this.selectMode) {
                    Text('复制')
                      .fontSize(14)
                      .fontColor(this.theme().primary)
                      .padding({ left: 12, right: 4, top: 8, bottom: 8 })
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 10, top: 12, bottom: 12 })
                .backgroundColor(this.theme().glassCard)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  if (this.selectMode) {
                    this.toggleSelect(m);
                  } else {
                    this.copyRecord(m);
                  }
                })
                .gesture(
                  LongPressGesture()
                    .onAction(() => {
                      if (!this.selectMode) {
                        this.deleteRecordAt(i);
                      }
                    })
                )
              }
            }, (m: number) => `${m}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20, right: 20, top: 8, bottom: this.selectMode ? 96 : 24 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 135,
        colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
      })

      // 批量操作底栏
      if (this.selectMode) {
        this.SelectionBar()
      }
      // 编辑事件弹层
      if (this.showEdit) {
        this.EditSheet()
      }
    }
    .width('100%')
    .height('100%')
  }
}
