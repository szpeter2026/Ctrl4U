// Hero3D.ets — 骑行 3D 设备拓扑（合并 YeDall 视觉层次 + Ctrl4U 骑行语义）
//
// - 中央：Ring Control；环绕：前灯 / 尾灯 / 头盔相机 / 跟拍无人机 / 码表（骑行扩展位）
// - ArkUI：offset + scale + opacity + 轻微 X 轴 rotate，营造「骑行前向俯视」空间感
// - 动画帧通过整体替换 @State 数组触发刷新（避免仅改字段不刷新的问题）

import { promptAction } from '@kit.ArkUI';

const BRAND_PURPLE = '#534AB7';
const HERO_TOP = '#E8F4FC';
const HERO_BOTTOM = '#B8E0F0';
const ROAD_LINE = '#94A3B8';

interface CyclingDevice {
  icon: string;
  label: string;
  glowColor: string;
  radius: number;
  speed: number;
  angleDeg: number;
}

@Component
export struct Hero3D {
  @State private rotating: boolean = true;
  @State private devices: CyclingDevice[] = [
    { icon: '💡', label: '前灯', glowColor: '#FFD54F', radius: 82, speed: 1.15, angleDeg: 0 },
    { icon: '🚦', label: '尾灯', glowColor: '#EF5350', radius: 82, speed: 0.82, angleDeg: 72 },
    { icon: '📷', label: '头盔相机', glowColor: '#66BB6A', radius: 82, speed: 0.98, angleDeg: 144 },
    { icon: '🚁', label: '跟拍无人机', glowColor: '#42A5F5', radius: 82, speed: 0.88, angleDeg: 216 },
    { icon: '⌚', label: '码表', glowColor: '#AB47BC', radius: 82, speed: 1.05, angleDeg: 288 },
  ];
  private timerId: number = -1;

  aboutToAppear(): void {
    this.startAnimation();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private startAnimation(): void {
    this.stopTimer();
    if (!this.rotating) {
      return;
    }
    this.timerId = setInterval(() => {
      if (!this.rotating) {
        return;
      }
      const next: CyclingDevice[] = [];
      for (let i = 0; i < this.devices.length; i++) {
        const d = this.devices[i];
        next.push({
          icon: d.icon,
          label: d.label,
          glowColor: d.glowColor,
          radius: d.radius,
          speed: d.speed,
          angleDeg: (d.angleDeg + d.speed * 0.58) % 360,
        });
      }
      this.devices = next;
    }, 16);
  }

  private toggleRotate(): void {
    this.rotating = !this.rotating;
    if (this.rotating) {
      this.startAnimation();
    } else {
      this.stopTimer();
    }
    promptAction.showToast({ message: this.rotating ? '动画：继续' : '动画：已暂停' });
  }

  private onDeviceTap(device: CyclingDevice): void {
    promptAction.showToast({ message: `${device.label} · 骑行装备（示意）` });
  }

  build() {
    Column() {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          // 3D 主场景：轻微俯视角（与 YeDall 同系 transform，语义改为骑行）
          Stack({ alignContent: Alignment.Center }) {
            // 「路面」置于场景内，与俯视角一致
            Column()
              .width('78%')
              .height(3)
              .backgroundColor(ROAD_LINE)
              .opacity(0.4)
              .borderRadius(2)
              .offset({ y: 72 })
              .zIndex(1);

            // ── 中央：Ring Control ──
            Column() {
              Stack() {
                Column()
                  .width(64)
                  .height(64)
                  .borderRadius(32)
                  .backgroundColor(BRAND_PURPLE)
                  .opacity(0.14);

                Column()
                  .width(50)
                  .height(50)
                  .borderRadius(25)
                  .backgroundColor('#FFFFFF')
                  .shadow({ radius: 18, color: '#40534AB7', offsetY: 4 });

                Text('◯')
                  .fontSize(24)
                  .fontColor(BRAND_PURPLE);
              }
              .width(64)
              .height(64);

              Text('Ring Control')
                .fontSize(10)
                .fontColor(BRAND_PURPLE)
                .opacity(0.85)
                .margin({ top: 4 });

              Text('骑行视角')
                .fontSize(9)
                .fontColor('#78909C')
                .margin({ top: 2 });
            }
            .zIndex(10);

            ForEach(this.devices, (device: CyclingDevice, index: number) => {
              Stack() {
                Column({ space: 2 }) {
                  Text(device.icon)
                    .fontSize(27)
                    .shadow({ radius: 6, color: '#30000000', offsetY: 3 });

                  Text(device.label)
                    .fontSize(9)
                    .fontColor('#555555');
                }
                .alignItems(HorizontalAlign.Center);
              }
              .width(56)
              .height(56)
              .borderRadius(12)
              .backgroundColor('#FFFFFF')
              .shadow({ radius: 9, color: '#18000000', offsetY: 2 })
              .offset({
                x: -device.radius * Math.sin(device.angleDeg * Math.PI / 180) * 0.86,
                y: -device.radius * Math.cos(device.angleDeg * Math.PI / 180) * 0.46,
              })
              .scale({
                x: 0.42 + 0.58 * (Math.cos(device.angleDeg * Math.PI / 180) + 1) / 2,
                y: 0.42 + 0.58 * (Math.cos(device.angleDeg * Math.PI / 180) + 1) / 2,
              })
              .opacity(0.38 + 0.62 * (Math.cos(device.angleDeg * Math.PI / 180) + 1) / 2)
              .zIndex(Math.floor((Math.cos(device.angleDeg * Math.PI / 180) + 1) / 2 * 5))
              .onClick(() => {
                this.onDeviceTap(device);
              });
            }, (device: CyclingDevice, index: number) => index.toString());

            Column()
              .width(164)
              .height(164)
              .borderRadius(82)
              .border({ width: 1, color: '#C8D8E8', style: BorderStyle.Dashed })
              .opacity(0.48);
          }
          .width('100%')
          .height(200)
          .clip(true)
          .rotate({
            x: 1,
            y: 0,
            z: 0,
            angle: 7,
            centerX: '50%',
            centerY: '50%',
          });
        }
        .width('100%')
        .height(208)
        .clip(false);

        Row({ space: 10 }) {
          Button(this.rotating ? '暂停' : '继续')
            .fontSize(12)
            .height(30)
            .fontColor('#5C6BC0')
            .backgroundColor('#E8EAF6')
            .onClick(() => {
              this.toggleRotate();
            });

          Text('360° 骑行装备环绕 · 3D 拓扑')
            .fontSize(12)
            .fontColor('#8EC8E8')
            .layoutWeight(1);

          Text('NearLink / BLE')
            .fontSize(10)
            .fontColor('#90A4AE');
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 10 });
      }
      .width('100%')
      .height(268)
      .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 24, bottomRight: 24 })
      .linearGradient({
        direction: GradientDirection.Top,
        colors: [[HERO_TOP, 0], [HERO_BOTTOM, 1]],
      })
      .onClick(() => {
        promptAction.showToast({ message: '骑行装备空间拓扑 · Ring Control 中枢' });
      });
    }
    .width('100%');
  }
}
