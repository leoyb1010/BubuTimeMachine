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

  private static async share(context: common.UIAbilityContext, path: string, title: string,
                             utd: string, description: string): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd,
      uri: fileUri.getUriFromPath(path),
      title,
      label: 'FILE',
      description
    };
    const controller = new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }
}
