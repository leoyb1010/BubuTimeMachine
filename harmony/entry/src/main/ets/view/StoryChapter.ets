// MARK: - 成长绘本章节（派生模型，不入库）（对照 iOS Features/Story/StoryChapter.swift）
// 把已达成、有「那一天的故事」(Milestone.detail) 的里程碑按时间编织成可翻页阅读的章节。
// 纯派生——不新增持久化模型、不写库，数据随里程碑实时变化。

import { Milestone } from '../models/Models';
import { BubuDateFormat } from '../theme/BubuDateFormat';

// 章节结构（对照 iOS struct StoryChapter: Identifiable, Hashable）
export interface StoryChapter {
  id: string;            // = milestone.id（章节稳定标识）
  number: number;        // 第几章（1 起）
  title: string;         // 章名（取里程碑标题）
  ageText: string;       // 年龄（Milestone.ageDescription，兜底空串）
  dateText: string;      // 日期（happenedAt 格式化）
  lines: string[];       // 正文逐行（把 detail 按句拆行，便于逐行浮现动画）
  hue: number;           // 章节配色（由标题哈希生成，呼应星座/详情）
  emoji: string;
  milestoneId: string;
}

// 第 N 章（对照 iOS noText 计算属性）
export function chapterNoText(ch: StoryChapter): string {
  return `第 ${ch.number} 章`;
}

// MARK: - 章节编织器（对照 iOS enum StoryChapterBuilder）
export class StoryChapterBuilder {
  /// 把里程碑编织成章节：仅取「已达成」的，按发生时间升序；正文优先 detail。
  static chapters(milestones: Milestone[]): StoryChapter[] {
    const achieved: Milestone[] = milestones
      .filter((m: Milestone) => m.happenedAt !== undefined && m.happenedAt !== null)
      .sort((a: Milestone, b: Milestone) =>
        (a.happenedAt ?? 0) - (b.happenedAt ?? 0));

    return achieved.map((m: Milestone, idx: number) => {
      const rawDetail: string = (m.detail ?? '').trim();
      const body: string = rawDetail.length > 0 ? rawDetail : StoryChapterBuilder.defaultLine(m);
      const ch: StoryChapter = {
        id: m.id,
        number: idx + 1,
        title: m.title,
        ageText: m.ageDescription ?? '',
        dateText: m.happenedAt !== undefined && m.happenedAt !== null
          ? BubuDateFormat.yearMonthDay(new Date(m.happenedAt)) : '',
        lines: StoryChapterBuilder.splitLines(body),
        hue: StoryChapterBuilder.hueFromTitle(m.title),
        emoji: m.emoji,
        milestoneId: m.id
      };
      return ch;
    });
  }

  /// 没有故事文案时的温柔兜底（不会空着一页）。
  private static defaultLine(m: Milestone): string {
    return `这一天，布布完成了「${m.title}」。\n虽然还没写下故事，但这一刻已经被悄悄收藏。`;
  }

  /// 按中文句末标点 / 换行拆成若干行，便于逐行 fadeUp。（对照 iOS splitLines）
  private static splitLines(text: string): string[] {
    const normalized: string = text.split('\n').join('。');
    const terminators: string = '。！？!?.';
    const parts: string[] = [];
    let current: string = '';
    for (const ch of normalized) {
      current += ch;
      if (terminators.indexOf(ch) >= 0) {
        const trimmed: string = current.trim();
        if (trimmed.length > 0) { parts.push(trimmed); }
        current = '';
      }
    }
    const tail: string = current.trim();
    if (tail.length > 0) { parts.push(tail); }
    return parts.length === 0 ? [text] : parts;
  }

  /// 由标题生成稳定色相（对照 iOS abs(title.hashValue) % 360）。
  /// ArkTS 无 hashValue，用确定性字符串哈希（djb2 变体）对齐「同标题同色」语义。
  static hueFromTitle(title: string): number {
    let hash: number = 0;
    for (let i = 0; i < title.length; i++) {
      hash = (hash * 31 + title.charCodeAt(i)) | 0;
    }
    return Math.abs(hash) % 360;
  }
}
