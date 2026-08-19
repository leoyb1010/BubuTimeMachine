import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import type { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AgeCalculator } from '../models/AgeCalculator';
import { WidgetRefresher } from '../theme/WidgetRefresher';

interface CardData {
  name: string;
  ageText: string;
  daysText: string;
  recentTitle: string;
  recentNote: string;
  statsText: string;
  growthText: string;
  nextMilestone: string;
  recentPhotoUri: string;
}

// MARK: - 服务卡片提供方（对照 iOS WidgetKit 小组件）
// 桌面卡片显示布布年龄 + 来到世界第几天。数据从 App Group 等价的 Preferences 镜像读取。
export default class BubuFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY]?.toString() ?? '';
    WidgetRefresher.register(this.context, formId);
    return formBindingData.createFormBindingData(this.buildData());
  }

  onUpdateForm(formId: string): void {
    const data = formBindingData.createFormBindingData(this.buildData());
    formProvider.updateForm(formId, data);
  }

  onRemoveForm(formId: string): void {
    WidgetRefresher.unregister(this.context, formId);
  }

  // 卡片数据：从 Preferences 读布布生日（首页保存档案时写入），算年龄/天数。
  private buildData(): CardData {
    let name = '布布';
    let ageText = '记录布布的成长';
    let daysText = '';
    let recentTitle = '记录一个新瞬间';
    let recentNote = '打开 App，留住今天的成长';
    let statsText = '0 条时光 · 0 张照片';
    let growthText = '还没有成长测量';
    let nextMilestone = '记录新的第一次';
    let recentPhotoUri = '';
    try {
      const opt: preferences.Options = { name: 'bubu_widget' };
      const store = preferences.getPreferencesSync(this.context, opt);
      const birthday = store.getSync('birthday', 0) as number;
      name = store.getSync('childName', '布布') as string;
      if (birthday > 0) {
        ageText = AgeCalculator.ageDescription(birthday, Date.now());
        daysText = `来到世界第 ${AgeCalculator.daysSinceBirth(birthday)} 天`;
      }
      const entryCount = store.getSync('entryCount', 0) as number;
      const photoCount = store.getSync('photoCount', 0) as number;
      const achieved = store.getSync('achievedMilestones', 0) as number;
      const total = store.getSync('totalMilestones', 0) as number;
      const height = store.getSync('latestHeight', 0) as number;
      const weight = store.getSync('latestWeight', 0) as number;
      recentTitle = store.getSync('recentTitle', recentTitle) as string;
      recentNote = store.getSync('recentNote', recentNote) as string;
      nextMilestone = store.getSync('nextMilestone', nextMilestone) as string;
      recentPhotoUri = store.getSync('recentPhotoUri', '') as string;
      statsText = `${entryCount} 条时光 · ${photoCount} 张照片 · ${achieved}/${total} 里程碑`;
      if (height > 0 || weight > 0) {
        const parts: string[] = [];
        if (height > 0) parts.push(`${height} cm`);
        if (weight > 0) parts.push(`${weight} kg`);
        growthText = parts.join(' · ');
      }
    } catch (e) {
    }
    const data: CardData = {
      name, ageText, daysText, recentTitle, recentNote, statsText, growthText, nextMilestone, recentPhotoUri
    };
    return data;
  }
}
