import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';

export class ShareService {
  static async shareFile(context: common.UIAbilityContext, path: string, title: string): Promise<void> {
    await ShareService.share(context, path, title, 'general.zip-archive', '布布时光机永久离线档案');
  }

  static async sharePDF(context: common.UIAbilityContext, path: string, title: string): Promise<void> {
    await ShareService.share(context, path, title, 'com.adobe.pdf', '布布时光机可打印年册');
  }

  static async shareImage(context: common.UIAbilityContext, path: string, title: string): Promise<void> {
    await ShareService.share(context, path, title, 'general.image', '布布时光机成长分享卡');
  }

  static async shareMedia(context: common.UIAbilityContext, path: string, title: string,
                          isVideo: boolean): Promise<void> {
    await ShareService.share(context, path, title, isVideo ? 'general.video' : 'general.image',
      isVideo ? '布布时光机视频' : '布布时光机照片');
  }

  static async shareText(context: common.UIAbilityContext, title: string, text: string): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd: 'general.plain-text', content: text, title: title, label: 'TEXT', description: '布布时光机文字'
    };
    await ShareService.show(context, new systemShare.SharedData(record));
  }

  static async shareEntryLink(context: common.UIAbilityContext, entryId: string,
                              title: string, text: string): Promise<void> {
    const plain: systemShare.SharedRecord = {
      utd: 'general.plain-text', content: text, title: title, label: 'TEXT', description: '布布时光'
    };
    const data = new systemShare.SharedData(plain);
    data.addRecord({
      utd: 'general.hyperlink', content: `bubutime://entry/${encodeURIComponent(entryId)}`,
      title: '在布布时光机中打开', label: 'HYPERLINK', description: '直达这条时光'
    });
    await ShareService.show(context, data);
  }

  private static async share(context: common.UIAbilityContext, path: string, title: string,
                             utd: string, description: string): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd,
      uri: fileUri.getUriFromPath(path),
      title,
      label: 'FILE',
      description
    };
    await ShareService.show(context, new systemShare.SharedData(record));
  }

  private static async show(context: common.UIAbilityContext, data: systemShare.SharedData): Promise<void> {
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }
}
