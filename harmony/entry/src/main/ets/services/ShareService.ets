import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';

export class ShareService {
  static async shareFile(context: common.UIAbilityContext, path: string, title: string): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd: 'general.zip-archive',
      uri: fileUri.getUriFromPath(path),
      title,
      label: 'FILE',
      description: '布布时光机永久离线档案'
    };
    const controller = new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }
}
