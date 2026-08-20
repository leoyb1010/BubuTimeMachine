import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaStore } from '../MediaStore';
import { zlib } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const DOMAIN = 0x0000;

// MARK: - 全量档案导出（对照 iOS Services/Media/ArchiveExporter.swift）
// 导出 index.html + data.json + media/，覆盖照片、视频、语音、家人合奏与成长之声。
// iOS 写临时目录；HarmonyOS 写应用 cacheDir 下的一个时间戳目录，返回该目录路径。

// 以下 interface 对照 iOS 的各 Snapshot struct（字段一一对应）。
export interface MediaSnapshot {
  fileName: string;
  type: string;
  resourceRole?: string;
}

export interface VoiceSnapshot {
  fileName: string;
  duration: number;
  authorRole: string;
  transcript?: string;
}

export interface CommentSnapshot {
  authorRole: string;
  text?: string;
  voiceFileName?: string;
  voiceDuration: number;
  createdAt: number;
}

export interface EntrySnapshot {
  happenedAt: number;
  authorRole: string;
  note?: string;
  firstPersonNote?: string;
  locationName?: string;
  moodEmoji?: string;
  ageDescription: string;
  media: MediaSnapshot[];
  voiceNotes: VoiceSnapshot[];
  comments: CommentSnapshot[];
  tags: string[];
}

export interface VoiceMemoSnapshot {
  kind: string;
  fileName?: string;
  transcript?: string;
  ageYears?: number;
  recordedAt: number;
  durationSeconds?: number;
}

export interface MilestoneSnapshot {
  title: string;
  emoji: string;
  achieved: boolean;
  ageDescription?: string;
}

export interface HealthRecordSnapshot {
  kind: string;
  title: string;
  detail?: string;
  recordedAt: number;
  amountText?: string;
  reaction?: string;
}

export interface FirstTimeSnapshot {
  what: string;
  happenedAt: number;
  confirmed: boolean;
}

export interface TimeCapsuleSnapshot {
  id: string;
  title: string;
  fromRole: string;
  unlockAt: number;
  isLocked: boolean;
  coverEmoji?: string;
  encryptedBlobFileName?: string;
}

export interface GrowthSnapshot {
  measuredAt: number;
  heightCm?: number;
  weightKg?: number;
  headCircumferenceCm?: number;
  note?: string;
  source: string;
}

export interface VaccineSnapshot {
  vaccineName: string;
  doseLabel?: string;
  injectedAt: number;
  hospital?: string;
  injectionSite?: string;
  reaction?: string;
  note?: string;
}

export interface ExportInput {
  childName: string;
  birthday: number;
  entries: EntrySnapshot[];
  milestones: MilestoneSnapshot[];
  voiceMemos: VoiceMemoSnapshot[];
  healthRecords: HealthRecordSnapshot[];
  growthMeasurements: GrowthSnapshot[];
  vaccines: VaccineSnapshot[];
  firstTimes: FirstTimeSnapshot[];
  timeCapsules: TimeCapsuleSnapshot[];
  unavailableReferences: string[];
}

export class ArchiveExporter {
  static readonly shared = new ArchiveExporter();
  private mediaStore: MediaStore = MediaStore.shared;

  private constructor() {}

  // iOS: func export(_ input:) throws -> URL
  async export(input: ExportInput): Promise<string> {
    const cacheBase = this.mediaStore.cacheDir();
    const stamp = Math.floor(Date.now() / 1000);
    const root = `${cacheBase}/布布的一生_${stamp}`;
    const mediaDir = `${root}/media`;
    ArchiveExporter.mkdirp(root);
    ArchiveExporter.mkdirp(mediaDir);

    // 收集所有引用到的文件名（去重）。
    const names = new Set<string>();
    for (const entry of input.entries) {
      for (const m of entry.media) names.add(m.fileName);
      for (const v of entry.voiceNotes) names.add(v.fileName);
      for (const c of entry.comments) {
        if (c.voiceFileName) names.add(c.voiceFileName);
      }
    }
    for (const memo of input.voiceMemos) {
      if (memo.fileName) names.add(memo.fileName);
    }
    for (const capsule of input.timeCapsules) {
      if (capsule.encryptedBlobFileName) names.add(capsule.encryptedBlobFileName);
    }
    const missing: string[] = input.unavailableReferences.slice();
    for (const name of names) {
      const src = this.mediaStore.fullPath(name);
      const dest = `${mediaDir}/${name}`;
      try {
        if (fileIo.accessSync(src) && !fileIo.accessSync(dest)) {
          fileIo.copyFileSync(src, dest);
        } else if (!fileIo.accessSync(src)) {
          missing.push(name);
        }
      } catch (e) {
        missing.push(name);
      }
    }

    const incomplete = Array.from(new Set<string>(missing)).sort();
    ArchiveExporter.writeText(`${root}/data.json`, ArchiveExporter.buildJSON(input, incomplete));
    ArchiveExporter.writeText(`${root}/index.html`, ArchiveExporter.buildHTML(input));
    ArchiveExporter.writeText(`${root}/incomplete.json`, JSON.stringify(incomplete, null, 2));
    await ArchiveExporter.buildManifest(root, names);
    if (incomplete.length > 0) {
      throw new Error(`档案不完整：${incomplete.length} 个文件或引用尚未回到本机，请先完成全量同步再导出`);
    }
    return root;
  }

  async exportZip(input: ExportInput): Promise<string> {
    const folder = await this.export(input);
    const zipPath = `${folder}.zip`;
    await zlib.compressFile(folder, zipPath, {});
    return zipPath;
  }

  // MARK: HTML

  private static buildHTML(input: ExportInput): string {
    const milestones = input.milestones.filter((item: MilestoneSnapshot): boolean => item.achieved)
      .map((item: MilestoneSnapshot): string =>
        `<li>${item.emoji} ${esc(item.title)} <em>${esc(item.ageDescription ?? '')}</em></li>`)
      .join('');

    const voiceMemos = input.voiceMemos.slice()
      .sort((a: VoiceMemoSnapshot, b: VoiceMemoSnapshot): number => b.recordedAt - a.recordedAt)
      .map((memo: VoiceMemoSnapshot): string => {
        const title = memo.kind === 'childVoice' ? '布布的声音' : '家人对她说';
        const audio = memo.fileName ? `<audio controls src="media/${urlEsc(memo.fileName)}"></audio>` : '';
        const transcript = memo.transcript ? `<p>${esc(memo.transcript)}</p>` : '';
        const age = memo.ageYears !== undefined ? `${memo.ageYears}岁` : '未知年龄';
        return `<div class="memo"><b>${title}</b><span>${longDate(memo.recordedAt)} · ${age}</span>${audio}${transcript}</div>`;
      }).join('');

    const health = input.healthRecords.slice()
      .sort((a: HealthRecordSnapshot, b: HealthRecordSnapshot): number => b.recordedAt - a.recordedAt)
      .map((item: HealthRecordSnapshot): string => {
        const detail = item.detail ? `<p>${esc(item.detail)}</p>` : '';
        const amount = item.amountText ? ` · ${esc(item.amountText)}` : '';
        const reaction = item.reaction ? ` · 反应：${esc(item.reaction)}` : '';
        return `<li><b>${esc(item.title)}</b><span>${longDate(item.recordedAt)} · ${esc(item.kind)}${amount}${reaction}</span>${detail}</li>`;
      }).join('');

    const firstTimes = input.firstTimes.slice()
      .sort((a: FirstTimeSnapshot, b: FirstTimeSnapshot): number => b.happenedAt - a.happenedAt)
      .map((item: FirstTimeSnapshot): string =>
        `<li>✨ ${esc(item.what)} <em>${longDate(item.happenedAt)}</em></li>`)
      .join('');

    const capsules = input.timeCapsules.slice()
      .sort((a: TimeCapsuleSnapshot, b: TimeCapsuleSnapshot): number => a.unlockAt - b.unlockAt)
      .map((item: TimeCapsuleSnapshot): string => {
        const state = item.isLocked ? '未到开启时间' : '已开启';
        const emoji = item.coverEmoji ?? '💌';
        return `<li>${esc(emoji)} ${esc(item.title)} · ${esc(item.fromRole)} <em>${longDate(item.unlockAt)} · ${state}</em></li>`;
      }).join('');

    const growth = input.growthMeasurements.slice()
      .sort((a: GrowthSnapshot, b: GrowthSnapshot): number => b.measuredAt - a.measuredAt)
      .map((item: GrowthSnapshot): string =>
        `<li><b>${longDate(item.measuredAt)}</b> · ${item.heightCm ?? '-'} cm · ${item.weightKg ?? '-'} kg</li>`)
      .join('');

    const vaccines = input.vaccines.slice()
      .sort((a: VaccineSnapshot, b: VaccineSnapshot): number => b.injectedAt - a.injectedAt)
      .map((item: VaccineSnapshot): string =>
        `<li><b>${esc(item.vaccineName)} ${esc(item.doseLabel ?? '')}</b> · ${longDate(item.injectedAt)}</li>`)
      .join('');

    const cards = input.entries.slice()
      .sort((a: EntrySnapshot, b: EntrySnapshot): number => b.happenedAt - a.happenedAt)
      .map((entry: EntrySnapshot): string => {
        const mediaHtml = entry.media.map(mediaHTML).join('');
        const voices = entry.voiceNotes.map((voice: VoiceSnapshot): string => {
          const transcript = voice.transcript ? `<p>${esc(voice.transcript)}</p>` : '';
          return `<div class="audio"><span>🎙️ ${esc(voice.authorRole)}</span><audio controls src="media/${urlEsc(voice.fileName)}"></audio>${transcript}</div>`;
        }).join('');
        const comments = entry.comments.slice()
          .sort((a: CommentSnapshot, b: CommentSnapshot): number => a.createdAt - b.createdAt)
          .map((comment: CommentSnapshot): string => {
            const text = comment.text ? `<p>${esc(comment.text)}</p>` : '';
            const audio = comment.voiceFileName ? `<audio controls src="media/${urlEsc(comment.voiceFileName)}"></audio>` : '';
            return `<div class="comment"><b>${esc(comment.authorRole)}</b>${text}${audio}</div>`;
          }).join('');
        const mood = entry.moodEmoji ?? '';
        const place = entry.locationName ? ` · 📍${esc(entry.locationName)}` : '';
        const note = entry.note ? `<p class="note">${esc(entry.note)}</p>` : '';
        const fp = entry.firstPersonNote ? `<p class="fp">「${esc(entry.firstPersonNote)}」</p>` : '';
        const tags = entry.tags.length === 0 ? ''
          : '<div class="tags">' + entry.tags.map((t: string): string => `<span>#${esc(t)}</span>`).join('') + '</div>';
        const voiceBlock = voices.length === 0 ? '' : `<div class="voices"><h3>语音记录</h3>${voices}</div>`;
        const commentBlock = comments.length === 0 ? '' : `<div class="comments"><h3>家人合奏</h3>${comments}</div>`;
        return `<div class="card">
  <div class="meta">${mood} ${longDate(entry.happenedAt)} · ${esc(entry.authorRole)}${place} · <em>${esc(entry.ageDescription)}</em></div>
  <div class="media">${mediaHtml}</div>
  ${note}${fp}${tags}${voiceBlock}${commentBlock}
</div>`;
      }).join('');

    const style = ':root{--pink:#F28C9E;--brown:#5C4D47;--bg:#FBF6F0}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--brown);font-family:-apple-system,"PingFang SC",sans-serif;line-height:1.7}header{text-align:center;padding:48px 20px 24px}header h1{font-size:34px;margin:0}header p{color:#8a7d76;margin:6px 0}.wrap{max-width:760px;margin:0 auto;padding:0 16px 80px}.card,.milestones,.voice-memos{background:#fff;border-radius:18px;padding:18px 20px;margin:16px 0;box-shadow:0 4px 16px rgba(0,0,0,.05)}h2{font-size:18px;margin:0 0 10px}.meta{font-size:13px;color:#8a7d76;margin-bottom:10px}.meta em,.milestones em{color:var(--pink);font-style:normal}.media{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px}.media img,.media video{width:100%;aspect-ratio:1;object-fit:cover;border-radius:10px;background:#eee}.note{font-size:17px;margin:12px 0 4px}.fp{color:var(--pink);font-style:italic}.tags span{display:inline-block;background:rgba(242,140,158,.1);color:var(--pink);border-radius:20px;padding:2px 10px;font-size:12px;margin:4px 4px 0 0}h3{font-size:15px;margin:14px 0 6px}.audio,.comment,.memo{border-top:1px solid #f1e8e1;padding-top:10px;margin-top:10px}.audio audio,.comment audio,.memo audio{width:100%;margin-top:6px}.memo span{display:block;color:#8a7d76;font-size:12px}footer{text-align:center;color:#b0a59e;font-size:13px;padding:30px}';

    const section = (cond: boolean, html: string): string => (cond ? html : '');

    return `<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(input.childName)}的一生</title>
<style>${style}</style></head><body><header><h1>${esc(input.childName)}的一生</h1><p>出生于 ${longDate(input.birthday)}</p><p>共 ${input.entries.length} 个瞬间 · 由布布时光机生成</p></header><div class="wrap">
${section(milestones.length > 0, `<div class="milestones"><h2>🌟 成长里程碑</h2><ul>${milestones}</ul></div>`)}
${section(firstTimes.length > 0, `<div class="milestones"><h2>✨ 人生第一次</h2><ul>${firstTimes}</ul></div>`)}
${section(health.length > 0, `<div class="voice-memos"><h2>🩺 健康照护</h2><ul>${health}</ul></div>`)}
${section(growth.length > 0, `<div class="voice-memos"><h2>📏 成长测量</h2><ul>${growth}</ul></div>`)}
${section(vaccines.length > 0, `<div class="voice-memos"><h2>💉 疫苗记录</h2><ul>${vaccines}</ul></div>`)}
${section(capsules.length > 0, `<div class="milestones"><h2>💌 时间胶囊</h2><ul>${capsules}</ul></div>`)}
${section(voiceMemos.length > 0, `<div class="voice-memos"><h2>🎙️ 成长之声</h2>${voiceMemos}</div>`)}
${cards}</div><footer>这是布布的时光机 · 永久离线可读</footer></body></html>`;
  }

  // MARK: JSON

  private static buildJSON(input: ExportInput, incomplete: string[]): string {
    return JSON.stringify({ archiveVersion: 2, incompleteReferences: incomplete, data: input }, null, 2);
  }

  private static async buildManifest(root: string, mediaNames: Set<string>): Promise<void> {
    const relativePaths: string[] = ['data.json', 'index.html', 'incomplete.json'];
    for (const name of mediaNames) {
      const path = `${root}/media/${name}`;
      try { if (fileIo.accessSync(path)) relativePaths.push(`media/${name}`); } catch (e) {}
    }
    relativePaths.sort();
    const lines: string[] = [];
    for (const relative of relativePaths) {
      lines.push(`${await ArchiveExporter.sha256File(`${root}/${relative}`)}  ${relative}`);
    }
    ArchiveExporter.writeText(`${root}/manifest.sha256`, lines.join('\n') + '\n');
  }

  private static async sha256File(path: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(path).size;
      let readTotal = 0;
      while (readTotal < size) {
        const chunk = new ArrayBuffer(Math.min(1048576, size - readTotal));
        const count = fileIo.readSync(file.fd, chunk);
        if (count <= 0) break;
        await md.update({ data: new Uint8Array(chunk.slice(0, count)) });
        readTotal += count;
      }
      const digest = await md.digest();
      return Array.from(digest.data).map((value: number): string => value.toString(16).padStart(2, '0')).join('');
    } finally {
      fileIo.closeSync(file);
    }
  }

  // MARK: 文件工具

  private static mkdirp(dir: string): void {
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `建目录失败: ${JSON.stringify(e)}`);
    }
  }

  private static writeText(path: string, content: string): void {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, content);
      fileIo.closeSync(file);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `写文件失败: ${JSON.stringify(e)}`);
    }
  }
}

// MARK: - 顶层工具函数（对照 iOS 的 static esc/jsonEsc/urlEsc + DateFormatter）

function mediaHTML(media: MediaSnapshot): string {
  const path = `media/${urlEsc(media.fileName)}`;
  switch (media.type) {
    case 'video': return `<video controls src="${path}"></video>`;
    case 'audio': return `<audio controls src="${path}"></audio>`;
    default: return `<img src="${path}" loading="lazy">`;
  }
}

// iOS: DateFormatter "yyyy年M月d日"（zh_CN）
function longDate(epochMs: number): string {
  const d = new Date(epochMs);
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
}

// iOS: ISO8601DateFormatter
function iso(epochMs: number): string {
  return new Date(epochMs).toISOString();
}

function esc(s: string): string {
  return s.replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function jsonEsc(s: string): string {
  return s.replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n');
}

function urlEsc(s: string): string {
  return encodeURI(s);
}
