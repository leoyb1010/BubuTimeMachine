import { camera, cameraPicker } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';

// MARK: - 直接录像（对照 iOS Features/Capture/VideoCaptureView.swift）
// iOS 用 UIImagePickerController(.camera, mediaTypes:["public.movie"], cameraCaptureMode:.video,
// videoMaximumDuration:60) 拉起系统相机录像，回调 onVideo(URL) / onCancel()。
// 录完回传本地临时文件 URL，由 CaptureModel 走统一视频导入管线（压缩 + 缩略图）。
// HarmonyOS 对应 @kit.CameraKit 系统相机选择器的视频模式。
// NOTE: Harmony cameraPicker 录像的最大时长由系统相机控制，无直接 60s 入参；
//       与 iOS 的 videoMaximumDuration=60 语义近似（系统录像界面有大停止按钮，适老防误触）。

export class VideoCaptureView {
  // 返回录到的视频 URI；用户取消时返回 null。
  static async captureVideo(context: common.UIAbilityContext): Promise<string | null> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        videoDuration: 60   // 限 60s（对照 iOS videoMaximumDuration = 60）
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.VIDEO],
        profile
      );
      if (result.resultCode === 0 && result.resultUri.length > 0) {
        return result.resultUri;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
