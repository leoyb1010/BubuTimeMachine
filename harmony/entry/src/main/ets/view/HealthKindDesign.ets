// MARK: - HealthKindDesign（对照 iOS Features/Health/HealthKindDesign.swift）
// 每个健康记录类型的视觉设计：英雄标题/副标题、emoji 图标、快捷数值、单位、标签预设。
// iOS 用 BubuExpression 吉祥物枚举 + SF Symbols；ArkUI 用 emoji 字符串近似。

import { HealthRecordKind } from '../models/Enums';

// 对照 iOS struct HealthKindDesign。
export interface HealthKindDesign {
  heroTitle: string;
  heroSubtitle: string;
  iconEmoji: string;     // 对照 iOS 的 SF Symbol icon，鸿蒙用 emoji 近似
  mascotEmoji: string;   // 对照 iOS BubuExpression 吉祥物表情
  quickAmounts: number[];
  unit: string | undefined;
  chips: string[];
}

// 对照 iOS extension HealthRecordKind { var design }。
export function healthKindDesign(kind: HealthRecordKind): HealthKindDesign {
  switch (kind) {
    case HealthRecordKind.meal:
      return {
        heroTitle: '今天吃了什么',
        heroSubtitle: '记录正餐、主食、蛋白质和吃完反应。',
        iconEmoji: '🍴',
        mascotEmoji: '😋',
        quickAmounts: [],
        unit: undefined,
        chips: ['米粥', '面条', '鸡蛋', '肉泥', '蔬菜', '水果']
      };
    case HealthRecordKind.snack:
      return {
        heroTitle: '小零食时间',
        heroSubtitle: '用小卡片记录水果、酸奶、磨牙棒和尝新反应。',
        iconEmoji: '🍿',
        mascotEmoji: '🧸',
        quickAmounts: [],
        unit: undefined,
        chips: ['水果', '酸奶', '奶酪', '小饼干', '磨牙棒', '尝新']
      };
    case HealthRecordKind.supplement:
      return {
        heroTitle: '营养补充',
        heroSubtitle: '维 D、钙、益生菌等，适合做连续记录。',
        iconEmoji: '💊',
        mascotEmoji: '🤔',
        quickAmounts: [],
        unit: undefined,
        chips: ['维D', '钙', '铁', '益生菌', 'DHA']
      };
    case HealthRecordKind.water:
      return {
        heroTitle: '喝水小水壶',
        heroSubtitle: '快速点一下，记录今天喝了多少水。',
        iconEmoji: '💧',
        mascotEmoji: '🥤',
        quickAmounts: [30, 60, 90, 120, 150, 200],
        unit: 'ml',
        chips: ['温水', '吸管杯', '水壶', '主动喝', '提醒后喝']
      };
    case HealthRecordKind.sleep:
      return {
        heroTitle: '睡眠小月亮',
        heroSubtitle: '记录入睡、醒来、午睡和夜醒。',
        iconEmoji: '🌙',
        mascotEmoji: '😴',
        quickAmounts: [],
        unit: undefined,
        chips: ['午睡', '夜睡', '夜醒', '自主入睡', '哄睡']
      };
    case HealthRecordKind.symptom:
      return {
        heroTitle: '不舒服观察',
        heroSubtitle: '记录症状、体温、严重程度和是否需要继续观察。',
        iconEmoji: '🩹',
        mascotEmoji: '🤒',
        quickAmounts: [],
        unit: undefined,
        chips: ['流鼻涕', '咳嗽', '发热', '腹泻', '皮疹', '肚子疼']
      };
    case HealthRecordKind.checkup:
      return {
        heroTitle: '体检护理',
        heroSubtitle: '记录身高、体重、疫苗、牙齿和医生建议。',
        iconEmoji: '🩺',
        mascotEmoji: '💗',
        quickAmounts: [],
        unit: undefined,
        chips: ['身高', '体重', '疫苗', '牙齿', '体检', '医生建议']
      };
    default:
      return {
        heroTitle: '健康记录',
        heroSubtitle: '',
        iconEmoji: '📝',
        mascotEmoji: '🍼',
        quickAmounts: [],
        unit: undefined,
        chips: []
      };
  }
}
