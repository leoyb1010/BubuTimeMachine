// MARK: - 小组件刷新（对照 iOS DesignSystem/WidgetRefresher.swift）
// 主 App 改了会显示在桌面卡片上的数据后，通知卡片框架重载，否则卡片只会按系统低频节奏更新。
// iOS 用 WidgetCenter.reloadTimelines；HarmonyOS 用 @kit.FormKit formProvider。
// NOTE: HarmonyOS 主动刷新需持有已添加卡片的 formId（系统不提供「刷新全部」的等价 API）。
//       这里把卡片的 formId 持久化清单交给 BubuFormAbility 维护；reload 遍历清单逐个 updateForm。
//       若拿不到 formId（无已添加卡片），静默跳过——与 iOS 行为一致（无卡片则无操作）。

import { formProvider, formBindingData } from '@kit.FormKit';

export class WidgetRefresher {
  /// 已添加卡片的 formId 清单（由 BubuFormAbility.onAddForm/onRemoveForm 维护）。
  private static formIds: string[] = [];

  static register(formId: string): void {
    if (!WidgetRefresher.formIds.includes(formId)) {
      WidgetRefresher.formIds.push(formId);
    }
  }

  static unregister(formId: string): void {
    WidgetRefresher.formIds = WidgetRefresher.formIds.filter(id => id !== formId);
  }

  /// 触发所有已添加卡片重载（对照 iOS reloadAllTimelines）。
  static reload(): void {
    for (const id of WidgetRefresher.formIds) {
      try {
        // 传空数据触发卡片重新拉取（卡片侧 onUpdateForm 会重算）。
        const empty = formBindingData.createFormBindingData({});
        formProvider.updateForm(id, empty).catch(() => {});
      } catch (e) {
        // 刷新失败静默：卡片非关键路径。
      }
    }
  }
}
