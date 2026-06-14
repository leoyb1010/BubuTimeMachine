import { Mood } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 布布表情贴纸（对照 iOS DesignSystem/BubuExpression.swift）
// 一套与 logo 同系的布布插画。每个表情是独立 asset，按语义/心情选择。
export enum BubuExpression {
  eating = 'BubuEating',
  drinking = 'BubuDrinking',
  sleeping = 'BubuSleeping',
  playing = 'BubuPlaying',
  sport = 'BubuSport',
  reading = 'BubuReading',
  drawing = 'BubuDrawing',
  happy = 'BubuHappy',
  surprised = 'BubuSurprised',
  angry = 'BubuAngry',
  shy = 'BubuShy',
  thinking = 'BubuThinking',
  cheer = 'BubuCheer',
  bye = 'BubuBye',
  love = 'BubuLove',
  travel = 'BubuTravel',
  bath = 'BubuBath',
  music = 'BubuMusic',
  tv = 'BubuTV',
  yeah = 'BubuYeah'
}

// iOS: BubuExpression.forMood —— 心情 → 表情贴纸（找不到贴切的回落到开心/比心）。
export function expressionForMood(mood: Mood | undefined): BubuExpression {
  switch (mood) {
    case Mood.happy: return BubuExpression.happy;
    case Mood.calm: return BubuExpression.reading;
    case Mood.naughty: return BubuExpression.yeah;
    case Mood.proud: return BubuExpression.cheer;
    case Mood.curious: return BubuExpression.thinking;
    case Mood.sleepy: return BubuExpression.sleeping;
    case Mood.grievance: return BubuExpression.shy;
    case Mood.milestone: return BubuExpression.cheer;
    case Mood.eating: return BubuExpression.eating;
    case Mood.laughing: return BubuExpression.happy;
    case Mood.crying: return BubuExpression.shy;
    case Mood.angry: return BubuExpression.angry;
    case Mood.surprised: return BubuExpression.surprised;
    case Mood.brave: return BubuExpression.sport;
    case Mood.cuddly: return BubuExpression.love;
    case Mood.sick: return BubuExpression.drinking;
    case Mood.playful: return BubuExpression.playing;
    case Mood.focused: return BubuExpression.drawing;
    case Mood.shy: return BubuExpression.shy;
    case Mood.love: return BubuExpression.love;
    default: return BubuExpression.happy;
  }
}

// 表情 → emoji 兜底（资源贴纸缺失时显示）。复用心情 emoji 语义。
function expressionEmoji(e: BubuExpression): string {
  switch (e) {
    case BubuExpression.eating: return '😋';
    case BubuExpression.drinking: return '🥤';
    case BubuExpression.sleeping: return '😴';
    case BubuExpression.playing: return '🧸';
    case BubuExpression.sport: return '💪';
    case BubuExpression.reading: return '📖';
    case BubuExpression.drawing: return '🎨';
    case BubuExpression.happy: return '😄';
    case BubuExpression.surprised: return '😮';
    case BubuExpression.angry: return '😤';
    case BubuExpression.shy: return '🫣';
    case BubuExpression.thinking: return '🤔';
    case BubuExpression.cheer: return '🎉';
    case BubuExpression.bye: return '👋';
    case BubuExpression.love: return '💗';
    case BubuExpression.travel: return '🧳';
    case BubuExpression.bath: return '🛁';
    case BubuExpression.music: return '🎵';
    case BubuExpression.tv: return '📺';
    case BubuExpression.yeah: return '✌️';
    default: return '😄';
  }
}

// MARK: - 布布吉祥物徽章（对照 iOS DesignSystem/Components/BubuMascotBadge.swift）
// 显示单张布布表情贴纸（绝不显示整张合集）。expression 优先；否则按 mood 自动选；都没有则默认开心。
@Component
export struct BubuMascotBadge {
  @Prop badgeSize: number = 54;
  @Prop expression?: BubuExpression;
  @Prop mood?: Mood;

  // iOS: resolved = expression ?? .forMood(mood)
  private resolved(): BubuExpression {
    return this.expression !== undefined ? this.expression : expressionForMood(this.mood);
  }

  build() {
    // NOTE: iOS 用 Image(asset) 加载布布贴纸；本切片未携带贴纸资源，
    // 故以 emoji 兜底渲染（按表情语义）。资源就绪后可改为 Image($r('app.media.<assetName>'))。
    Stack() {
      Text(expressionEmoji(this.resolved()))
        .fontSize(this.badgeSize * 0.6)
        .textAlign(TextAlign.Center)
    }
    .width(this.badgeSize)
    .height(this.badgeSize)
    .backgroundColor(BubuColor.cream)
    .borderRadius(this.badgeSize * 0.24)
    // logo 质感白描边
    .border({ width: 2, color: '#E6FFFFFF' })
    .shadow({ radius: 8, color: '#2EF28C9E', offsetY: 3 })
  }
}
