@CustomDialog
@Component
export struct SleAuthorizeDialog {
    cancel?: Function
    confirm?: Function
    controller: CustomDialogController

    build() {
        Column() {
            Text("请授权APP获取星闪权限以建立星闪连接")
            Flex({ justifyContent: FlexAlign.SpaceAround }) {
                Button('关闭')
                    .onClick(() => {
                        this.controller.close()
                        if (this.cancel) {
                            this.cancel()
                        }
                    })

                Button('去授权')
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
