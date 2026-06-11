import SwiftUI
import UIKit

// MARK: - 直接录像（Wave L §5.7）
/// 用系统相机录像，限 60s。姥姥手抖防误触：系统录像界面本身有大停止按钮。
/// 录完回调本地临时文件 URL，由 CaptureModel 走统一视频导入管线（压缩 + 缩略图）。
struct VideoCaptureView: UIViewControllerRepresentable {
    var onVideo: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoCaptureView

        init(parent: VideoCaptureView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onCancel()
            if let url = info[.mediaURL] as? URL {
                DispatchQueue.main.async { self.parent.onVideo(url) }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
