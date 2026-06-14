import { Comment } from '../models/Models';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 亲一下 · 轻量反应（对照 iOS Features/Timeline/Reaction.swift）
// 适老化的互动形式：姥姥可能不打字，但一定会点亲亲。
// 零迁移设计：复用现有 Comment 模型与同步链路，反应是一条 text 以哨兵前缀开头的 Comment（"RXN:❤️"）。
// 同一人同一条只保留最新反应（插入前先删旧）。

export enum Reaction {
  heart = '❤️',
  hug = '🤗',
  laugh = '😂',
  moved = '😭'
}

// 全部反应（对照 iOS CaseIterable.allCases，固定顺序）。
export const ALL_REACTIONS: Reaction[] = [Reaction.heart, Reaction.hug, Reaction.laugh, Reaction.moved];

// 反应工具集合（对照 iOS enum Reaction 的静态/实例方法）。
export class ReactionUtil {
  private static readonly sentinel: string = 'RXN:';

  // 反应的中文标签（对照 iOS Reaction.label）。
  static label(r: Reaction): string {
    switch (r) {
      case Reaction.heart: return '亲亲';
      case Reaction.hug: return '抱抱';
      case Reaction.laugh: return '笑死';
      case Reaction.moved: return '感动';
      default: return '亲亲';
    }
  }

  // 把反应编码进 Comment.text（对照 iOS encodedText）。
  static encodedText(r: Reaction): string {
    return ReactionUtil.sentinel + r;
  }

  // 从 Comment.text 还原反应（非反应则返回 undefined，对照 iOS decode）。
  static decode(text: string | undefined): Reaction | undefined {
    if (text === undefined || !text.startsWith(ReactionUtil.sentinel)) return undefined;
    const raw = text.substring(ReactionUtil.sentinel.length);
    for (const r of ALL_REACTIONS) {
      if (r === raw) return r;
    }
    return undefined;
  }

  // 判断一条 Comment 是否是反应（对照 iOS isReaction）。
  static isReaction(comment: Comment): boolean {
    return ReactionUtil.decode(comment.text) !== undefined;
  }
}

// MARK: - 反应聚合（对照 iOS ReactionSummary）
export class ReactionSummary {
  // 每种反应的计数（去重：同一作者同一反应只算一次，取其最新）。
  counts: Map<Reaction, number>;
  // 当前身份已选的反应。
  mine?: Reaction;

  constructor(counts: Map<Reaction, number>, mine?: Reaction) {
    this.counts = counts;
    this.mine = mine;
  }

  get isEmpty(): boolean {
    for (const r of ALL_REACTIONS) {
      if ((this.counts.get(r) ?? 0) > 0) return false;
    }
    return true;
  }

  count(r: Reaction): number {
    return this.counts.get(r) ?? 0;
  }

  // 从一条 Entry 的 comments 聚合（对照 iOS ReactionSummary.from）。
  static from(comments: Comment[], myRole: string): ReactionSummary {
    // 每个作者只保留最新一条反应。
    const latestAt: Map<string, number> = new Map();
    const latestReaction: Map<string, Reaction> = new Map();
    for (const c of comments) {
      const r = ReactionUtil.decode(c.text);
      if (r === undefined) continue;
      const existing = latestAt.get(c.authorRole);
      if (existing !== undefined && existing >= c.createdAt) continue;
      latestAt.set(c.authorRole, c.createdAt);
      latestReaction.set(c.authorRole, r);
    }
    const counts: Map<Reaction, number> = new Map();
    latestReaction.forEach((r: Reaction) => {
      counts.set(r, (counts.get(r) ?? 0) + 1);
    });
    return new ReactionSummary(counts, latestReaction.get(myRole));
  }
}

// MARK: - 反应聚合行（卡片/详情元信息行尾，对照 iOS ReactionRow）
@Component
export struct ReactionRow {
  @Prop summary: ReactionSummary;

  build() {
    if (!this.summary.isEmpty) {
      Row({ space: 8 }) {
        ForEach(ALL_REACTIONS, (r: Reaction) => {
          if (this.summary.count(r) > 0) {
            Row({ space: 2 }) {
              Text(r).fontSize(13)
              Text(`${this.summary.count(r)}`)
                .fontSize(15).fontWeight(FontWeight.Medium)
                .fontColor(BubuColor.secondaryText)
            }
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(BubuColor.softFill)
            .borderRadius(100)
          }
        }, (r: Reaction) => r)
      }
    }
  }
}

// MARK: - 弹出的反应选择条（对照 iOS ReactionPicker）
@Component
export struct ReactionPicker {
  @Prop current?: Reaction;
  onPick?: (r: Reaction) => void;

  build() {
    Row({ space: 14 }) {
      ForEach(ALL_REACTIONS, (r: Reaction) => {
        Text(r)
          .fontSize(30)
          .padding(4)
          .scale({ x: this.current === r ? 1.25 : 1.0, y: this.current === r ? 1.25 : 1.0 })
          .onClick(() => { if (this.onPick) this.onPick(r); })
      }, (r: Reaction) => r)
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(BubuColor.elevatedCard)
    .borderRadius(100)
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
  }
}
