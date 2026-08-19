import { InsightIntentEntry } from '@ohos.app.ability.InsightIntentDecorator';
import InsightIntentEntryExecutor from '@ohos.app.ability.InsightIntentEntryExecutor';
import { insightIntent } from '@kit.AbilityKit';

@InsightIntentEntry({
  intentName: 'BubuOpenApp',
  domain: 'FamilyMemory',
  intentVersion: '1.0.0',
  displayName: '打开布布时光机',
  displayDescription: '打开家庭成长记录',
  icon: $r('app.media.app_icon'),
  llmDescription: '当用户要查看、记录或回顾孩子布布的成长时，打开布布时光机。',
  keywords: ['打开布布时光机', '查看布布记录', '宝宝成长记录'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND]
})
export default class OpenBubuIntent extends InsightIntentEntryExecutor<string> {
  async onExecute(): Promise<insightIntent.IntentResult<string>> {
    return { code: 0, result: 'opened' };
  }
}
