import type { QAContextRecord } from './AIArtifacts.ts';

export interface QAMemoryFact {
  id: string;
  happenedAt: number;
  dateText: string;
  ageText: string;
  text: string;
}

export function retrieveQAContexts(question: string, facts: QAMemoryFact[],
                                   now: number = Date.now(), limit: number = 12): QAContextRecord[] {
  const lower = question.trim().toLowerCase();
  let picked: QAMemoryFact[] = [];
  const yearsAgo = lower.includes('前年今天') || lower.includes('前年的今天') ? 2
    : (lower.includes('去年今天') || lower.includes('去年的今天') ? 1 : 0);
  if (yearsAgo > 0) {
    const target = new Date(now);
    target.setFullYear(target.getFullYear() - yearsAgo);
    const radius = 3 * 24 * 60 * 60 * 1000;
    picked = facts.filter((fact: QAMemoryFact): boolean => Math.abs(fact.happenedAt - target.getTime()) <= radius)
      .sort((left: QAMemoryFact, right: QAMemoryFact): number => right.happenedAt - left.happenedAt);
  }

  const keywords = questionKeywords(lower);
  const scored = facts.map((fact: QAMemoryFact): { fact: QAMemoryFact; score: number } => {
    const text = fact.text.toLowerCase();
    let score = 0;
    for (const keyword of keywords) if (text.includes(keyword)) score += keyword.length;
    return { fact, score };
  }).filter((item: { fact: QAMemoryFact; score: number }): boolean => item.score > 0)
    .sort((left, right): number => right.score === left.score
      ? right.fact.happenedAt - left.fact.happenedAt : right.score - left.score);
  for (const item of scored) {
    if (!picked.some((fact: QAMemoryFact): boolean => fact.id === item.fact.id)) picked.push(item.fact);
  }

  if (picked.length < 6) {
    const recent = facts.slice().sort((left: QAMemoryFact, right: QAMemoryFact): number => {
      return right.happenedAt - left.happenedAt;
    });
    for (const fact of recent) {
      if (!picked.some((value: QAMemoryFact): boolean => value.id === fact.id)) picked.push(fact);
      if (picked.length >= 6) break;
    }
  }
  return picked.slice(0, limit).map((fact: QAMemoryFact): QAContextRecord => ({
    id: fact.id,
    dateText: fact.dateText,
    ageText: fact.ageText,
    text: fact.text.substring(0, 200)
  }));
}

function questionKeywords(question: string): string[] {
  const stop = ['什么', '时候', '怎么', '最近', '布布', '去年今天', '前年今天', '是哪天'];
  let cleaned = question;
  for (const word of stop) cleaned = cleaned.replaceAll(word, ' ');
  const keywords = cleaned.split(/[\s，。？！、]+/).filter((part: string): boolean => part.length >= 2);
  const compact = cleaned.replace(/[\s，。？！、]/g, '');
  for (let index = 0; index + 1 < compact.length; index += 1) {
    const pair = compact.substring(index, index + 2);
    if (!keywords.includes(pair)) keywords.push(pair);
  }
  return keywords;
}
