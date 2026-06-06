@CustomDialog
@Component
export struct SleWriteDialog {
    cancel?: Function
    confirm?: Function
    controller: CustomDialogController
    private sentValue = ""

    build() {
        Column() {
            TextInput({ placeholder: "请输入16进制字符串" }).onChange((value: string) => {
                this.sentValue = value
            }).margin({ left: 20, right: 20 })
            Flex({ justifyContent: FlexAlign.SpaceAround }) {
                Button('关闭')
                    .onClick(() => {
                        this.controller.close()
                        if (this.cancel) {
                            this.cancel()
                        }
                    })
                Button('发送')
                    .onClick(async () => {
                        this.controller.close()
                        if (this.confirm) {
                            await this.confirm(this.sentValue)
                        }
                    })
            }.margin({ top: 20 })
        }.backgroundColor(Color.White).padding({ top: 30, bottom: 30 })
    }
}
