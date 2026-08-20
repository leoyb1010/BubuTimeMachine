import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';

// API 26 手机端不读取旧返回数组；请求后用 accessToken 权威复查。
export class PermissionService {
  static async isGranted(permission: Permissions): Promise<boolean> {
    const manager = abilityAccessCtrl.createAtManager();
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const tokenId = info.appInfo.accessTokenId;
    return await manager.checkAccessToken(tokenId, permission)
      === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  static async request(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
    if (await PermissionService.isGranted(permission)) return true;
    const manager = abilityAccessCtrl.createAtManager();
    await manager.requestPermissionsFromUser(context, [permission]);
    return await PermissionService.isGranted(permission);
  }
}
