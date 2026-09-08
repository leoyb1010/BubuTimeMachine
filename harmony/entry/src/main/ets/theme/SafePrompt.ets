import { UIContext, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 页面已销毁、窗口尚未就绪时，系统提示本身也可能失败，不能掩盖保存结果。
export class SafePrompt {
  static toast(context: UIContext, options: promptAction.ShowToastOptions): void {
    try {
      context.getPromptAction().showToast(options);
    } catch (error) {
      hilog.warn(0x0000, 'Bubu', '窗口暂不可显示提示，操作结果保持不变');
    }
  }

  static async dialog(context: UIContext, options: promptAction.ShowDialogOptions): Promise<promptAction.ShowDialogSuccessResponse> {
    try {
      return await context.getPromptAction().showDialog(options);
    } catch (error) {
      hilog.warn(0x0000, 'Bubu', '确认框未能显示，按取消处理');
      return { index: -1 };
    }
  }
}
