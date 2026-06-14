import { http } from '@kit.NetworkKit';
import { FamilyRole } from '../models/Enums';
import { ServerConfig } from './ServerConfig';

export class AccountService {
  static readonly familyCode: string = 'YUANCHENXI';
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
    if (u.length === 0 || password.length < 6) {
      throw new Error('用户名至少 1 位、密码至少 6 位');
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

  async register(username: string, password: string, familyCode: string, role: FamilyRole): Promise<void> {
    if (familyCode.trim().toUpperCase() !== AccountService.familyCode) {
      throw new Error('家庭码不对，问问家里人正确的家庭码');
    }
    const u = username.trim();
    if (u.length === 0 || password.length < 6) {
      throw new Error('用户名至少 1 位、密码至少 6 位');
    }
    const e = AccountService.emailFor(u);

    const body = JSON.stringify({
      email: e,
      password: password,
      passwordConfirm: password,
      name: role
    });
    try {
      await this.request('POST', '/api/collections/users/records', body);
    } catch (e) {
      // 与 iOS 一致：用户名已存在时，如果密码正确，直接当登录成功。
      try {
        const identity = await this.firstWorkingIdentity(u, password);
        await this.persist(identity, password, role);
        return;
      } catch (authError) {
        throw new Error('这个用户名已被注册，但密码不对。换个用户名，或用正确密码去「登录」。');
      }
    }
    await this.authWithPassword(e, password);
    await this.persist(e, password, role);
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
