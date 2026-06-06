@CustomDialog
@Component
export struct JumpToSettingDialog {
    cancel?: Function
    confirm?: Function
    controller: CustomDialogController

    aboutToAppear(): void {
        console.debug(`open JumpToSettingDialog`)
    }

    build() {
        Column() {
            Text('请在系统设置页面打开星闪授权')
            Flex({ justifyContent: FlexAlign.SpaceAround }) {
                Button('关闭')
                    .onClick(() => {
                        this.controller.close()
                        if (this.cancel) {
                            this.cancel()
                        }
                    })
                Button('去设置')
                    .onClick(async () => {
                        this.controller.close()
                        if (this.confirm) {
                            await this.confirm()
                        }
                    })
            }.margin({ top: 20 })
        }.backgroundColor(Color.White).padding({ top: 30, bottom: 30 })
    }
}
