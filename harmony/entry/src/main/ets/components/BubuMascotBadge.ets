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

  private resolvedResource(): Resource {
    switch (this.resolved()) {
      case BubuExpression.eating: return $r('app.media.bubu_eating');
      case BubuExpression.drinking: return $r('app.media.bubu_drinking');
      case BubuExpression.sleeping: return $r('app.media.bubu_sleeping');
      case BubuExpression.playing: return $r('app.media.bubu_playing');
      case BubuExpression.sport: return $r('app.media.bubu_sport');
      case BubuExpression.reading: return $r('app.media.bubu_reading');
      case BubuExpression.drawing: return $r('app.media.bubu_drawing');
      case BubuExpression.happy: return $r('app.media.bubu_happy');
      case BubuExpression.surprised: return $r('app.media.bubu_surprised');
      case BubuExpression.angry: return $r('app.media.bubu_angry');
      case BubuExpression.shy: return $r('app.media.bubu_shy');
      case BubuExpression.thinking: return $r('app.media.bubu_thinking');
      case BubuExpression.cheer: return $r('app.media.bubu_cheer');
      case BubuExpression.bye: return $r('app.media.bubu_bye');
      case BubuExpression.love: return $r('app.media.bubu_love');
      case BubuExpression.travel: return $r('app.media.bubu_travel');
      case BubuExpression.bath: return $r('app.media.bubu_bath');
      case BubuExpression.music: return $r('app.media.bubu_music');
      case BubuExpression.tv: return $r('app.media.bubu_tv');
      case BubuExpression.yeah: return $r('app.media.bubu_yeah');
      default: return $r('app.media.bubu_happy');
    }
  }

  build() {
    Stack() {
      Image(this.resolvedResource())
        .width(this.badgeSize)
        .height(this.badgeSize)
        .objectFit(ImageFit.Cover)
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
