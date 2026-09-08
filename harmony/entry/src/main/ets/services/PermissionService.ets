import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';

// API 26 手机端不读取旧返回数组；请求后用 accessToken 权威复查。
export class PermissionService {
  static async isGranted(permission: Permissions): Promise<boolean> {
    try {
    const manager = abilityAccessCtrl.createAtManager();
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const tokenId = info.appInfo.accessTokenId;
    return await manager.checkAccessToken(tokenId, permission)
      === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      } catch (error) {
      hilog.error(0x0000, 'Bubu', 'PermissionService.isGranted 操作失败，已安全中止');
      throw error as Error;
    }
  }

  static async request(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
    try {
    if (await PermissionService.isGranted(permission)) return true;
    const manager = abilityAccessCtrl.createAtManager();
    await manager.requestPermissionsFromUser(context, [permission]);
    return await PermissionService.isGranted(permission);
      } catch (error) {
      hilog.error(0x0000, 'Bubu', 'PermissionService.request 操作失败，已安全中止');
      throw error as Error;
    }
  }
}
