import { InsightIntentEntry } from '@ohos.app.ability.InsightIntentDecorator';
import InsightIntentEntryExecutor from '@ohos.app.ability.InsightIntentEntryExecutor';
import { insightIntent } from '@kit.AbilityKit';

@InsightIntentEntry({
  intentName: 'BubuRecordMoment',
  domain: 'FamilyMemory',
  intentVersion: '1.0.0',
  displayName: '记录布布这一刻',
  displayDescription: '把一句话带到布布时光机，确认后保存',
  icon: $r('app.media.app_icon'),
  llmDescription: '当用户明确要记录孩子布布刚发生的事情时调用，把用户要记录的原话完整放入 note。',
  keywords: ['记录布布', '记下这一刻', '宝宝今天', '成长记录'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND],
  parameters: {
    '$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'title': '布布成长记录参数',
    'description': '需要用户确认后写入家庭档案的一句话原文',
    'properties': {
      'note': {
        'type': 'string',
        'description': '用户要记录的完整原话，不改写、不补充未说出的事实',
        'minLength': 1,
        'maxLength': 2000
      }
    },
    'required': ['note'],
    'additionalProperties': false
  }
})
export default class RecordMomentIntent extends InsightIntentEntryExecutor<string> {
  public note: string = '';

  async onExecute(): Promise<insightIntent.IntentResult<string>> {
    const value = this.note.trim();
    if (value.length === 0) return { code: 1, result: 'missing_note' };
    AppStorage.setOrCreate('bubuIntentDraft', value);
    return { code: 0, result: 'ready_for_confirmation' };
  }
}
