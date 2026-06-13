import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import type { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AgeCalculator } from '../models/AgeCalculator';

interface CardData {
  name: string;
  ageText: string;
  daysText: string;
}

// MARK: - 服务卡片提供方（对照 iOS WidgetKit 小组件）
// 桌面卡片显示布布年龄 + 来到世界第几天。数据从 App Group 等价的 Preferences 镜像读取。
export default class BubuFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(this.buildData());
  }

  onUpdateForm(formId: string): void {
    const data = formBindingData.createFormBindingData(this.buildData());
    formProvider.updateForm(formId, data);
  }

  onRemoveForm(formId: string): void {}

  // 卡片数据：从 Preferences 读布布生日（首页保存档案时写入），算年龄/天数。
  private buildData(): CardData {
    let name = '布布';
    let ageText = '记录布布的成长';
    let daysText = '';
    try {
      const opt: preferences.Options = { name: 'bubu_widget' };
      const store = preferences.getPreferencesSync(this.context, opt);
      const birthday = store.getSync('birthday', 0) as number;
      name = store.getSync('childName', '布布') as string;
      if (birthday > 0) {
        ageText = AgeCalculator.ageDescription(birthday, Date.now());
        daysText = `来到世界第 ${AgeCalculator.daysSinceBirth(birthday)} 天`;
      }
    } catch (e) {
    }
    const data: CardData = { name: name, ageText: ageText, daysText: daysText };
    return data;
  }
}
