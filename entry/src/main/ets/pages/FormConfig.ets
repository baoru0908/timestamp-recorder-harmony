import { common } from '@kit.AbilityKit';
import formProvider from '@ohos.app.form.formProvider';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { EventRepository } from '../data/EventRepository';
import { TimestampEvent, colorToHex, hexToColor } from '../model/TimestampEvent';
import {
  PREF_BIND_PREFIX,
  PREF_CUSTOM_TITLE,
  PREF_CUSTOM_BG,
  PREF_CUSTOM_IMG,
  PREF_CUSTOM_EVENTS,
  CUSTOM_DEFAULT_TITLE,
  CUSTOM_IMG_FILE,
  CUSTOM_IMG_MAX_SIDE,
  CUSTOM_BG_PRESETS,
  FORM_SINGLE,
  FORM_CAPSULE,
  FORM_CUSTOM
} from '../model/CardData';
import { formConfigWant } from '../entryability/FormConfigAbility';
import { syncAllForms } from '../util/FormSync';
import { getTheme, ThemeColors } from '../util/Theme';

class RowItem {
  ev: TimestampEvent;
  count: number;
  last: number;
  /** 列表副标题（按事件类型：点时刻「N 条记录」/ 时间段「N 段」） */
  countText: string;
  constructor(ev: TimestampEvent, count: number, last: number, countText: string) {
    this.ev = ev;
    this.count = count;
    this.last = last;
    this.countText = countText;
  }
}

/**
 * 服务卡片配置页（formConfigAbility 指向本页）：
 * - 单事件 / 胶囊：选择要绑定的单个事件（点行即完成）
 * - 自定义卡片：标题 + 背景色（6 预设 / 十六进制）+ 背景图（相册选图，存沙箱）+ 多选事件
 */
@Entry
@Component
struct FormConfig {
  @State rows: RowItem[] = [];
  @State formName: string = FORM_SINGLE;
  @StorageProp('isDark') isDark: boolean = false;

  // —— 自定义卡片配置态 ——
  @State customTitle: string = CUSTOM_DEFAULT_TITLE;
  @State customBg: string = CUSTOM_BG_PRESETS[0];
  @State customImg: string = '';
  @State customIds: number[] = [];
  @State showHex: boolean = false;
  @State hexInput: string = '';
  @State hexError: string = '';
  @State busy: boolean = false;

  private repo: EventRepository | null = null;

  /** 当前语义色板（ArkUI struct 内必须用普通方法，不能用 getter） */
  private theme(): ThemeColors {
    return getTheme(this.isDark);
  }

  /** 是否自定义卡片配置流程 */
  private isCustom(): boolean {
    return this.formName === FORM_CUSTOM;
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.repo = new EventRepository(ctx);
    // ⚠️ 从磁盘重读后再操作：本页会写「卡片绑定 / 自定义配置」，
    //    若沿用进程内过期缓存实例，写盘时可能把卡片进程刚写入的记录覆盖回去。
    this.repo.refresh();
    const want = formConfigWant;
    if (want !== null) {
      const params: Record<string, Object> = (want.parameters as Record<string, Object>) ?? {};
      const name = String(params['ohos.extra.param.key.form_name'] ?? '');
      if (name === FORM_SINGLE || name === FORM_CAPSULE || name === FORM_CUSTOM) {
        this.formName = name;
      } else {
        // 桌面（SCB）编辑流程只传 formId，按 formId 反查 formName
        const fid = String(params['formId'] ?? '');
        if (fid.length > 0) {
          formProvider.getPublishedRunningFormInfos().then((infos) => {
            for (let i = 0; i < infos.length; i++) {
              if (infos[i].formId === fid &&
                (infos[i].formName === FORM_SINGLE || infos[i].formName === FORM_CAPSULE ||
                  infos[i].formName === FORM_CUSTOM)) {
                this.formName = infos[i].formName;
                this.loadCustom();
                this.reload();
                return;
              }
            }
          }).catch(() => {});
        }
      }
    }
    this.loadCustom();
    this.reload();
  }

  private reload(): void {
    if (this.repo === null) {
      return;
    }
    const next: RowItem[] = [];
    this.repo.getEvents().forEach((ev: TimestampEvent) => {
      const last: number | null = this.repo!.lastRecord(ev.id);
      // 时间段统计「段数」、点时刻统计「条数」（对齐卡片与 Android 口径）
      const cnt: number = ev.isInterval() ? this.repo!.intervalCount(ev.id) : this.repo!.recordCount(ev.id);
      const label: string = ev.isInterval() ? `${cnt} 段` : `${cnt} 条记录`;
      next.push(new RowItem(ev, cnt, last === null ? -1 : last, label));
    });
    this.rows = next;
  }

  /** 读取已保存的自定义配置（用于编辑既有卡片） */
  private loadCustom(): void {
    if (this.repo === null) {
      return;
    }
    this.customTitle = this.repo.getPrefStr(PREF_CUSTOM_TITLE, CUSTOM_DEFAULT_TITLE);
    this.customBg = colorToHex(this.repo.getPrefNum(PREF_CUSTOM_BG, 0xFF1A1C1E | 0));
    this.customImg = this.repo.getPrefStr(PREF_CUSTOM_IMG, '');
    const raw: string = this.repo.getPrefStr(PREF_CUSTOM_EVENTS, '[]');
    try {
      const arr: number[] = JSON.parse(raw) as number[];
      this.customIds = Array.isArray(arr) ? arr : [];
    } catch (err) {
      this.customIds = [];
    }
  }

  // ---------- 单事件 / 胶囊：绑定 ----------

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
    this.finish();
  }

  private finish(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  // ---------- 自定义卡片：多选 / 保存 ----------

  private isChecked(id: number): boolean {
    return this.customIds.includes(id);
  }

  private toggleCheck(id: number): void {
    const next: number[] = this.customIds.slice();
    const idx: number = next.indexOf(id);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(id);
    }
    this.customIds = next;
  }

  private saveCustom(): void {
    if (this.repo === null) {
      return;
    }
    if (this.customIds.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请至少勾选一个事件' });
      return;
    }
    const title: string = this.customTitle.trim();
    this.repo.setPrefStr(PREF_CUSTOM_TITLE, title.length > 0 ? title : CUSTOM_DEFAULT_TITLE);
    this.repo.setPrefNum(PREF_CUSTOM_BG, hexToColor(this.customBg));
    this.repo.setPrefStr(PREF_CUSTOM_IMG, this.customImg);
    this.repo.setPrefStr(PREF_CUSTOM_EVENTS, JSON.stringify(this.customIds));
    try {
      const ctx0 = this.getUIContext().getHostContext() as common.Context;
      syncAllForms(ctx0);
    } catch (e) {
    }
    this.getUIContext().getPromptAction().showToast({ message: '已保存卡片设置' });
    this.finish();
  }

  // ---------- 自定义背景色 ----------

  private pickHex(): void {
    const v: string = this.hexInput.trim();
    if (v.length === 0) {
      this.hexError = '请输入色值';
      return;
    }
    // 简单校验：#/无# 3 或 6 位十六进制
    let h: string = v.startsWith('#') ? v.substring(1) : v;
    if (h.length === 3) {
      h = `${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}`;
    }
    if (h.length !== 6 || !/^[0-9A-Fa-f]{6}$/.test(h)) {
      this.hexError = '格式应为 #RRGGBB';
      return;
    }
    this.hexError = '';
    this.customBg = `#${h.toUpperCase()}`;
    this.showHex = false;
  }

  // ---------- 背景图：选图 + 压缩 + 落沙箱 ----------

  private async chooseImage(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const res = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (res.photoUris.length === 0) {
        this.busy = false;
        return;
      }
      await this.saveImageToSandbox(res.photoUris[0]);
      this.getUIContext().getPromptAction().showToast({ message: '背景图已设置' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '选图失败或已取消' });
    }
    this.busy = false;
  }

  /** 读取所选图片 → 等比缩放到 CUSTOM_IMG_MAX_SIDE 内 → JPEG(q60) → 写入 filesDir */
  private async saveImageToSandbox(uri: string): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const source = image.createImageSource(src.fd);
    const info = await source.getImageInfo();
    const ow: number = info.size.width;
    const oh: number = info.size.height;
    let tw: number = ow;
    let th: number = oh;
    const maxSide: number = CUSTOM_IMG_MAX_SIDE;
    if (ow > maxSide || oh > maxSide) {
      if (ow >= oh) {
        tw = maxSide;
        th = Math.max(1, Math.round(oh * maxSide / ow));
      } else {
        th = maxSide;
        tw = Math.max(1, Math.round(ow * maxSide / oh));
      }
    }
    const pixelMap = await source.createPixelMap({ desiredSize: { width: tw, height: th } });
    const packer = image.createImagePacker();
    const buf = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 60 });
    const dest: string = `${ctx.filesDir}/${CUSTOM_IMG_FILE}`;
    const out = fs.openSync(dest, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(out.fd, buf);
    fs.closeSync(out);
    fs.closeSync(src);
    this.customImg = CUSTOM_IMG_FILE;
  }

  private removeImage(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    const dest: string = `${ctx.filesDir}/${CUSTOM_IMG_FILE}`;
    try {
      if (fs.accessSync(dest)) {
        fs.unlinkSync(dest);
      }
    } catch (e) {
    }
    this.customImg = '';
    this.getUIContext().getPromptAction().showToast({ message: '已移除背景图' });
  }

  private previewUri(): string {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    return fileUri.getUriFromPath(`${ctx.filesDir}/${this.customImg}`);
  }

  // ---------- UI ----------

  @Builder
  Header() {
    Row() {
      Text(this.isCustom() ? '自定义卡片' : '绑定事件')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().onSurface)
        .layoutWeight(1)
      Text(this.isCustom() ? '保存' : '取消')
        .fontSize(15)
        .fontWeight(this.isCustom() ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.theme().primary)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .onClick(() => {
          if (this.isCustom()) {
            this.saveCustom();
          } else {
            this.finish();
          }
        })
    }
    .width('100%')
    .padding({ left: 20, right: 12, top: 32, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundEffect({ radius: 20, saturation: 1.15, brightness: 1.0, color: this.theme().glassToolbar })
  }

  @Builder
  SectionTitle(t: string) {
    Text(t)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.theme().onSurfaceVariant)
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 8 })
  }

  /** 背景色：6 预设 + 自定义（hex 输入）。⚠️ 用 Flex wrap：7 个色块在窄屏一行放不下会溢出 */
  @Builder
  BgColorPicker() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(CUSTOM_BG_PRESETS, (c: string) => {
          Stack() {
            if (this.customBg.toUpperCase() === c.toUpperCase()) {
              Text('✓')
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor(c)
          .border({
            width: 2,
            color: this.customBg.toUpperCase() === c.toUpperCase() ? this.theme().primary : this.theme().outline
          })
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.customBg = c;
            this.showHex = false;
          })
        }, (c: string) => c)

        // 自定义（十六进制）
        Stack() {
          Text('#')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().onSurfaceVariant)
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(this.theme().inputBg)
        .border({ width: 1, color: this.theme().outline })
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          this.hexInput = this.customBg;
          this.hexError = '';
          this.showHex = !this.showHex;
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })

      if (this.showHex) {
        Column() {
          Row() {
            TextInput({ text: this.hexInput, placeholder: '#RRGGBB' })
              .fontSize(15)
              .fontColor(this.theme().onSurface)
              .backgroundColor(this.theme().inputBg)
              .borderRadius(10)
              .height(44)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.hexInput = v;
                this.hexError = '';
              })
            // 实时预览
            Row()
              .width(44)
              .height(44)
              .borderRadius(10)
              .backgroundColor(/^#?[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$/.test(this.hexInput.trim())
                ? (this.hexInput.trim().startsWith('#') ? this.hexInput.trim() : `#${this.hexInput.trim()}`)
                : this.customBg)
              .margin({ left: 10 })
            Text('确定')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(10)
              .backgroundColor(this.theme().primary)
              .margin({ left: 10 })
              .onClick(() => this.pickHex())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.hexError.length > 0) {
            Text(this.hexError)
              .fontSize(12)
              .fontColor(this.theme().danger)
              .width('100%')
              .margin({ top: 6 })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 背景图：当前预览 + 选图 / 移除 */
  @Builder
  BgImagePicker() {
    Row() {
      if (this.customImg.length > 0) {
        Image(this.previewUri())
          .width(56)
          .height(56)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text('无图')
            .fontSize(12)
            .fontColor(this.theme().onSurfaceVariant)
        }
        .width(56)
        .height(56)
        .borderRadius(10)
        .backgroundColor(this.theme().inputBg)
        .justifyContent(FlexAlign.Center)
      }

      Text(this.customImg.length > 0 ? '更换背景图' : '选择背景图')
        .fontSize(14)
        .fontColor(this.theme().primary)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => {
          this.chooseImage();
        })

      if (this.customImg.length > 0) {
        Text('移除')
          .fontSize(14)
          .fontColor(this.theme().danger)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .onClick(() => this.removeImage())
      }

      Blank()
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  /** 事件多选列表 */
  @Builder
  EventChecks() {
    List() {
      ForEach(this.rows, (r: RowItem) => {
        ListItem() {
          Row() {
            // 自绘勾选框（⚠️ Circle 上加 border 会渲染成方框；此处用圆角方块，兼容 API 24）
            Stack() {
              if (this.isChecked(r.ev.id)) {
                Row()
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .backgroundColor(this.theme().primary)
                Text('✓')
                  .fontSize(13)
                  .fontColor('#FFFFFF')
              } else {
                Row()
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .backgroundColor('#00000000')
                  .border({ width: 1.6, color: this.theme().outline })
              }
            }
            .width(28)
            .height(28)

            Row()
              .width(12)
              .height(12)
              .borderRadius(6)
              .backgroundColor(colorToHex(r.ev.color))
              .margin({ left: 10 })

            Column() {
              Text(r.ev.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme().onSurface)
              Text(r.countText)
                .fontSize(12)
                .fontColor(this.theme().onSurfaceVariant)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 10 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(this.theme().glassCard)
          .borderRadius(16)
          .border({ width: 1, color: this.theme().glassStroke })
          .onClick(() => this.toggleCheck(r.ev.id))
        }
        .margin({ left: 16, right: 16, bottom: 10 })
      }, (r: RowItem) => `${r.ev.id}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      this.Header()

      if (this.isCustom()) {
        Scroll() {
          Column() {
            this.SectionTitle('卡片标题')
            TextInput({ text: this.customTitle, placeholder: '给卡片起个名字' })
              .fontSize(16)
              .fontColor(this.theme().onSurface)
              .backgroundColor(this.theme().inputBg)
              .borderRadius(12)
              .height(48)
              .margin({ left: 20, right: 20 })
              .onChange((v: string) => {
                this.customTitle = v;
              })

            this.SectionTitle('背景色')
            this.BgColorPicker()

            this.SectionTitle('背景图（可选，优先于背景色）')
            this.BgImagePicker()

            this.SectionTitle('显示哪些事件（可多选）')
            Column() {
              this.EventChecks()
            }
            .width('100%')
            .height(this.rows.length === 0 ? 120 : Math.min(this.rows.length, 5) * 82)

            if (this.rows.length === 0) {
              Text('还没有事件，请先在 App 里添加')
                .fontSize(13)
                .fontColor(this.theme().onSurfaceVariant)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
            }

            Blank().height(24)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      } else {
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
                  // ⚠️ 原用 Circle().fill()：fill 是 API 26 新增，平板（API 24）上不可用 → 改全版本兼容的圆角方块画法
                  Row()
                    .width(14)
                    .height(14)
                    .borderRadius(7)
                    .backgroundColor(colorToHex(r.ev.color))
                  Column() {
                    Text(r.ev.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.theme().onSurface)
                    Text(r.countText)
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
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 135,
      colors: [[this.theme().bgStart, 0.0], [this.theme().bgCenter, 0.5], [this.theme().bgEnd, 1.0]]
    })
  }
}
