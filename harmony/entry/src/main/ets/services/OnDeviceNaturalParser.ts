export interface OfflineNaturalRequest {
  text: string;
  referenceDate: string;
}

// HarmonyOS 没有可依赖的全量系统端上大模型时，离线只保留原文，不猜健康数值或类别。
export function parseNaturalCaptureOfflineWire(request: OfflineNaturalRequest): Record<string, Object> {
  const text = request.text.trim();
  return {
    confidence: 1,
    warnings: ['offline_plain_text'],
    items: [{
      id: `offline-${Date.now()}`,
      domain: 'timeline',
      action: 'create',
      title: text.length > 12 ? `${text.substring(0, 12)}…` : text,
      note: text,
      date: request.referenceDate,
      fields: {},
      tags: [],
      confidence: 1,
      needs_confirmation: false,
      source_text: text
    }]
  };
}
