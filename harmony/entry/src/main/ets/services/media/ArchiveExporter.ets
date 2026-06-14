import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaStore } from '../MediaStore';

const DOMAIN = 0x0000;

// MARK: - 全量档案导出（对照 iOS Services/Media/ArchiveExporter.swift）
// 导出 index.html + data.json + media/，覆盖照片、视频、语音、家人合奏与成长之声。
// iOS 写临时目录；HarmonyOS 写应用 cacheDir 下的一个时间戳目录，返回该目录路径。

// 以下 interface 对照 iOS 的各 Snapshot struct（字段一一对应）。
export interface MediaSnapshot {
  fileName: string;
  type: string;
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
  title: string;
  fromRole: string;
  unlockAt: number;
  isLocked: boolean;
  coverEmoji?: string;
}

export interface ExportInput {
  childName: string;
  birthday: number;
  entries: EntrySnapshot[];
  milestones: MilestoneSnapshot[];
  voiceMemos: VoiceMemoSnapshot[];
  healthRecords: HealthRecordSnapshot[];
  firstTimes: FirstTimeSnapshot[];
  timeCapsules: TimeCapsuleSnapshot[];
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
    for (const name of names) {
      const src = this.mediaStore.fullPath(name);
      const dest = `${mediaDir}/${name}`;
      try {
        if (fileIo.accessSync(src) && !fileIo.accessSync(dest)) {
          fileIo.copyFileSync(src, dest);
        }
      } catch (e) {
        // 单个文件拷贝失败不阻塞整体导出。
      }
    }

    ArchiveExporter.writeText(`${root}/data.json`, ArchiveExporter.buildJSON(input));
    ArchiveExporter.writeText(`${root}/index.html`, ArchiveExporter.buildHTML(input));
    return root;
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
${section(capsules.length > 0, `<div class="milestones"><h2>💌 时间胶囊</h2><ul>${capsules}</ul></div>`)}
${section(voiceMemos.length > 0, `<div class="voice-memos"><h2>🎙️ 成长之声</h2>${voiceMemos}</div>`)}
${cards}</div><footer>这是布布的时光机 · 永久离线可读</footer></body></html>`;
  }

  // MARK: JSON

  private static buildJSON(input: ExportInput): string {
    const entries = input.entries.map((entry: EntrySnapshot): string => {
      const media = entry.media.map((m: MediaSnapshot): string =>
        `{"type":"${jsonEsc(m.type)}","file":"media/${jsonEsc(m.fileName)}"}`).join(',');
      const voices = entry.voiceNotes.map((v: VoiceSnapshot): string =>
        `{"author":"${jsonEsc(v.authorRole)}","file":"media/${jsonEsc(v.fileName)}","duration":${v.duration}}`).join(',');
      const comments = entry.comments.map((c: CommentSnapshot): string => {
        const textVal = c.text !== undefined ? `"${jsonEsc(c.text)}"` : 'null';
        const voiceVal = c.voiceFileName !== undefined ? `"media/${jsonEsc(c.voiceFileName)}"` : 'null';
        return `{"author":"${jsonEsc(c.authorRole)}","text":${textVal},"voice":${voiceVal}}`;
      }).join(',');
      const tags = entry.tags.map((t: string): string => `"${jsonEsc(t)}"`).join(',');
      const noteVal = entry.note !== undefined ? `"${jsonEsc(entry.note)}"` : 'null';
      const fpVal = entry.firstPersonNote !== undefined ? `"${jsonEsc(entry.firstPersonNote)}"` : 'null';
      const locVal = entry.locationName !== undefined ? `"${jsonEsc(entry.locationName)}"` : 'null';
      return `{"happenedAt":"${iso(entry.happenedAt)}","author":"${jsonEsc(entry.authorRole)}","age":"${jsonEsc(entry.ageDescription)}","note":${noteVal},"firstPerson":${fpVal},"location":${locVal},"media":[${media}],"voiceNotes":[${voices}],"comments":[${comments}],"tags":[${tags}]}`;
    }).join(',');
    return `{"childName":"${jsonEsc(input.childName)}","birthday":"${iso(input.birthday)}","entries":[${entries}]}`;
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
