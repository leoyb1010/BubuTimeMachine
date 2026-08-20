import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { MediaStore } from './MediaStore';

export interface PreparedVideoUpload {
  path: string;
  fileName: string;
  temporary: boolean;
}

export class VideoUploadPreparer {
  static async prepare(fileName: string, width?: number, height?: number): Promise<PreparedVideoUpload | null> {
    const sourcePath = MediaStore.shared.fullPath(fileName);
    const size = MediaStore.fileSizeAt(sourcePath);
    if (size === null) return null;
    if (size <= MediaStore.publicUploadSoftLimitBytes) {
      return { path: sourcePath, fileName: fileName, temporary: false };
    }

    const outputName = `sync_${util.generateRandomUUID(true)}.mp4`;
    const outputPath = MediaStore.shared.fullPath(outputName);
    const source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    const output = fileIo.openSync(outputPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    const transcoder = await media.createAVTranscoder();
    let succeeded = false;
    try {
      transcoder.fdSrc = { fd: source.fd, offset: 0, length: size };
      transcoder.fdDst = output.fd;
      const dimensions = VideoUploadPreparer.outputDimensions(width, height);
      const completed = new Promise<void>((resolve, reject) => {
        transcoder.on('complete', (): void => { resolve(); });
        transcoder.on('error', (error: Error): void => { reject(error); });
      });
      const config: media.AVTranscoderConfig = {
        fileFormat: media.ContainerFormatType.CFT_MPEG_4,
        videoCodec: media.CodecMimeType.VIDEO_AVC,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        videoBitrate: 900000,
        audioBitrate: 64000,
        videoFrameWidth: dimensions[0],
        videoFrameHeight: dimensions[1],
        enableBFrame: true
      };
      await transcoder.prepare(config);
      await transcoder.start();
      await completed;
      const outputSize = MediaStore.fileSizeAt(outputPath);
      succeeded = outputSize !== null && outputSize > 0 && outputSize <= MediaStore.publicUploadSoftLimitBytes;
      return succeeded ? { path: outputPath, fileName: outputName, temporary: true } : null;
    } catch (e) {
      return null;
    } finally {
      try { await transcoder.release(); } catch (e) {}
      try { fileIo.closeSync(source); } catch (e) {}
      try { fileIo.closeSync(output); } catch (e) {}
      if (!succeeded) try { fileIo.unlinkSync(outputPath); } catch (e) {}
    }
  }

  static cleanup(prepared: PreparedVideoUpload): void {
    if (!prepared.temporary) return;
    try { fileIo.unlinkSync(prepared.path); } catch (e) {}
  }

  private static outputDimensions(width?: number, height?: number): number[] {
    const sourceWidth = width ?? 1280;
    const sourceHeight = height ?? 720;
    const scale = Math.min(1, 1280 / Math.max(sourceWidth, sourceHeight));
    const outWidth = Math.max(240, Math.round(sourceWidth * scale / 2) * 2);
    const outHeight = Math.max(240, Math.round(sourceHeight * scale / 2) * 2);
    return [outWidth, outHeight];
  }
}
