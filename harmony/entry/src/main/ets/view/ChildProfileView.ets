import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { ChildProfile } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { MediaStore } from '../services/MediaStore';

// 共用字段行样式（@Extend 复用，ArkUI 正规做法，替代闭包传 UI）
@Extend(Row)
function fieldRow() {
  .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)
}

// MARK: - 布布档案编辑（对照 iOS ChildProfileView）
// 名字 / 生日 / 出生地 / 性别(Picker) / 血型(Picker)。无档案时可新建。
@Component
export struct ChildProfileView {
  @State profile: ChildProfile | null = null;
  @State name: string = '布布';
  @State birthdayMs: number = Date.now();
  @State birthPlace: string = '';
  @State genderIndex: number = 0;   // 0 未填写 / 1 男 / 2 女 / 3 其他
  @State bloodIndex: number = 0;    // 0 未填写 / A / B / O / AB
  @State avatarFileName: string | undefined = undefined;
  @State heroFileName: string | undefined = undefined;

  private genderOptions: string[] = ['未填写', '男', '女', '其他'];
  private bloodOptions: string[] = ['未填写', 'A', 'B', 'O', 'AB'];

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const p = await AppDatabase.shared.fetchChildProfile();
    this.profile = p;
    if (p) {
      this.name = p.name;
      this.birthdayMs = p.birthday;
      this.birthPlace = p.birthPlace ?? '';
      this.genderIndex = Math.max(0, this.genderOptions.indexOf(p.gender ?? '未填写'));
      this.bloodIndex = Math.max(0, this.bloodOptions.indexOf(p.bloodType ?? '未填写'));
      this.avatarFileName = p.avatarMediaFileName;
      this.heroFileName = p.heroBackgroundFileName;
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('布布的档案')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          .width('100%')

        Row({ space: 12 }) {
          if (this.avatarFileName && MediaStore.shared.exists(this.avatarFileName)) {
            Image(`file://${MediaStore.shared.fullPath(this.avatarFileName)}`)
              .width(68).height(68).objectFit(ImageFit.Cover).borderRadius(18)
          } else {
            Text('👧').fontSize(36).width(68).height(68).textAlign(TextAlign.Center)
              .backgroundColor(BubuColor.softFill).borderRadius(18)
          }
          Column({ space: 6 }) {
            Button('选择布布头像').onClick(() => { this.pickImage('avatar'); })
            Text('头像只在本机做人脸基准，并随家庭档案同步').fontSize(11).fontColor(BubuColor.secondaryText)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.fieldRow()

        Column({ space: 8 }) {
          if (this.heroFileName && MediaStore.shared.exists(this.heroFileName)) {
            Image(`file://${MediaStore.shared.fullPath(this.heroFileName)}`)
              .width('100%').height(120).objectFit(ImageFit.Cover).borderRadius(14)
          }
          Row() {
            Button('选择首页照片背景').onClick(() => { this.pickImage('hero'); })
            Blank()
            if (this.heroFileName) {
              Button('恢复主题背景').fontColor(BubuColor.danger).onClick(() => { this.heroFileName = undefined; })
            }
          }.width('100%')
        }.fieldRow()

        // 名字
        Row() {
          Text('名字').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          TextInput({ text: $$this.name }).layoutWeight(1).textAlign(TextAlign.End)
        }.fieldRow()

        // 生日
        Row() {
          Text('生日').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          Button(this.dateText(this.birthdayMs))
            .backgroundColor(Color.Transparent).fontColor(BubuColor.primary)
            .onClick(() => {
              this.getUIContext().showDatePickerDialog({
                selected: new Date(this.birthdayMs),
                onDateAccept: (d: Date) => { this.birthdayMs = d.getTime(); }
              });
            })
        }.fieldRow()

        // 出生地
        Row() {
          Text('出生地').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          TextInput({ text: $$this.birthPlace, placeholder: '选填' }).layoutWeight(1).textAlign(TextAlign.End)
        }.fieldRow()

        // 性别（Picker：未填写/男/女/其他，对齐 iOS）
        Row() {
          Text('性别').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          Select(this.genderOptions.map((o): SelectOption => ({ value: o })))
            .selected(this.genderIndex)
            .value(this.genderOptions[this.genderIndex])
            .onSelect((i: number) => { this.genderIndex = i; })
        }.fieldRow()

        // 血型（Picker：未填写/A/B/O/AB）
        Row() {
          Text('血型').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          Select(this.bloodOptions.map((o): SelectOption => ({ value: o })))
            .selected(this.bloodIndex)
            .value(this.bloodOptions[this.bloodIndex])
            .onSelect((i: number) => { this.bloodIndex = i; })
        }.fieldRow()

        Button('保存档案')
          .width('100%').backgroundColor(BubuColor.primary)
          .margin({ top: 12 })
          .onClick(() => { this.save(); })
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  private async save(): Promise<void> {
    const gender = this.genderIndex === 0 ? undefined : this.genderOptions[this.genderIndex];
    const blood = this.bloodIndex === 0 ? undefined : this.bloodOptions[this.bloodIndex];
    const place = this.birthPlace.trim().length === 0 ? undefined : this.birthPlace.trim();
    const now = Date.now();
    const p: ChildProfile = {
      id: this.profile?.id ?? util.generateRandomUUID(true),
      remoteId: this.profile?.remoteId,
      name: this.name.trim().length === 0 ? '布布' : this.name.trim(),
      birthday: this.birthdayMs,
      gender: gender,
      bloodType: blood,
      birthPlace: place,
      avatarMediaFileName: this.avatarFileName,
      avatarRemoteURL: this.avatarFileName === this.profile?.avatarMediaFileName ? this.profile?.avatarRemoteURL : undefined,
      heroBackgroundFileName: this.heroFileName,
      syncState: SyncState.local,
      createdAt: this.profile?.createdAt ?? now
    };
    await AppDatabase.shared.upsertChildProfile(p);
    if (this.profile?.avatarMediaFileName && this.profile.avatarMediaFileName !== p.avatarMediaFileName) {
      MediaStore.shared.deleteMedia(this.profile.avatarMediaFileName);
    }
    if (this.profile?.heroBackgroundFileName && this.profile.heroBackgroundFileName !== p.heroBackgroundFileName) {
      MediaStore.shared.deleteMedia(this.profile.heroBackgroundFileName);
    }
    this.profile = p;
    // 镜像给服务卡片：写生日/名字到 Preferences，卡片据此显示年龄。
    try {
      const opt: preferences.Options = { name: 'bubu_widget' };
      const store = preferences.getPreferencesSync(this.getUIContext().getHostContext(), opt);
      store.putSync('birthday', p.birthday);
      store.putSync('childName', p.name);
      store.flush();
    } catch (e) {}
    this.getUIContext().getPromptAction().showToast({ message: '已保存档案 💛' });
  }

  private async pickImage(purpose: 'avatar' | 'hero'): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      const uri = result.photoUris?.[0];
      if (!uri) return;
      const name = MediaStore.shared.copyIntoStore(uri, 'jpg');
      if (!name) throw new Error('照片读取失败');
      const previous = purpose === 'avatar' ? this.avatarFileName : this.heroFileName;
      if (previous && previous !== this.profile?.avatarMediaFileName
        && previous !== this.profile?.heroBackgroundFileName) MediaStore.shared.deleteMedia(previous);
      if (purpose === 'avatar') this.avatarFileName = name; else this.heroFileName = name;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '已取消或照片暂时无法读取' });
    }
  }

  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }
}
