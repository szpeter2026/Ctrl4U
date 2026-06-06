import { abilityAccessCtrl, common, Want } from '@kit.AbilityKit'
import { bundleManager } from '@kit.AbilityKit'
import { BusinessError, Callback } from '@kit.BasicServicesKit'
import { buffer } from '@kit.ArkTS'
import { manager, scan, ssap, constant } from '@kit.NearLinkKit';

export function getSleState(): manager.NearlinkState {
    let sleState = manager.NearlinkState.STATE_OFF
    try {
        sleState = manager.getState()
        console.debug(`get state sle state :${sleState}`)
    } catch (err) {
        // 无权限
        console.error(`getSleState errCode: ${err.code}, errMessage: ${err.message}`)
    }
    return sleState
}

export async function getGrantStatus(): Promise<abilityAccessCtrl.GrantStatus> {
    // 获取应用程序的accessTokenID
    let tokenId: number = 0
    let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED

    try {
        tokenId =
            (await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)).appInfo.accessTokenId
        // 校验应用是否被授予权限
        grantStatus =
            await abilityAccessCtrl.createAtManager().checkAccessToken(tokenId, 'ohos.permission.ACCESS_NEARLINK')
    } catch (err) {
        console.error(`getGrantStatus errCode: ${err.code}, errMessage: ${err.message}`);
    }
    return grantStatus
}

export async function jumpToSetting(context: common.UIAbilityContext) {
    let bundleName =
        (await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)).appInfo.name
    console.log(`bundle name: ${bundleName}`)
    let wantInfo: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: {
            pushParams: bundleName // 应用的 bundleName
        }
    }

    await context.startAbility(wantInfo).catch((err: BusinessError) => {
        console.error(`startAbility errCode: ${err.code}, errMessage: ${err.message}`)
    })
}

export async function askUserAuthorize(context: common.UIAbilityContext,
    userAgreeCallback?: () => void,
    userDenyCallback?: () => void,
    notPopCallback?: () => void) {
    let result = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(context, ['ohos.permission.ACCESS_NEARLINK'])
        .catch((err: BusinessError) => console.error(`errCode: ${err.code}, errMessage: ${err.message}`))
    if (result) {
        let grantStatus = result.authResults[0]
        console.info(`grant status: ${grantStatus}`)

        if (grantStatus === 0) {
            if (userAgreeCallback) {
                userAgreeCallback()
            }
        } else {
            if (result.dialogShownResults && result.dialogShownResults[0]) {
                // 弹窗了，用户没有同意
                if (userDenyCallback) {
                    userDenyCallback()
                }
            } else {
                if (notPopCallback) {
                    notPopCallback()
                }
            }
        }
    } else {
        console.info("no result")
    }
}

export async function enableSle(bleOnCallback?: () => void) {
    manager.on('stateChange', state => {
        if (state == manager.NearlinkState.STATE_ON) {
            manager.off('stateChange')
            if (bleOnCallback) {
                bleOnCallback()
            }
        }
        console.debug(`nearlink statues: ${state}`)
    })

    try {
        console.debug("enableSle is not enable right now")
        // manager.enableBluetooth()
    } catch (err) {
        console.error(`enableSle errCode: ${err.code}, errMessage: ${err.message}`)
    }
}

export interface SleDevice {
    name: string
    rssi: number
    macAddress: string
}

/** 与 scan.on 成对使用，避免每次 startSleScan 再注册一层 deviceFound（日志会爆炸、列表被重复回调） */
interface ScanResultRow {
    isConnectable: boolean
    deviceName: string
    rssi: number
    address: string
}

let scanDeviceFoundUserCallback: Callback<Array<SleDevice>> | undefined = undefined

const onScanDeviceFound = (scanResult: Array<ScanResultRow>): void => {
    if (!scanDeviceFoundUserCallback) {
        return
    }
    scanDeviceFoundUserCallback(scanResult.filter(result => result.isConnectable).map(result => ({
        name: result.deviceName,
        rssi: result.rssi,
        macAddress: result.address
    })))
}

function detachScanDeviceFoundListener(): void {
    try {
        scan.off('deviceFound', onScanDeviceFound)
    } catch (err) {
        console.debug(`scan.off deviceFound: ${JSON.stringify(err)}`)
    }
}

export async function startSleScan(scanResultCallback: Callback<Array<SleDevice>>) {
    detachScanDeviceFoundListener()
    scanDeviceFoundUserCallback = scanResultCallback
    scan.on('deviceFound', onScanDeviceFound)
    try {
        console.log("scan.startScan")
        // 开启星闪扫描
        let scanFilter: scan.ScanFilters = {
            deviceName: "COUNTER" // 期望扫描到的外围设备的名称
        };
        let scanFilter2: scan.ScanFilters = {
            deviceName: "XH_LAMP" // 期望扫描到的外围设备的名称
        };
        let scanOptions: scan.ScanOptions = {
            scanMode: 2
        }
        scan.startScan([scanFilter, scanFilter2], scanOptions)
    } catch (err) {
        console.error(`errCode: ${err.code}, errMessage: ${err.message}`)
    }
}

export function stopSleScan() {
    try {
        console.log("scan.stopScan")
        scan.stopScan()
    } catch (err) {
        console.error(`errCode: ${err.code}, errMessage: ${err.message}`)
    }
    detachScanDeviceFoundListener()
    scanDeviceFoundUserCallback = undefined
}

let connectedDevice: ssap.Client | undefined = undefined
let serviceList: Array<ssap.Service> = []

export async function connectToDevice(macAddress: string, connectedCallback?: () => void,
    disconnectedCallback?: () => void,
    servicesCallback?: Callback<Array<ssap.Service>>,
    propertyNotifyCallback?: (shortUUID: string, propertyValue: string) => void) {
    connectedDevice = ssap.createClient(macAddress)
    connectedDevice?.on('connectionStateChange', async (state: ssap.ConnectionChangeState) => {
        let connectState: ssap.ConnectionChangeState = state
        if (connectState.state === constant.ConnectionState.STATE_CONNECTED) {
            if (connectedCallback) {
                connectedCallback()
            }
            connectedDevice?.on('propertyChange', (characteristic: ssap.Property) => {
                if (propertyNotifyCallback) {
                    propertyNotifyCallback(getShortUUID(characteristic.propertyUuid),
                        arrayBufferToString(characteristic.value))
                }
            })
            serviceList = await connectedDevice?.getServices()
            if (servicesCallback) {
                servicesCallback(serviceList)
            }
        } else if (connectState.state === constant.ConnectionState.STATE_DISCONNECTED) {
            if (disconnectedCallback) {
                disconnectedCallback()
            }
            // 这句很关键，取消订阅所有事件
            connectedDevice?.close()
            connectedDevice = null
        }
    })

    try {
        connectedDevice?.connect()
    } catch (err) {
        console.error(`errCode: ${err.code}, errMessage: ${err.message}`)
    }
    return connectedDevice
}

export async function disconnectDevice() {
    try {
        connectedDevice?.disconnect()
    } catch (err) {
        console.error(`errCode: ${err.code}, errMessage: ${err.message}`)
    }
}

// 根据SLE协议，把UUID改为短写模式，方便操作
export const getShortUUID = (src: string): string => {
    return src.slice(src.length - 4)
}

const strToArrayBuffer = (str: string): ArrayBuffer => {
    const pairs = str.toUpperCase().match(/[0-9A-F]{2}/g)
    if (!pairs) {
        return new ArrayBuffer(0)
    }
    return buffer.from(pairs.map(s => parseInt(s, 16))).buffer
}

/** 每字节固定两位十六进制，与 strToArrayBuffer 的「双字符一字节」一致；否则 0x01+0x00 会误显示为 "10" */
const arrayBufferToString = (buff: ArrayBuffer | undefined): string => {
    if (buff === undefined || buff.byteLength === 0) {
        return ""
    }
    let temp = ""
    const arr = new Uint8Array(buff)
    for (let i = 0; i < arr.byteLength; i++) {
        const h = arr[i].toString(16)
        temp += (h.length === 1 ? "0" : "") + h
    }
    return temp.toUpperCase()
}


const findTargetProperty = (propertyUuid: string): ssap.Property | undefined => {
    let targetProperty: ssap.Property | undefined = undefined

    serviceList.forEach(service => {
        service.properties.forEach(property => {
            if (property.propertyUuid == propertyUuid) {
                targetProperty = property
            }
        })
    })

    if (targetProperty == undefined) {
        console.error(`property ${propertyUuid} not found`)
    }

    return targetProperty
}


export const readProperty = async (propertyUuid: string): Promise<string | undefined> => {
    try {
        if (!connectedDevice) {
            return undefined
        }
        // 重新拉一次 GATT，避免一直用发现服务时缓存的 value（容易固定成如 0100）
        serviceList = await connectedDevice.getServices()
        const target = findTargetProperty(propertyUuid)
        if (!target) {
            console.error(`readProperty: property not found ${propertyUuid}`)
            return undefined
        }
        const readBack = await connectedDevice.readProperty(target)
        // 部分实现把读到的字节写回返回值，部分写回入参 Property，两处都尝试
        const buf = (readBack?.value !== undefined && readBack.value.byteLength > 0)
            ? readBack.value
            : (target.value !== undefined && target.value.byteLength > 0 ? target.value : undefined)
        if (!buf || buf.byteLength === 0) {
            return undefined
        }
        const s = arrayBufferToString(buf)
        console.info(`readProperty ${propertyUuid.slice(-8)} => ${s} (${buf.byteLength} bytes)`)
        return s.length > 0 ? s : undefined
    } catch (err) {
        console.error(`errCode: ${err.code}, errMessage: ${err.message}`)
    }
    return undefined
}

export const writeProperty = async (propertyUuid: string, writeValue: string) => {
    let targetProperty = findTargetProperty(propertyUuid)
    // 把writeValue按照每两个字符串分割后按照16进制转换为数字后写入
    if (targetProperty) {
        targetProperty.value = strToArrayBuffer(writeValue)
    }

    try {
        await connectedDevice?.writeProperty(targetProperty, ssap.PropertyWriteType.WRITE)
    } catch (err) {
        console.error(`errCode: ${err.code}, errMessage: ${err.message}`)
    }
}

export const subscribeProperty = (propertyUuid: string) => {
    try {
        connectedDevice?.setPropertyNotification(findTargetProperty(propertyUuid), true)
    } catch (err) {
        console.error(`errCode: ${err.code}, errMessage: ${err.message}`)
    }
}
