import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const viewer = await readFile(new URL('../entry/src/main/ets/components/MediaViewer.ets', import.meta.url), 'utf8');
const detail = await readFile(new URL('../entry/src/main/ets/view/EntryDetailView.ets', import.meta.url), 'utf8');

test('照片查看器使用真正双击缩放而不是单击近似', () => {
  assert.ok(viewer.includes('TapGesture({ count: 2 })'));
  assert.ok(viewer.includes('PinchGesture()'));
  assert.ok(!viewer.includes('以单击在缩放态间切换近似'));
});

test('时光详情的多媒体查看器可用单指左右翻页，放大后改为平移图片', () => {
  assert.ok(viewer.includes('private swiperController: SwiperController = new SwiperController()'));
  assert.ok(viewer.includes('Swiper(this.swiperController)'));
  assert.ok(viewer.includes('.cachedCount(1)'));
  assert.ok(viewer.includes('onSwipePage: (direction: number)'));
  assert.ok(viewer.includes('priorityGesture('));
  assert.ok(viewer.includes('PanGesture({ fingers: 1, direction: PanDirection.All'));
  assert.ok(viewer.includes('if (this.scaleValue > 1.01) return'));
  assert.ok(viewer.includes('this.swiperController.showNext()'));
  assert.ok(viewer.includes('this.swiperController.showPrevious()'));
  assert.ok(detail.includes('mediaItems: this.sortedMedia()'), '详情页必须把该条时光的全部媒体传给分页查看器');
});

test('远端受保护照片和视频先带家庭登录态下载，失败可重试且退出后清理临时文件', () => {
  assert.ok(viewer.includes('APIClient.shared.downloadFile(remote, destination)'));
  assert.ok(viewer.includes("Button('重试')"));
  assert.ok(viewer.includes('aboutToDisappear(): void'));
  assert.ok(viewer.includes('this.cleanupRemote()'));
  assert.ok(viewer.includes('fileIo.unlinkSync(this.remoteFilePath)'));
  assert.ok(!viewer.includes('本切片仅支持本地与裸 remoteURL'));
});

test('全屏查看器可保存到系统相册并通过 Share Kit 分享当前照片或视频', () => {
  assert.ok(viewer.includes('MediaLibraryService.save'));
  assert.ok(viewer.includes('ShareService.shareMedia'));
  assert.ok(viewer.includes("Text('保存')"));
  assert.ok(viewer.includes("Text('分享')"));
  assert.ok(viewer.includes('onRemoteReady'));
});
