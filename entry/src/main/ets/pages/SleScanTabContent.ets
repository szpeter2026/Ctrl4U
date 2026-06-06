import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'
import { JumpToSettingDialog } from '../dialogs/JumpToSettingDialog'
import {
    askUserAuthorize,
    SleDevice,
    enableSle,
    getGrantStatus,
    getSleState,
    jumpToSetting,
    startSleScan,
    stopSleScan
} from '../sle/helper'
import { manager } from '@kit.NearLinkKit'
import { SleAuthorizeDialog } from '../dialogs/SleAuthorizeDialog'
import { SleSwitchDialog } from '../dialogs/SleSwitchDialog'

@Component
export struct SleScanTabContent {
    @State bleItemList: Array<SleDevice> = []
    @State sleScanning: boolean = false
    private scanTimer = -1
    sleAuthorizeDialogController: CustomDialogController = new CustomDialogController({
        builder: SleAuthorizeDialog({
            confirm: () => {
                this.onSleAuthorizeDialogConfirm()
            }
        }),
        alignment: DialogAlignment.Bottom
    })
    sleSwitchDialogController: CustomDialogController = new CustomDialogController({
        builder: SleSwitchDialog({
            confirm: () => {
                this.onSleSwitchDialogConfirm()
            }
        }),
        alignment: DialogAlignment.Bottom
    })
    jumpToSettingDialogController: CustomDialogController = new CustomDialogController({
        builder: JumpToSettingDialog({
            confirm: () => {
                this.onJumpToSettingDialogConfirm()
            }
        }),
        alignment: DialogAlignment.Bottom
    })

    onSleAuthorizeDialogConfirm() {
        askUserAuthorize(getContext(this) as common.UIAbilityContext, () => {
            this.onSleState(getSleState())
        }, () => {
        }, () => {
            this.jumpToSettingDialogController.open()
        })
    }

    onSleSwitchDialogConfirm() {
        enableSle(() => {
            this.startScan()
        })
    }

    onJumpToSettingDialogConfirm() {
        jumpToSetting(getContext(this) as common.UIAbilityContext)
    }

    stopScan() {
        this.sleScanning = false
        stopSleScan()
        if (this.scanTimer > 0) {
            clearTimeout(this.scanTimer)
            this.scanTimer = -1
        }
    }

    aboutToDisappear(): void {
        this.stopScan()
    }

    aboutToAppear(): void {
        this.bleItemList = []
    }

    startScan() {
        this.sleScanning = true
        startSleScan((bleDeviceList: Array<SleDevice>) => {
            bleDeviceList.forEach(bleDevice => {
                let foundDevice = this.bleItemList.find(item => item.name == bleDevice.name)
                if (foundDevice) {
                    foundDevice.rssi = bleDevice.rssi
                } else {
                    this.bleItemList.push({
                        name: bleDevice.name,
                        rssi: bleDevice.rssi,
                        macAddress: bleDevice.macAddress
                    })
                }
            })
        })
        this.scanTimer = setTimeout(() => {
            this.stopScan()
        }, 20 * 1000)
    }

    onSleState(sleState: manager.NearlinkState) {
        if (sleState == manager.NearlinkState.STATE_OFF) {
            this.sleSwitchDialogController.open()
        } else if (sleState === manager.NearlinkState.STATE_ON) {
            this.startScan()
        }
    }

    onGetGrantStatus(grantStatus: abilityAccessCtrl.GrantStatus) {
        if (grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
            this.onSleState(getSleState())
        } else if (grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_DENIED) {
            this.sleAuthorizeDialogController.open()
        }
    }

    build() {
        Column() {
            Flex({
                direction: FlexDirection.Row,
                alignItems: ItemAlign.Auto,
                justifyContent: FlexAlign.SpaceAround
            }) {
                Button("开始扫描").onClick(async () => {
                    if (this.sleScanning) {
                        return
                    }
                    const grantStatus = await getGrantStatus()
                    this.onGetGrantStatus(grantStatus)
                }).enabled(!this.sleScanning)
            }

            List() {
                ForEach(this.bleItemList, (item: SleDevice) => {
                    ListItem() {
                        Row() {
                            Text(item.name.length > 0 ? item.name : "noname")
                            Text(item.rssi.toString())
                            Text(item.macAddress).fontSize(8)
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.SpaceBetween)
                    }.onClick(() => {
                        this.stopScan()

                        router.pushUrl({
                            url: 'pages/SleDevicePage',
                            params: item
                        }, err => {
                            if (err) {
                                console.error(`Invoke pushUrl failed, code is ${err.code}, message is ${err.message}`)
                                return
                            }
                        })
                    })
                    .margin(10)
                    .padding(15)
                    .border({ width: 1, color: Color.Black })
                }, (item: SleDevice) => `${item.macAddress}${item.rssi}`)
            }.width("90%").backgroundColor("#ff93deff").margin({ top: 30 }).layoutWeight(1)
        }
        .padding({ top: 30, bottom: 50 })
        .height('100%')
        .width('100%')
    }
}
