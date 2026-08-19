import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';

// API 26 手机端不读取旧返回数组；请求后用 accessToken 权威复查。
export class PermissionService {
  static async request(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
    const manager = abilityAccessCtrl.createAtManager();
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const tokenId = info.appInfo.accessTokenId;
    if (await manager.checkAccessToken(tokenId, permission) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true;
    }
    await manager.requestPermissionsFromUser(context, [permission]);
    return await manager.checkAccessToken(tokenId, permission) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }
}
