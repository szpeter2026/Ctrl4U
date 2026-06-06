/**
 * BLE 周边扫描（对齐 YeDall DeviceListContent + HarmonyOS 官方 ConnectivityKit）。
 * 不使用已废弃的 @ohos.bluetoothManager。
 */
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { access, ble } from '@kit.ConnectivityKit';

export interface BleFoundDevice {
  deviceId: string;
  deviceName: string;
  rssi: number;
}

let scanActive: boolean = false;
let deviceCallback: ((d: BleFoundDevice) => void) | undefined = undefined;

function handleBleDeviceFind(data: Array<ble.ScanResult>): void {
  if (!scanActive || deviceCallback === undefined) {
    return;
  }
  for (const result of data) {
    const name: string = result.deviceName || '未知设备';
    const id: string = result.deviceId || '';
    const rssi: number = result.rssi ?? 0;
    if (id.length > 0) {
      deviceCallback({ deviceId: id, deviceName: name, rssi: rssi });
    }
  }
}

/** 蓝牙是否处于可扫描状态 */
export function isBluetoothAdapterOn(): boolean {
  try {
    const state: access.BluetoothState = access.getState();
    return state === access.BluetoothState.STATE_ON || state === access.BluetoothState.STATE_BLE_ON;
  } catch (_e) {
    return false;
  }
}

/** 申请扫描所需权限（与 module.json5 声明一致） */
export async function requestBleScanPermissions(ctx: common.UIAbilityContext): Promise<boolean> {
  const perms: Permissions[] = [
    'ohos.permission.ACCESS_BLUETOOTH',
    'ohos.permission.DISCOVER_BLUETOOTH'
  ];
  try {
    const at = abilityAccessCtrl.createAtManager();
    const r = await at.requestPermissionsFromUser(ctx, perms);
    return r.authResults.length >= 2 && r.authResults[0] === 0 && r.authResults[1] === 0;
  } catch (_e) {
    return false;
  }
}

/**
 * 开始 BLE 扫描。回调每发现新设备 id 即触发一次（由调用方去重或展示）。
 * @returns false 表示未启动（蓝牙关 / 已在扫）
 */
export function startBleDeviceScan(onDevice: (d: BleFoundDevice) => void): boolean {
  if (scanActive) {
    return false;
  }
  if (!isBluetoothAdapterOn()) {
    return false;
  }
  scanActive = true;
  deviceCallback = onDevice;
  try {
    ble.on('BLEDeviceFind', handleBleDeviceFind);
    const scanOptions: ble.ScanOptions = {
      interval: 500,
      dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
      matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
    };
    ble.startBLEScan(null, scanOptions);
    return true;
  } catch (_e) {
    scanActive = false;
    deviceCallback = undefined;
    return false;
  }
}

/** 停止扫描并移除监听 */
export function stopBleDeviceScan(): void {
  if (!scanActive) {
    return;
  }
  scanActive = false;
  deviceCallback = undefined;
  try {
    ble.off('BLEDeviceFind');
    ble.stopBLEScan();
  } catch (_e) {
    // best-effort
  }
}
