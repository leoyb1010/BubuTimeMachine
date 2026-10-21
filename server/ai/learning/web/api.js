export class APIError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
export async function api(path, {method = 'GET', body, signal} = {}) {
  const response = await fetch(`/learning/api/${path}`, {
    method, credentials: 'same-origin', signal,
    headers: {'X-Bubu-Learning': '1', ...(body === undefined ? {} : {'Content-Type': 'application/json'})},
    ...(body === undefined ? {} : {body: JSON.stringify(body)})
  });
  if (!response.ok) {
    const messages = {401: '登录已过期，请重新登录。', 403: '这个账号没有操作权限，请联系家庭管理员。', 409: '内容已更新，旧确认已失效。请重新加载并核对当前版本。'};
    throw new APIError(response.status, messages[response.status] || `服务暂时没有完成请求（${response.status}），请稍后重试。`);
  }
  return response.status === 204 ? null : response.json();
}

/** Queue contains attempts only; never credentials or media. One queue per family user and child. */
export class AttemptQueue {
  constructor({userId, childId, storage = localStorage, send = body => api('attempts', {method:'POST',body})}) {
    this.key = `bubu-learning:attempts:v1:${encodeURIComponent(userId)}:${encodeURIComponent(childId)}`;
    this.storage = storage; this.send = send; this.childId = childId; this.pending = this.read(); this.flushing = null; this.blockedError = null;
  }
  read() {
    try { const list = JSON.parse(this.storage.getItem(this.key) || '[]'); return Array.isArray(list) ? list.filter(x => x.child_id === this.childId && typeof x.id === 'string') : []; }
    catch { return []; }
  }
  persist() { this.storage.setItem(this.key, JSON.stringify(this.pending)); }
  async add(attempt) {
    if (attempt.child_id !== this.childId) throw new Error('学习记录的孩子不匹配。');
    if (!this.pending.some(x => x.id === attempt.id)) this.pending.push(attempt);
    this.persist(); return this.flush();
  }
  async flush() {
    if (this.blockedError) return {pending:this.pending.length, error:this.blockedError};
    if (this.flushing) return this.flushing;
    this.flushing = this.flushPending();
    try { return await this.flushing; } finally { this.flushing = null; }
  }
  async flushPending() {
    while (this.pending.length) {
      const first = this.pending[0];
      try { await this.send(first); }
      catch (error) {
        // Permission/conflict errors require a fresh authenticated session, never an online retry loop.
        if ([401,403,409].includes(error.status)) this.blockedError = error;
        return {pending:this.pending.length, error};
      }
      this.pending.shift(); this.persist();
    }
    return {pending:0};
  }
}
