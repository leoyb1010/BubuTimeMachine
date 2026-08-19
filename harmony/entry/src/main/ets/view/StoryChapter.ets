import { Entry } from '../models/Models';
import { AgeCalculator } from '../models/AgeCalculator';
import { Mood, moodEmoji } from '../models/Enums';
import { BubuDateFormat } from '../theme/BubuDateFormat';

export interface StoryChapter {
  id: string;
  number: number;
  title: string;
  ageText: string;
  dateText: string;
  lines: string[];
  hue: number;
  emoji: string;
  entryId: string;
  photoFileName?: string;
}

export function chapterNoText(ch: StoryChapter): string { return `第 ${ch.number} 章`; }

export class StoryChapterBuilder {
  static chapters(entries: Entry[], birthday: number | undefined,
                  coverByEntry: Map<string, string>): StoryChapter[] {
    const picked = entries
      .filter((entry: Entry): boolean => entry.inStorybook === true && !entry.isArchived)
      .sort((a: Entry, b: Entry): number => a.happenedAt - b.happenedAt);
    return picked.map((entry: Entry, index: number): StoryChapter => {
      const body = StoryChapterBuilder.storyText(entry);
      const title = StoryChapterBuilder.chapterTitle(entry, body);
      return {
        id: entry.id,
        number: index + 1,
        title,
        ageText: birthday === undefined ? '' : AgeCalculator.ageDescription(birthday, entry.happenedAt),
        dateText: BubuDateFormat.yearMonthDay(new Date(entry.happenedAt)),
        lines: StoryChapterBuilder.splitLines(body),
        hue: StoryChapterBuilder.hueFromTitle(title),
        emoji: entry.moodRaw ? moodEmoji(entry.moodRaw as Mood) : '✨',
        entryId: entry.id,
        photoFileName: coverByEntry.get(entry.id)
      };
    });
  }

  private static storyText(entry: Entry): string {
    const firstPerson = (entry.firstPersonNote ?? '').trim();
    if (firstPerson.length > 0) return firstPerson;
    const note = (entry.note ?? '').trim();
    if (note.length > 0) return note;
    return '这一天，布布留下了一段没有文字的时光，\n但它已经被悄悄收进这本书里。';
  }

  private static chapterTitle(entry: Entry, body: string): string {
    const title = (entry.title ?? '').trim();
    if (title.length > 0) return title;
    const first = StoryChapterBuilder.splitLines(body)[0] ?? '';
    return first.length > 0 && first.length <= 18 ? first : '布布的这一天';
  }

  private static splitLines(text: string): string[] {
    const normalized = text.split('\n').join('。');
    const terminators = '。！？!?.';
    const parts: string[] = [];
    let current = '';
    for (const char of normalized) {
      current += char;
      if (terminators.includes(char)) {
        const value = current.trim();
        if (value.length > 0) parts.push(value);
        current = '';
      }
    }
    const tail = current.trim();
    if (tail.length > 0) parts.push(tail);
    return parts.length > 0 ? parts : [text];
  }

  static hueFromTitle(title: string): number {
    let hash = 0;
    for (let i = 0; i < title.length; i++) hash = (hash * 31 + title.charCodeAt(i)) | 0;
    return Math.abs(hash) % 360;
  }
}
