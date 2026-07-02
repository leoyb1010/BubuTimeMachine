import { http } from '@kit.NetworkKit';
import { FamilyRole } from '../models/Enums';
import { ServerConfig } from './ServerConfig';

export class AccountService {
  private static readonly emailDomain: string = 'bubu.family';

  static emailFor(username: string): string {
    const u = username.trim().toLowerCase();
    return u.indexOf('@') >= 0 ? u : `${u}@${AccountService.emailDomain}`;
  }

  static usernameFor(email: string): string {
    const e = email.trim().toLowerCase();
    const suffix = `@${AccountService.emailDomain}`;
    return e.endsWith(suffix) ? e.slice(0, e.length - suffix.length) : email;
  }

  private static identityCandidates(username: string): string[] {
    const raw = username.trim().toLowerCase();
    const email = AccountService.emailFor(raw);
    const candidates: string[] = [email];
    // 兼容服务器里已经存在的原始用户名账号，例如 identity = "yuanbo"。
    if (raw.length > 0 && raw !== email) {
      candidates.push(raw);
    }
    return candidates;
  }

  async login(username: string, password: string, role: FamilyRole): Promise<void> {
    const u = username.trim();
    if (ServerConfig.shared.baseURLString.trim().length === 0 || u.length === 0 || password.length < 8) {
      throw new Error('请先填写服务器地址、用户名和至少 8 位密码');
    }
    let lastError: Error | null = null;
    for (const identity of AccountService.identityCandidates(u)) {
      try {
        await this.authWithPassword(identity, password);
        await this.persist(identity, password, role);
        return;
      } catch (e) {
        lastError = e instanceof Error ? e : new Error('登录失败，请稍后再试');
      }
    }
    throw lastError ?? new Error('登录失败，请确认用户名、密码和服务器地址');
  }

  async register(_username: string, _password: string, _familyCode: string, _role: FamilyRole): Promise<void> {
    throw new Error('家里服务器已关闭公开注册。请先在 PocketBase 后台创建账号，再用「登录」进入。');
  }

  async logout(): Promise<void> {
    await ServerConfig.shared.logout();
  }

  private async persist(email: string, password: string, role: FamilyRole): Promise<void> {
    const cfg = ServerConfig.shared;
    cfg.accountEmail = email;
    cfg.accountPassword = password;
    await cfg.setRole(role);
    await cfg.persistServer();
  }

  private async authWithPassword(identity: string, password: string): Promise<string> {
    const body = JSON.stringify({ identity: identity, password: password });
    const resp = await this.request('POST', '/api/collections/users/auth-with-password', body);
    const obj = JSON.parse(resp) as Record<string, Object>;
    const token = obj['token'] as string | undefined;
    if (!token || token.length === 0) {
      throw new Error('登录响应异常');
    }
    return token;
  }

  private async firstWorkingIdentity(username: string, password: string): Promise<string> {
    let lastError: Error | null = null;
    for (const identity of AccountService.identityCandidates(username)) {
      try {
        await this.authWithPassword(identity, password);
        return identity;
      } catch (e) {
        lastError = e instanceof Error ? e : new Error('登录失败');
      }
    }
    throw lastError ?? new Error('登录失败');
  }

  private baseURL(): string {
    const configured = ServerConfig.shared.baseURLString.trim();
    const base = configured.length > 0 ? configured : ServerConfig.defaultBaseURL;
    if (base.length === 0) throw new Error('请先填写服务器地址');
    return base.replace(/\/+$/, '');
  }

  private async request(method: string, path: string, body: string): Promise<string> {
    const req = http.createHttp();
    try {
      const methodEnum = method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET;
      const resp = await req.request(this.baseURL() + path, {
        method: methodEnum,
        header: { 'Content-Type': 'application/json' } as Record<string, string>,
        extraData: body,
        connectTimeout: 30000,
        readTimeout: 90000
      });
      const code = resp.responseCode;
      if (code < 200 || code >= 300) {
        throw new Error(this.errorMessage(code, resp.result as string, path));
      }
      return resp.result as string;
    } finally {
      req.destroy();
    }
  }

  private errorMessage(code: number, body: string, path: string): string {
    if (code === 400 && path.indexOf('/users/records') >= 0) {
      return '这个用户名可能已注册，换一个或直接登录';
    }
    if (code === 400 && path.indexOf('/auth-with-password') >= 0) {
      return '用户名或密码不对；如果你在 iOS 用的是 yuanbo，也可以直接填 yuanbo 再试';
    }
    try {
      const obj = JSON.parse(body) as Record<string, Object>;
      const message = obj['message'] as string | undefined;
      if (message && message.length > 0) return message;
    } catch (e) {}
    return `请求失败（${code}）`;
  }
}
