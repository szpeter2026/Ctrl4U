/**
 * TEE 安全相机演示页：与 README「安全相机 / 头盔第一视角」能力对齐的可验证入口。
 * 依赖设备支持 SECURE_PHOTO、已授予 CAMERA 权限；失败时以文案提示，不阻塞返回。
 */
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import secureCameraService from '../model/SecureCamera';

@Entry
@Component
struct SecureCameraDemoPage {
  private xComponentController: XComponentController = new XComponentController();
  @State private hint: string = '加载预览组件后将尝试建立安全相机会话…';
  @State private busy: boolean = false;
  private started: boolean = false;

  private async ensureCameraPermission(): Promise<boolean> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const perms: Permissions[] = ['ohos.permission.CAMERA'];
    try {
      const at = abilityAccessCtrl.createAtManager();
      const r = await at.requestPermissionsFromUser(ctx, perms);
      return r.authResults[0] === 0;
    } catch (_e) {
      return false;
    }
  }

  private async tryStartSecureCamera(): Promise<void> {
    if (this.started || this.busy) {
      return;
    }
    const ok = await this.ensureCameraPermission();
    if (!ok) {
      this.hint = '需要相机权限才能演示安全相机';
      promptAction.showToast({ message: '请授予相机权限后重试' });
      return;
    }
    this.busy = true;
    this.hint = '正在初始化安全相机…';
    try {
      const surfaceId: string = this.xComponentController.getXComponentSurfaceId();
      const ctx = getContext(this) as common.UIAbilityContext;
      await secureCameraService.initCamera(surfaceId, ctx, (_err: BusinessError, _msg: string) => {
        // 安全帧到达时由 SecureCamera 内部校验链路处理
      });
      this.started = true;
      this.hint = '安全相机会话已建立（DeviceSecurityKit + SecureSession）。拍照校验见 SecureCamera 实现。';
    } catch (e) {
      const msg = (e as BusinessError).message ?? `${e}`;
      this.hint = `当前设备或环境不可用：${msg}`;
      promptAction.showToast({ message: '安全相机初始化失败（部分机型无 SECURE_PHOTO）' });
    } finally {
      this.busy = false;
    }
  }

  aboutToDisappear(): void {
    void secureCameraService.closeCamera();
  }

  private async leave(): Promise<void> {
    try {
      await secureCameraService.closeCamera();
    } catch (_e) {
      // best-effort
    }
    router.back();
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(22)
          .padding({ right: 12 })
          .onClick(() => {
            void this.leave();
          })
        Text('TEE 安全相机')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(34)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 48, bottom: 12 })

      Text(this.hint)
        .fontSize(13)
        .fontColor('#555555')
        .padding({ left: 16, right: 16, bottom: 8 })

      XComponent({
        id: 'ctrl4u_secure_cam',
        type: XComponentType.SURFACE,
        libraryname: '',
        controller: this.xComponentController
      })
        .width('100%')
        .height(280)
        .backgroundColor('#000000')
        .onLoad(() => {
          void this.tryStartSecureCamera();
        })

      Button('结束并返回')
        .margin({ top: 16, left: 24, right: 24 })
        .width('100%')
        .onClick(() => {
          void this.leave();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F7')
  }
}
