@CustomDialog
@Component
export struct SleSwitchDialog {
    cancel?: Function
    confirm?: Function
    controller: CustomDialogController

    build() {
        Column() {
            Text("请打开星闪开关")
            Flex({ justifyContent: FlexAlign.SpaceAround }) {
                Button('关闭')
                    .onClick(() => {
                        this.controller.close()
                        if (this.cancel) {
                            this.cancel()
                        }
                    })
                Button('去打开')
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
