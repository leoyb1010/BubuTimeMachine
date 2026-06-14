import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// MARK: - 定位 / 反向地理编码（对照 iOS Services/Location/LocationService.swift）
// iOS 用 CoreLocation(CLLocationManager) 取一次定位 + MapKit(MKReverseGeocodingRequest) 反查地名。
// HarmonyOS 用 @kit.LocationKit geoLocationManager：
//   - getCurrentLocation 取一次当前坐标（对应 manager.requestLocation 一次性定位）；
//   - getAddressesFromLocation 反向地理编码取地名（对应 MKReverseGeocodingRequest）。
// 授权：iOS requestWhenInUseAuthorization → HarmonyOS abilityAccessCtrl 申请 APPROXIMATELY_LOCATION。

// iOS: struct CapturedLocation { latitude; longitude; name? }
export interface CapturedLocation {
  latitude: number;
  longitude: number;
  name?: string;
}

// iOS: private struct CapturedCoordinate { latitude; longitude }
interface CapturedCoordinate {
  latitude: number;
  longitude: number;
}

export class LocationService {
  static readonly shared = new LocationService();

  // iOS: private(set) var authorizationStatus —— 这里以最近一次申请结果缓存是否已授权。
  private authorized: boolean = false;

  private constructor() {}

  // iOS: var authorizationStatus（只读暴露）。HarmonyOS 无等价多态状态，以布尔表达「是否已授权」。
  get isAuthorized(): boolean {
    return this.authorized;
  }

  // iOS: func requestPermissionIfNeeded() async -> Bool
  // CLLocationManager.requestWhenInUseAuthorization → abilityAccessCtrl 申请 APPROXIMATELY_LOCATION。
  // 已授权直接返回 true；被拒返回 false。需由调用方传入 UIAbilityContext（对齐工程约定）。
  async requestPermissionIfNeeded(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const mgr = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION'];
      const result = await mgr.requestPermissionsFromUser(context, perms);
      const granted = result.authResults;
      this.authorized = granted.length > 0 && granted[0] === 0;
      return this.authorized;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `定位授权失败: ${JSON.stringify(e)}`);
      this.authorized = false;
      return false;
    }
  }

  // iOS: func currentPlacemark() async -> CapturedLocation?
  // 先确保授权 → 取一次坐标 → 反向地理编码补地名，组装 CapturedLocation。
  async currentPlacemark(context: common.UIAbilityContext): Promise<CapturedLocation | null> {
    const granted = await this.requestPermissionIfNeeded(context);
    if (!granted) return null;
    const coordinate = await this.requestOneShotLocation();
    if (!coordinate) return null;
    const name = await this.reverseGeocode(coordinate.latitude, coordinate.longitude);
    return {
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      name: name
    };
  }

  // iOS: private func requestOneShotLocation() async -> CapturedCoordinate?
  // CLLocationManager.requestLocation 一次性定位 → geoLocationManager.getCurrentLocation。
  private async requestOneShotLocation(): Promise<CapturedCoordinate | null> {
    try {
      // 对齐 iOS kCLLocationAccuracyHundredMeters：取低功耗、约百米精度的一次定位。
      const request: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
        locatingTimeoutMs: 10000
      };
      const location: geoLocationManager.Location =
        await geoLocationManager.getCurrentLocation(request);
      return { latitude: location.latitude, longitude: location.longitude };
    } catch (e) {
      // 定位失败（无信号 / 超时 / 权限关闭）：对齐 iOS didFailWithError，静默返回 nil。
      hilog.error(DOMAIN, 'Bubu', `单次定位失败: ${JSON.stringify(e)}`);
      return null;
    }
  }

  // iOS: private func reverseGeocode(_ location:) async -> String?
  // MapKit MKReverseGeocodingRequest(preferredLocale: zh_Hans_CN) → geoLocationManager.getAddressesFromLocation。
  // iOS 候选顺序：shortAddress → cityName → cityWithContext → name → fullAddress，取首个非空。
  // HarmonyOS GeoAddress 字段映射：placeName / subLocality / locality / administrativeArea / descriptions。
  private async reverseGeocode(lat: number, lon: number): Promise<string | undefined> {
    try {
      const req: geoLocationManager.ReverseGeoCodeRequest = {
        latitude: lat,
        longitude: lon,
        maxItems: 1,
        locale: 'zh'
      };
      const list: geoLocationManager.GeoAddress[] = await geoLocationManager.getAddressesFromLocation(req);
      if (list.length === 0) return undefined;
      const a = list[0];
      const candidates: Array<string | undefined> = [
        a.placeName,
        a.subLocality,
        a.locality,
        a.administrativeArea,
        a.descriptions
      ];
      for (const c of candidates) {
        if (c && c.trim().length > 0) {
          return c.trim();
        }
      }
      return undefined;
    } catch (e) {
      // 无网络 / 无权限 / API 不可用：静默跳过（对齐 iOS try? 降级）。
      hilog.error(DOMAIN, 'Bubu', `反向地理编码失败: ${JSON.stringify(e)}`);
      return undefined;
    }
  }
}
