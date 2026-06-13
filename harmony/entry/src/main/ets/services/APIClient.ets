import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerConfig } from './ServerConfig';
import { AuthResponse } from './DTOs';

const DOMAIN = 0x0000;

// MARK: - PocketBase 网络客户端（对照 iOS PocketBaseClient）
// 复用你现有的自托管 PocketBase：密码鉴权 + collection 增量拉取/upsert + 文件上传。
// 全部走 REST/JSON，与 iOS / 服务端协议一致。
export class APIClient {
  static readonly shared = new APIClient();
  private token: string = '';

  private constructor() {}

  private get baseURL(): string {
    return ServerConfig.shared.baseURLString.replace(/\/+$/, '');
  }

  // 密码登录，拿 token（PocketBase: /api/collections/users/auth-with-password）
  async authenticate(): Promise<boolean> {
    const cfg = ServerConfig.shared;
    if (!cfg.isConfigured) return false;
    try {
      const body = JSON.stringify({ identity: cfg.accountEmail, password: cfg.accountPassword });
      const resp = await this.request('POST', '/api/collections/users/auth-with-password', body, false);
      const auth = JSON.parse(resp) as AuthResponse;
      this.token = auth.token;
      return this.token.length > 0;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `登录失败: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 通用 upsert：localId 已存在则 PATCH，否则 POST（与 iOS upsert 同语义）
  async upsert(collection: string, localId: string, body: Record<string, Object>): Promise<Record<string, Object>> {
    const existing = await this.findByLocalId(collection, localId);
    body['localId'] = localId;
    body['clientUpdatedAt'] = new Date().toISOString();
    if (existing) {
      const id = existing['id'] as string;
      const resp = await this.request('PATCH', `/api/collections/${collection}/records/${id}`, JSON.stringify(body), true);
      return JSON.parse(resp) as Record<string, Object>;
    } else {
      const resp = await this.request('POST', `/api/collections/${collection}/records`, JSON.stringify(body), true);
      return JSON.parse(resp) as Record<string, Object>;
    }
  }

  // 增量拉取：since 用 clientUpdatedAt 游标（对齐服务端迁移 add_client_updated_at）
  async fetchRecords(collection: string, sinceISO?: string): Promise<Record<string, Object>[]> {
    let path = `/api/collections/${collection}/records?perPage=500&sort=clientUpdatedAt`;
    if (sinceISO) {
      const filter = encodeURIComponent(`clientUpdatedAt > "${sinceISO}"`);
      path += `&filter=${filter}`;
    }
    const resp = await this.request('GET', path, undefined, true);
    const parsed = JSON.parse(resp) as Record<string, Object>;
    const items = parsed['items'] as Record<string, Object>[] | undefined;
    return items ?? [];
  }

  private async findByLocalId(collection: string, localId: string): Promise<Record<string, Object> | null> {
    try {
      const filter = encodeURIComponent(`localId = "${localId}"`);
      const resp = await this.request('GET', `/api/collections/${collection}/records?filter=${filter}&perPage=1`, undefined, true);
      const parsed = JSON.parse(resp) as Record<string, Object>;
      const items = parsed['items'] as Record<string, Object>[] | undefined;
      return (items && items.length > 0) ? items[0] : null;
    } catch (e) {
      return null;
    }
  }

  // 底层请求
  private async request(method: string, path: string, body: string | undefined, auth: boolean): Promise<string> {
    const req = http.createHttp();
    try {
      const header: Record<string, string> = { 'Content-Type': 'application/json' };
      if (auth && this.token.length > 0) header['Authorization'] = this.token;
      const methodEnum = method === 'POST' ? http.RequestMethod.POST
        : method === 'PATCH' ? http.RequestMethod.PATCH
        : method === 'DELETE' ? http.RequestMethod.DELETE
        : http.RequestMethod.GET;
      const resp = await req.request(this.baseURL + path, {
        method: methodEnum,
        header: header,
        extraData: body,
        connectTimeout: 30000,
        readTimeout: 90000
      });
      const code = resp.responseCode;
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code}: ${resp.result}`);
      }
      return resp.result as string;
    } finally {
      req.destroy();
    }
  }
}
