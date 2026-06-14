// MARK: - 布布表情贴纸（对照 iOS DesignSystem/BubuExpression.swift）
// 一套与 logo 同系的布布插画。每个表情都是独立 asset，按语义在产品里替换合适的位置/心情。
// iOS 用 enum: String + asset 名；HarmonyOS 这里用 enum（值即 asset 名），forMood 映射一致。

import { Mood } from '../models/Enums';

export enum BubuExpression {
  eating = 'BubuEating',          // 吃饭
  drinking = 'BubuDrinking',      // 喝水
  sleeping = 'BubuSleeping',      // 睡觉
  playing = 'BubuPlaying',        // 玩耍
  sport = 'BubuSport',            // 运动
  reading = 'BubuReading',        // 读书
  drawing = 'BubuDrawing',        // 画画
  happy = 'BubuHappy',            // 开心
  surprised = 'BubuSurprised',    // 惊讶
  angry = 'BubuAngry',            // 生气
  shy = 'BubuShy',                // 害羞
  thinking = 'BubuThinking',      // 思考
  cheer = 'BubuCheer',            // 加油
  bye = 'BubuBye',                // 拜拜
  love = 'BubuLove',              // 比心
  travel = 'BubuTravel',          // 旅行
  bath = 'BubuBath',              // 洗澡
  music = 'BubuMusic',            // 听音乐
  tv = 'BubuTV',                  // 看电视
  yeah = 'BubuYeah'               // 耶
}

export class BubuExpressionMap {
  /// asset 名（与 enum 值相同）。
  static assetName(e: BubuExpression): string { return e as string; }

  /// 心情 → 表情贴纸（找不到贴切的就回落到开心/比心）。对照 iOS forMood(_:)。
  static forMood(mood: Mood | undefined | null): BubuExpression {
    switch (mood) {
      case Mood.happy:      return BubuExpression.happy;
      case Mood.calm:       return BubuExpression.reading;
      case Mood.naughty:    return BubuExpression.yeah;
      case Mood.proud:      return BubuExpression.cheer;
      case Mood.curious:    return BubuExpression.thinking;
      case Mood.sleepy:     return BubuExpression.sleeping;
      case Mood.grievance:  return BubuExpression.shy;
      case Mood.milestone:  return BubuExpression.cheer;
      case Mood.eating:     return BubuExpression.eating;
      case Mood.laughing:   return BubuExpression.happy;
      case Mood.crying:     return BubuExpression.shy;
      case Mood.angry:      return BubuExpression.angry;
      case Mood.surprised:  return BubuExpression.surprised;
      case Mood.brave:      return BubuExpression.sport;
      case Mood.cuddly:     return BubuExpression.love;
      case Mood.sick:       return BubuExpression.drinking;
      case Mood.playful:    return BubuExpression.playing;
      case Mood.focused:    return BubuExpression.drawing;
      case Mood.shy:        return BubuExpression.shy;
      case Mood.love:       return BubuExpression.love;
      default:              return BubuExpression.happy;
    }
  }
}
