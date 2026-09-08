// (updated, id) 游标：同一毫秒的批量写入与翻页期间的编辑都不能造成漏拉。
// ponytail: 单轮约十万条封顶；接近此规模时改为逐页落盘和断点续拉。
export async function collectSyncPages(
  since: string | undefined,
  fetch: (updated: string | undefined, afterID: string | undefined) => Promise<Record<string, Object>[]>,
  maxRounds: number = 500
): Promise<Record<string, Object>[]> {
  const all: Record<string, Object>[] = [];
  const positions: Map<string, number> = new Map();
  let cursor = since;
  let cursorID: string | undefined = undefined;
  for (let round = 0; round < maxRounds; round++) {
    const items = await fetch(cursor, cursorID);
    if (items.length === 0) return all;
    for (const item of items) {
      const id = item['id'];
      const updated = item['updated'];
      if (typeof id !== 'string' || id.length === 0 || typeof updated !== 'string' ||
          Number.isNaN(Date.parse(updated))) {
        throw new Error('同步记录缺少有效的 id 或 updated，已保留原游标');
      }
      if (cursor !== undefined) {
        const before = Date.parse(cursor);
        const after = Date.parse(updated);
        if (!(after > before || (after === before && cursorID !== undefined && id > cursorID))) {
          throw new Error('同步分页顺序异常，已保留原游标');
        }
      }
      const position = positions.get(id);
      if (position !== undefined) all[position] = item;
      else { positions.set(id, all.length); all.push(item); }
      cursor = updated;
      cursorID = id;
    }
    if (items.length < 200) return all;
  }
  throw new Error('同步分页超过安全上限，请稍后重试');
}
