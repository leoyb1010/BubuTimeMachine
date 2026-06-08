import SwiftUI

// MARK: - 布布表情贴纸
/// 一套与 logo 同系的布布插画（由「布布各种表情状态」合集拆分而来）。
/// 每个表情都是独立 asset，按语义在产品里替换合适的位置/心情。
enum BubuExpression: String, CaseIterable {
    case eating = "BubuEating"          // 吃饭
    case drinking = "BubuDrinking"      // 喝水
    case sleeping = "BubuSleeping"      // 睡觉
    case playing = "BubuPlaying"        // 玩耍
    case sport = "BubuSport"            // 运动
    case reading = "BubuReading"        // 读书
    case drawing = "BubuDrawing"        // 画画
    case happy = "BubuHappy"            // 开心
    case surprised = "BubuSurprised"    // 惊讶
    case angry = "BubuAngry"            // 生气
    case shy = "BubuShy"                // 害羞
    case thinking = "BubuThinking"      // 思考
    case cheer = "BubuCheer"            // 加油
    case bye = "BubuBye"                // 拜拜
    case love = "BubuLove"              // 比心
    case travel = "BubuTravel"          // 旅行
    case bath = "BubuBath"              // 洗澡
    case music = "BubuMusic"            // 听音乐
    case tv = "BubuTV"                  // 看电视
    case yeah = "BubuYeah"              // 耶

    var assetName: String { rawValue }

    /// 心情 → 表情贴纸（找不到贴切的就回落到开心/比心）。
    static func forMood(_ mood: Mood?) -> BubuExpression {
        switch mood {
        case .happy:      return .happy
        case .calm:       return .reading
        case .naughty:    return .yeah
        case .proud:      return .cheer
        case .curious:    return .thinking
        case .sleepy:     return .sleeping
        case .grievance:  return .shy
        case .milestone:  return .cheer
        case .eating:     return .eating
        case .laughing:   return .happy
        case .crying:     return .shy
        case .angry:      return .angry
        case .surprised:  return .surprised
        case .brave:      return .sport
        case .cuddly:     return .love
        case .sick:       return .drinking
        case .playful:    return .playing
        case .focused:    return .drawing
        case .shy:        return .shy
        case .love:       return .love
        case .none:       return .happy
        }
    }
}
