import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { request } from '@kit.BasicServicesKit';
import type { common } from '@kit.AbilityKit';
import { ServerConfig } from './ServerConfig';
import { AuthResponse, UploadedFileResult } from './DTOs';

const DOMAIN = 0x0000;

// multipart 普通字段（name/value 对）。
interface FormField {
  name: string;
  value: string;
}

// MARK: - PocketBase 网络客户端（对照 iOS PocketBaseClient.swift）
// 复用你现有的自托管 PocketBase：密码鉴权 + collection 增量拉取/upsert + 文件上传 + 下载 + 软删除。
// 全部走 REST/JSON，与 iOS / 服务端协议一致。
// 幂等：以 localId 为去重键，upsert 先查后建/更新。
// 离线优先：所有失败都抛错，由 SyncEngine 决定保留本地、稍后重试。
export class APIClient {
  static readonly shared = new APIClient();
  private token: string = '';
  private currentUserId: string = '';
  private currentFamilyId: string = '';
  private fileToken: string = '';
  private fileTokenExpiresAt: number = 0;
  private appContext: common.BaseContext | null = null;

  private constructor() {}

  initialize(context: common.BaseContext): void {
    this.appContext = context;
  }

  private get baseURL(): string {
    return ServerConfig.shared.baseURLString.replace(/\/+$/, '');
  }

  static syncTimestampString(date: Date = new Date()): string {
    const year = date.getUTCFullYear();
    const month = APIClient.pad2(date.getUTCMonth() + 1);
    const day = APIClient.pad2(date.getUTCDate());
    const hour = APIClient.pad2(date.getUTCHours());
    const minute = APIClient.pad2(date.getUTCMinutes());
    const second = APIClient.pad2(date.getUTCSeconds());
    const ms = APIClient.pad3(date.getUTCMilliseconds());
    return `${year}-${month}-${day} ${hour}:${minute}:${second}.${ms}Z`;
  }

  private static normalizeSyncTimestamp(value: string): string {
    if (value.indexOf('T') < 0) return value;
    const parsed = new Date(value);
    const ms = parsed.getTime();
    return ms === ms ? APIClient.syncTimestampString(parsed) : value;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private static pad3(value: number): string {
    if (value < 10) return `00${value}`;
    if (value < 100) return `0${value}`;
    return `${value}`;
  }

  // MARK: 鉴权 ----------------------------------------------------------------

  // 密码登录，拿 token（PocketBase: /api/collections/users/auth-with-password）
  async authenticate(): Promise<boolean> {
    const cfg = ServerConfig.shared;
    if (!cfg.isConfigured) return false;
    const identities = APIClient.identityCandidates(cfg.accountEmail);
    let lastError: Object | null = null;
    for (const identity of identities) {
      try {
        const body = JSON.stringify({ identity: identity, password: cfg.accountPassword });
        const resp = await this.request('POST', '/api/collections/users/auth-with-password', body, false);
        const auth = JSON.parse(resp) as AuthResponse;
        this.token = auth.token;
        this.currentUserId = auth.record?.id ?? '';
        this.currentFamilyId = auth.record?.familyId ?? '';
        this.fileToken = '';
        this.fileTokenExpiresAt = 0;
        if (this.token.length > 0) {
          if (cfg.accountEmail !== identity) {
            cfg.accountEmail = identity;
            await cfg.persistServer();
          }
          return true;
        }
      } catch (e) {
        lastError = e;
      }
    }
    hilog.error(DOMAIN, 'Bubu', `登录失败: ${JSON.stringify(lastError)}`);
    this.token = '';
    this.currentUserId = '';
    this.currentFamilyId = '';
    this.fileToken = '';
    this.fileTokenExpiresAt = 0;
    return false;
  }

  private static identityCandidates(account: string): string[] {
    const raw = account.trim().toLowerCase();
    if (raw.length === 0) return [];
    const candidates: string[] = [];
    candidates.push(raw.indexOf('@') >= 0 ? raw : `${raw}@bubu.family`);
    if (raw.indexOf('@') < 0) candidates.push(raw);
    const at = raw.indexOf('@bubu.family');
    if (at > 0) candidates.push(raw.substring(0, at));
    const deduped: string[] = [];
    for (const item of candidates) {
      if (item.length > 0 && deduped.indexOf(item) < 0) deduped.push(item);
    }
    return deduped;
  }

  private authHeader(token: string): string {
    return token.startsWith('Bearer ') ? token : `Bearer ${token}`;
  }

  async authProbe(): Promise<string> {
    const cfg = ServerConfig.shared;
    if (!cfg.isConfigured) return '还没有登录服务器';
    try {
      const ok = await this.ping();
      if (!ok) return '服务器连接失败';
      const authed = await this.authenticate();
      return authed ? '账号验证成功' : '账号或密码验证失败';
    } catch (e) {
      return `服务器验证异常：${JSON.stringify(e)}`;
    }
  }

  // token 过期（401）时清掉缓存、重新登录一次。对照 iOS withAuthRetry 的鉴权重试部分。
  private async ensureToken(): Promise<string> {
    if (this.token.length > 0) return this.token;
    await this.authenticate();
    return this.token;
  }

  // 给同一家庭的 FastAPI 摄取接口复用 PocketBase 登录态；不向 UI 暴露、也不持久化 token。
  async accessToken(): Promise<string> {
    return await this.ensureToken();
  }

  // MARK: 通用 CRUD（幂等）----------------------------------------------------

  // 通用 upsert：localId 已存在则 PATCH，否则 POST（与 iOS upsert 同语义）
  async upsert(collection: string, localId: string, body: Record<string, Object>): Promise<Record<string, Object>> {
    const existing = await this.findByLocalId(collection, localId);
    body['localId'] = localId;
    body['clientUpdatedAt'] = APIClient.syncTimestampString();
    body = this.activeRecordBody(body, existing === null);
    if (existing) {
      const id = existing['id'] as string;
      const resp = await this.request('PATCH', `/api/collections/${collection}/records/${id}`, JSON.stringify(body), true);
      return JSON.parse(resp) as Record<string, Object>;
    } else {
      const resp = await this.request('POST', `/api/collections/${collection}/records`, JSON.stringify(body), true);
      return JSON.parse(resp) as Record<string, Object>;
    }
  }

  // 增量拉取统一使用 PocketBase 服务器字段 updated，避免设备时钟偏移造成永久漏拉。
  async fetchRecords(collection: string, sinceISO?: string): Promise<Record<string, Object>[]> {
    return await this.fetchRecordPages(collection, sinceISO, false);
  }

  // 跨设备删除通过软删除 tombstone 传播；返回 localId + updated 等完整原始字段。
  async fetchDeletedTombstones(collection: string, sinceISO?: string): Promise<Record<string, Object>[]> {
    return await this.fetchRecordPages(collection, sinceISO, true);
  }

  private async fetchRecordPages(collection: string, sinceISO: string | undefined,
                                 onlyDeleted: boolean): Promise<Record<string, Object>[]> {
    const all: Record<string, Object>[] = [];
    let page = 1;
    while (true) {
      let path = `/api/collections/${collection}/records?perPage=200&page=${page}&sort=updated`;
      const clauses: string[] = [];
      if (sinceISO) {
        const sinceFilter = APIClient.normalizeSyncTimestamp(sinceISO);
        clauses.push(`(updated>'${APIClient.filterEscape(sinceFilter)}')`);
      }
      if (onlyDeleted) clauses.push('(isDeleted=true)');
      if (clauses.length > 0) path += `&filter=${encodeURIComponent(clauses.join(' && '))}`;
      const resp = await this.request('GET', path, undefined, true);
      const parsed = JSON.parse(resp) as Record<string, Object>;
      const items = (parsed['items'] as Record<string, Object>[] | undefined) ?? [];
      for (const it of items) {
        if (!onlyDeleted && it['isDeleted'] === true) continue;
        all.push(it);
      }
      const totalPages = (parsed['totalPages'] as number | undefined) ?? 1;
      if (page >= totalPages || items.length === 0) break;
      page += 1;
    }
    return all;
  }

  // 删除一条记录：服务端保留 tombstone，不再物理删除。
  async deleteRecord(collection: string, id: string): Promise<void> {
    const body: Record<string, Object> = {
      'isDeleted': true,
      'deletedAt': new Date().toISOString(),
      'clientUpdatedAt': APIClient.syncTimestampString()
    };
    if (this.currentUserId.length > 0) body['deletedByUserId'] = this.currentUserId;
    await this.request('PATCH', `/api/collections/${collection}/records/${id}`, JSON.stringify(body), true);
  }

  // 按 localId 查 remoteId（对照 iOS findRecord）。供 SyncEngine 上传前定位记录。
  async findByLocalId(collection: string, localId: string): Promise<Record<string, Object> | null> {
    try {
      const filter = encodeURIComponent(`(localId='${APIClient.filterEscape(localId)}')`);
      const resp = await this.request('GET', `/api/collections/${collection}/records?filter=${filter}&perPage=1`, undefined, true);
      const parsed = JSON.parse(resp) as Record<string, Object>;
      const items = parsed['items'] as Record<string, Object>[] | undefined;
      return (items && items.length > 0) ? items[0] : null;
    } catch (e) {
      return null;
    }
  }

  // MARK: 文件 URL 构造（对照 iOS remoteFileURL）-----------------------------

  // 拼远端文件直链：api/files/<collection>/<recordId>/<fileName>。
  // fileName 必须用上传响应里的真实落盘名（PocketBase 会改名）。
  fileURL(collection: string, recordId: string, fileName: string): string {
    if (recordId.length === 0 || fileName.length === 0) return '';
    return `${this.baseURL}/api/files/${collection}/${recordId}/${fileName}`;
  }

  // MARK: multipart 文件上传（对照 iOS multipartUpload / uploadGenericFile）----

  // 上传一个文件到指定 collection 的记录（localId 已存在则 PATCH，否则 POST），
  // 携带可观察进度。fields 为同时写入的普通字段（含 localId/clientUpdatedAt）。
  // 返回 UploadedFileResult（recordId + 真实落盘文件名），调用方用 fileURL() 拼直链。
  // NOTE: HarmonyOS 的 request.uploadFile 仅支持 POST/PUT 且需 UIAbilityContext；
  //       为保持 PocketBase 幂等 upsert（POST 创建 / PATCH 覆盖）语义与无 Context 依赖，
  //       统一用自实现 http multipart（multipartViaHttp，对照 iOS 手写 multipart body）。
  //       简化：整文件读入内存一次发出，进度回调以 0/1 两点近似（家庭规模文件可接受）。
  async uploadFile(
    collection: string,
    localId: string,
    fields: Record<string, string>,
    fileField: string,
    filePath: string,
    fileName: string,
    onProgress?: (fraction: number) => void,
    extraFileField?: string,
    extraFilePath?: string,
    extraFileName?: string
  ): Promise<UploadedFileResult> {
    const tokenStr = await this.ensureToken();
    const existing = await this.findByLocalId(collection, localId);
    const isPatch = existing !== null;
    const recordId = isPatch ? (existing!['id'] as string) : '';
    const url = isPatch
      ? `${this.baseURL}/api/collections/${collection}/records/${recordId}`
      : `${this.baseURL}/api/collections/${collection}/records`;

    // 组装普通字段：补 localId + clientUpdatedAt（对照 iOS addSyncTimestamp）。
    fields['localId'] = localId;
    fields['clientUpdatedAt'] = APIClient.syncTimestampString();
    fields = this.activeRecordFields(fields, !isPatch);
    const formData: Array<FormField> = [];
    const keys = Object.keys(fields).sort();
    for (const k of keys) {
      formData.push({ name: k, value: fields[k] });
    }

    const header: Record<string, string> = {};
    if (tokenStr.length > 0) header['Authorization'] = this.authHeader(tokenStr);
    if (onProgress) onProgress(0);
    return await this.multipartViaHttp(
      isPatch ? 'PATCH' : 'POST', url, formData, fileField, filePath, fileName, header, onProgress,
      extraFileField, extraFilePath, extraFileName);
  }

  // 系统 multipart 直接从 filePath 流式读取，避免把大视频整段装进内存。
  private async multipartViaHttp(
    method: string,
    url: string,
    formData: Array<FormField>,
    fileField: string,
    filePath: string,
    fileName: string,
    header: Record<string, string>,
    onProgress?: (fraction: number) => void,
    extraFileField?: string,
    extraFilePath?: string,
    extraFileName?: string
  ): Promise<UploadedFileResult> {
    const path = filePath.replace(/^file:\/\//, '');
    const parts: http.MultiFormData[] = [];
    for (const d of formData) {
      parts.push({ name: d.name, contentType: 'text/plain', data: d.value });
    }
    parts.push({
      name: fileField,
      contentType: 'application/octet-stream',
      remoteFileName: fileName,
      filePath: path
    });
    if (extraFileField && extraFilePath && extraFileName) {
      parts.push({
        name: extraFileField,
        contentType: 'application/octet-stream',
        remoteFileName: extraFileName,
        filePath: extraFilePath.replace(/^file:\/\//, '')
      });
    }

    const req = http.createHttp();
    try {
      if (onProgress) {
        req.on('dataSendProgress', (info: http.DataSendProgressInfo): void => {
          if (info.totalSize > 0) onProgress(Math.min(1, info.sendSize / info.totalSize));
        });
      }
      const resp = await req.request(url, {
        method: method === 'PATCH' ? http.RequestMethod.PATCH : http.RequestMethod.POST,
        header: header,
        multiFormDataList: parts,
        connectTimeout: 30000,
        readTimeout: 300000
      });
      const code = resp.responseCode;
      if (code < 200 || code >= 300) throw new Error(`HTTP ${code}: ${resp.result}`);
      const obj = JSON.parse(resp.result as string) as Record<string, Object>;
      const id = obj['id'] as string | undefined;
      if (!id) throw new Error('上传响应异常');
      if (onProgress) onProgress(1);
      return {
        recordId: id,
        storedFileName: APIClient.storedFileName(obj, fileField, fileName),
        storedExtraFileName: extraFileField && extraFileName
          ? APIClient.storedFileName(obj, extraFileField, extraFileName) : undefined
      };
    } finally {
      req.destroy();
    }
  }

  // MARK: 文件下载（对照 iOS downloadFile(from:)）-----------------------------

  // 下载远端文件到本地 destPath，返回最终落盘路径。带 Bearer token。
  // 只走系统下载任务直接落盘；失败由 SyncEngine 保留本地状态并在下一轮重试。
  async downloadFile(remoteURL: string, destPath: string): Promise<string> {
    if (remoteURL.length === 0) throw new Error('文件地址不正确');
    const tokenStr = await this.ensureToken();
    const accessURL = await this.fileAccessURL(remoteURL);
    const header: Record<string, string> = {};
    if (tokenStr.length > 0) header['Authorization'] = this.authHeader(tokenStr);
    return await this.downloadFileViaTask(accessURL, destPath, header);
  }

  private async downloadFileViaTask(accessURL: string, destPath: string,
                                    header: Record<string, string>): Promise<string> {
    if (!this.appContext) throw new Error('缺少下载上下文');
    try {
      if (fileIo.accessSync(destPath)) fileIo.unlinkSync(destPath);
    } catch (e) {}
    const task = await request.downloadFile(this.appContext, {
      url: accessURL,
      filePath: destPath,
      header: header,
      enableMetered: true,
      enableRoaming: true,
      background: false,
      title: 'Bubu media'
    });
    return await new Promise<string>((resolve, reject) => {
      let finished = false;
      const complete = () => {
        if (finished) return;
        finished = true;
        try {
          const size = fileIo.statSync(destPath).size;
          if (size <= 0) {
            reject(new Error('下载文件为空'));
          } else {
            resolve(destPath);
          }
        } catch (e) {
          reject(new Error(`下载完成但文件不可读: ${APIClient.errorText(e)}`));
        }
      };
      const fail = (err: number) => {
        if (finished) return;
        finished = true;
        reject(new Error(`下载任务失败 ${err}`));
      };
      task.on('complete', complete);
      task.on('fail', fail);
      setTimeout(() => {
        if (finished) return;
        finished = true;
        reject(new Error('下载任务超时'));
      }, 300000);
    });
  }

  private static errorText(e: Object): string {
    if (e instanceof Error) return e.message;
    const text = JSON.stringify(e);
    return text.length > 0 ? text : '未知错误';
  }

  private async fileAccessURL(remoteURL: string): Promise<string> {
    const token = await this.ensureFileToken();
    if (token.length === 0) return remoteURL;
    const sep = remoteURL.indexOf('?') >= 0 ? '&' : '?';
    return `${remoteURL}${sep}token=${encodeURIComponent(token)}`;
  }

  private async ensureFileToken(): Promise<string> {
    const now = Date.now();
    if (this.fileToken.length > 0 && this.fileTokenExpiresAt > now) return this.fileToken;
    const resp = await this.request('POST', '/api/files/token', undefined, true);
    const parsed = JSON.parse(resp) as Record<string, Object>;
    const token = parsed['token'] as string | undefined;
    if (!token || token.length === 0) throw new Error('文件访问令牌响应异常');
    this.fileToken = token;
    this.fileTokenExpiresAt = now + 100000;
    return token;
  }

  // MARK: 连接测试（对照 iOS ping）-------------------------------------------

  async ping(): Promise<boolean> {
    const req = http.createHttp();
    try {
      const resp = await req.request(`${this.baseURL}/api/health`, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      const code = resp.responseCode;
      return code >= 200 && code < 300;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  // MARK: - 私有辅助 ----------------------------------------------------------

  private activeRecordBody(body: Record<string, Object>, defaultIsDeleted: boolean): Record<string, Object> {
    if (defaultIsDeleted && body['isDeleted'] === undefined) body['isDeleted'] = false;
    if (body['authorUserId'] === undefined && this.currentUserId.length > 0) {
      body['authorUserId'] = this.currentUserId;
    }
    if (body['familyId'] === undefined && this.currentFamilyId.length > 0) {
      body['familyId'] = this.currentFamilyId;
    }
    return body;
  }

  private activeRecordFields(fields: Record<string, string>, defaultIsDeleted: boolean): Record<string, string> {
    if (defaultIsDeleted && fields['isDeleted'] === undefined) fields['isDeleted'] = 'false';
    if (fields['authorUserId'] === undefined && this.currentUserId.length > 0) {
      fields['authorUserId'] = this.currentUserId;
    }
    if (fields['familyId'] === undefined && this.currentFamilyId.length > 0) {
      fields['familyId'] = this.currentFamilyId;
    }
    return fields;
  }

  // PocketBase filter 字符串里的单引号转义，杜绝注入面（对照 iOS filterEscape）。
  private static filterEscape(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  }

  // 上传响应里的真实落盘文件名（PocketBase 会清洗并追加随机后缀改名）。
  // 兼容 file 字段被配置为多文件（返回数组）的情况；解析不到回退本地名。
  private static storedFileName(obj: Record<string, Object>, fileField: string, fallback: string): string {
    const v = obj[fileField];
    if (typeof v === 'string' && v.length > 0) return v;
    if (Array.isArray(v) && v.length > 0 && typeof v[0] === 'string' && (v[0] as string).length > 0) {
      return v[0] as string;
    }
    return fallback;
  }

  private static uuid(): string {
    return util.generateRandomUUID(true);
  }

  // 底层请求
  private async request(method: string, path: string, body: string | undefined, auth: boolean): Promise<string> {
    const req = http.createHttp();
    try {
      const header: Record<string, string> = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
      if (auth && this.token.length > 0) header['Authorization'] = this.authHeader(this.token);
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
      if (code === 401 || code === 403) {
        // token 过期：清缓存，由上层下次 ensureToken 重登（对照 iOS unauthorized 处理）
        this.token = '';
        this.currentUserId = '';
        this.currentFamilyId = '';
        this.fileToken = '';
        this.fileTokenExpiresAt = 0;
        throw new Error(`HTTP ${code}: unauthorized`);
      }
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code}: ${resp.result}`);
      }
      return resp.result as string;
    } finally {
      req.destroy();
    }
  }
}
