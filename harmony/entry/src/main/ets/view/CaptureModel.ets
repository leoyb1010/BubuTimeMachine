import { Mood } from '../models/Enums';
import { FamilyRole } from '../models/Enums';
import { ServerConfig } from '../services/ServerConfig';
import { EntryWriter } from '../services/EntryWriter';
import { AIService, NaturalCaptureResult } from '../services/AIService';
import { MediaStore } from '../services/MediaStore';
import { hilog } from '@kit.PerformanceAnalysisKit';

// MARK: - 记录此刻 业务模型（对照 iOS Features/Capture/CaptureModel.swift）
// iOS 是 @Observable @MainActor class：把选中的媒体落本地并自动分析，写入 SwiftData（Entry + Media）。
// ArkUI 用 @Observed class + @ObjectLink 在面板里双向观察；写入走 EntryWriter（与意图/小组件同一写入层）。
// NOTE: iOS 端的端侧分析（EXIF/地理/Vision）与多媒体数组在本切片简化为「单张照片 + 一段语音 + 文字 + 心情」，
//       对齐 Harmony EntryWriter.entryWithPhoto 的写入契约；多媒体批量管线后续可扩展。

// 已选媒体预览（对照 iOS SelectedMediaPreview）。
export interface SelectedMediaPreview {
  index: number;
  uri: string;        // 沙盒内文件 URI（用于 Image 显示）
  isVideo: boolean;
  label: string;
  fileName?: string;
}

const DOMAIN = 0x0000;

@Observed
export class CaptureModel {
  // —— 面板可见性（对照 iOS showQuickCapture）——
  showQuickCapture: boolean = false;

  // —— 草稿内容 ——
  note: string = '';
  mood?: Mood = undefined;

  // 已选媒体（对照 iOS pickedItems / cameraPhotos / cameraVideos 汇总为预览列表）。
  selectedPreviews: SelectedMediaPreview[] = [];
  // 落盘后的首张照片文件名（用于 EntryWriter.entryWithPhoto）。
  pickedPhotoName: string | null = null;

  // —— 语音（对照 iOS pendingVoice）——
  pendingVoiceFileName: string | null = null;
  pendingVoiceDuration: number = 0;
  pendingVoiceWaveform: number[] = [];

  // —— 地点（对照 iOS includeLocation / currentLocation）——
  includeLocation: boolean = false;
  currentLocationName: string | null = null;
  locationError: string | null = null;

  // —— 状态 ——
  isSaving: boolean = false;
  isLoadingPreviews: boolean = false;
  saveError: string | null = null;
  lastSavedSummary: string | null = null;
  savedFlash: boolean = false;
  analyzingHint: string | null = null;
  // 最近一次保存的 Entry id（对照 iOS lastSavedEntryID，供首页做「第一次」识别）。
  lastSavedEntryID: string | null = null;

  private role: FamilyRole;

  constructor(role: FamilyRole) {
    this.role = role;
  }

  // 进入快速记录：清空草稿、可预填一句（对照 iOS startQuickCapture）。
  startQuickCapture(prefillNote: string = ''): void {
    this.note = prefillNote;
    this.mood = undefined;
    this.includeLocation = false;
    this.currentLocationName = null;
    this.locationError = null;
    this.selectedPreviews = [];
    this.pickedPhotoName = null;
    this.pendingVoiceFileName = null;
    this.pendingVoiceDuration = 0;
    this.pendingVoiceWaveform = [];
    this.analyzingHint = null;
    this.saveError = null;
    this.lastSavedSummary = null;
    this.showQuickCapture = true;
  }

  private trimmedNote(): string {
    return this.note.trim();
  }

  // 是否有可保存内容（媒体 / 文字 / 语音 任一即可，对照 iOS canSave）。
  canSave(): boolean {
    return this.selectedPreviews.length > 0 ||
      this.pickedPhotoName !== null ||
      this.trimmedNote().length > 0 ||
      this.pendingVoiceFileName !== null;
  }

  // 选中系统相册一张照片 → 拷进沙盒，加入预览（对照 iOS persist(item:)）。
  addPhotoUri(uri: string): void {
    const ext = uri.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    const name = MediaStore.shared.copyIntoStore(uri, ext);
    if (name) {
      this.pickedPhotoName = name;
      const index = this.selectedPreviews.length;
      this.selectedPreviews = this.selectedPreviews.concat([{
        index,
        uri: 'file://' + MediaStore.shared.fullPath(name),
        isVideo: false,
        label: '照片',
        fileName: name
      }]);
    } else {
      this.saveError = '照片读取失败';
    }
  }

  // 加入一段录像预览（对照 iOS addCameraVideo）。
  // NOTE: 视频写入未接入 EntryWriter，本切片仅做预览展示与 // NOTE 占位。
  addVideoUri(uri: string): void {
    const name = MediaStore.shared.importFile(uri, 'mp4');
    if (name) {
      const index = this.selectedPreviews.length;
      this.selectedPreviews = this.selectedPreviews.concat([{
        index,
        uri: 'file://' + MediaStore.shared.fullPath(name),
        isVideo: true,
        label: '视频',
        fileName: name
      }]);
    } else {
      this.saveError = '视频读取失败';
    }
  }

  // 移除已选媒体（对照 iOS removePickedItem）。
  removePickedItem(index: number): void {
    const removed = this.selectedPreviews.find(p => p.index === index);
    if (removed && !removed.isVideo) {
      this.pickedPhotoName = null;
    }
    const remaining = this.selectedPreviews.filter(p => p.index !== index);
    // 重排索引（对照 iOS 重建 index）。
    this.selectedPreviews = remaining.map((p, i): SelectedMediaPreview => {
      return { index: i, uri: p.uri, isVideo: p.isVideo, label: p.label };
    });
    // 重排后首张照片重新认定。
    const firstPhoto = this.selectedPreviews.find(p => !p.isVideo && p.fileName !== undefined);
    this.pickedPhotoName = firstPhoto?.fileName ?? null;
  }

  // 设置语音（对照 iOS pendingVoice）。
  setPendingVoice(fileName: string, duration: number, waveform: number[]): void {
    this.pendingVoiceFileName = fileName;
    this.pendingVoiceDuration = duration;
    this.pendingVoiceWaveform = waveform;
  }

  clearPendingVoice(): void {
    this.pendingVoiceFileName = null;
    this.pendingVoiceDuration = 0;
    this.pendingVoiceWaveform = [];
  }

  // 保存为一个 Entry，返回是否成功（对照 iOS savePickedItems(into:)）。
  async save(): Promise<boolean> {
    if (!this.canSave()) {
      return false;
    }
    this.isSaving = true;
    const noteText = this.trimmedNote();
    try {
      const firstPhoto = this.selectedPreviews.find(p => !p.isVideo && p.fileName !== undefined);
      const photoName = firstPhoto?.fileName ?? this.pickedPhotoName;
      const videoNames = this.selectedPreviews
        .filter(p => p.isVideo && p.fileName !== undefined)
        .map(p => p.fileName!);
      const id = await EntryWriter.entryWithPhoto(
        noteText,
        photoName,
        this.role,
        this.mood,
        this.pendingVoiceFileName,
        this.pendingVoiceDuration,
        videoNames
      );
      this.lastSavedEntryID = id;
      const mediaCount = (photoName ? 1 : 0) + videoNames.length;
      const mediaText = mediaCount > 0 ? ` · ${mediaCount} 个媒体` : '';
      const voiceText = this.pendingVoiceFileName ? ' · 1 段语音' : '';
      this.lastSavedSummary = `已保存到手机${mediaText}${voiceText}`;
      // 清空草稿（对照 iOS 保存后重置）。
      this.note = '';
      this.mood = undefined;
      this.selectedPreviews = [];
      this.pickedPhotoName = null;
      this.clearPendingVoice();
      this.showQuickCapture = false;
      this.flashSaved();
      this.isSaving = false;
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `记录保存失败: ${JSON.stringify(e)}`);
      this.saveError = `保存失败：${JSON.stringify(e)}`;
      this.isSaving = false;
      return false;
    }
  }

  // 一句话记录：有 AI 则先解析规整，无 AI/失败则直接存原文（离线优先）。
  // 对照 iOS NaturalCaptureBar + AIService.parseNaturalCapture。
  async quickTextOnly(text: string): Promise<boolean> {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return false;
    }
    this.isSaving = true;
    let note = trimmed;
    let mood: Mood | undefined = undefined;
    try {
      if (AIService.shared.isConfigured) {
        const r: NaturalCaptureResult = await AIService.shared.parseNaturalCapture(trimmed);
        if (r.note && r.note.length > 0) {
          note = r.note;
        }
        if (r.mood) {
          mood = r.mood as Mood;
        }
      }
    } catch (e) {
      // 解析失败：用原文。
    }
    try {
      const id = await EntryWriter.quickTextEntry(note, this.role, mood);
      this.lastSavedEntryID = id;
      this.isSaving = false;
      this.flashSaved();
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `智能记录保存失败: ${JSON.stringify(e)}`);
      this.saveError = `保存失败：${JSON.stringify(e)}`;
      this.isSaving = false;
      return false;
    }
  }

  // 保存成功闪现（对照 iOS flashSaved，触觉/音效在 UI 层处理）。
  private flashSaved(): void {
    this.savedFlash = true;
    setTimeout(() => {
      this.savedFlash = false;
    }, 1800);
  }
}
