import { camera, cameraPicker } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';

// MARK: - 拍照（对照 iOS Features/Capture/CameraCaptureView.swift）
// iOS 用 UIImagePickerController(.camera, mediaTypes:["public.image"]) 拉起系统相机拍照，
// 回调 onImage(UIImage) / onCancel()。
// HarmonyOS 对应 @kit.CameraKit 的系统相机选择器 cameraPicker.pick(...)，
// 拍照模式返回结果 resultUri（沙盒内临时文件）。
// NOTE: iOS 直接回传 UIImage（内存图）；Harmony 回传文件 URI，调用方据此落盘/读取。
//       这里以「拍照 → 返回照片 URI」的语义对齐，回调签名改为 (uri: string)。

export class CameraCaptureView {
  // iOS: makeUIViewController → 拉起 .camera 仅图片。
  // 返回拍到的照片 URI；用户取消时返回 null。
  static async capturePhoto(context: common.UIAbilityContext): Promise<string | null> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.PHOTO],
        profile
      );
      // resultCode === 0 表示成功，resultUri 为拍到的照片。
      if (result.resultCode === 0 && result.resultUri.length > 0) {
        return result.resultUri;
      }
      return null;
    } catch (e) {
      // 取消或设备无相机：回落 null，由调用方提示「先从相册选」。
      return null;
    }
  }
}
