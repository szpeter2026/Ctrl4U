# Ctrl4U

> 2026 HarmonyOS 创新赛 · 极客赛道 参赛作品  
> 骑行智能操控整体解决方案 | 基于 HarmonyOS 6.0+

<p align="center">
  <img src="entry/src/main/resources/base/media/logo.png" width="120" alt="Ctrl4U Logo"/>
</p>

---

## 📖 项目简介

**Ctrl4U** 是一款面向骑行运动爱好者的 HarmonyOS 原生智能操控应用，配合自主研发的 **Ring Control 智能指环硬件**，为骑行者提供「行车安全 + 无人机跟拍 + 头盔相机控制」三位一体的整体解决方案。

当骑行者在高速骑行过程中，双手无法离开车把去操作手机——Ctrl4U 通过指环手势与星闪/蓝牙近场通信，让骑行者**无需脱把**即可控制方向灯、鸣笛、跟拍无人机和头盔第一视角相机，全面兼顾行车安全与运动影像创作。

---

## 能力实现状态（与当前源码对齐）

| 模块 | 状态 | 说明 |
|------|------|------|
| 星闪 NearLink 扫描 / SSAP 连接 / 服务发现 | ✅ 已落地 | `sle/helper.ts` + 扫描页 + 设备页读/写/订阅 |
| DeviceSecurityKit：URL 威胁检测 | ✅ 已落地 | 访问官网前检测；`SafetyDetectModel` |
| DeviceSecurityKit：防窥蒙层 | ✅ 已落地 | `AntiPeepUtils` + 主窗口遮罩同步 |
| DeviceSecurityKit：安全地理位置 + TEE 证明链校验 | ✅ 已落地 | `SecureLocation` + `CertChain`（用于证明链，非外设连接） |
| 系统完整性检测 (`checkSysIntegrity`) | ✅ 已落地 | 冷启动经 `SafetyDetectModel` 调用一次，结果写入首页日志 |
| 骑行 AI 助手（DeepSeek SSE 流式对话） | ✅ 已落地 | `SseClient.ets` + `Config.ets`；**需配置 API Key** |
| Ring Control 首页模式开关 → 具体 SSAP 指令 | 🔜 待绑定 | 当前为场景 UI；指令需按固件 UUID/协议映射后接入 `writeProperty` |
| 蓝牙备选（App 内发现与连接） | ✅ 已落地（扫描） | `BleDiscovery.ets`：`access` + `ble.startBLEScan`；首页「+」触发约 12s 扫描并写日志，仍跳转系统设置便于配对 |
| 安全相机 `SecureCamera` | ✅ 已接演示入口 | Ring Control 页 →「TEE 安全相机演示」→ `SecureCameraDemoPage`（需真机 SECURE_PHOTO + 相机权限） |
| 3D 空间拓扑展示 | ✅ 已增强 | `Hero3D.ets`：5 装备环绕、俯视角 rotate、路面线、暂停/继续；初赛以 ArkUI 呈现空间关系。**官方 AR Engine 等为演进预留**（见下节「官方 3D / AR 与穿戴演进」） |

---

## 官方 3D / AR 与穿戴演进（预留）

- **当前**：`Hero3D` 在主流机型上稳定展示「人–盔–灯–机–表」相对拓扑，支撑「3D 空间化」方向的**可演示、可叙事**入场，无需依赖 AR 专用硬件。  
- **规划**：对接鸿蒙 **官方 AR / 空间感知等开放能力**（以届时 SDK 与设备准入为准），优先适配 **AI 安全眼镜等可穿戴**，融合 **近场控制（星闪/BLE）与道路/环境感知**，形成可理解为 **「智能驾驶能力在骑行场景的轻量化微缩」** 的辅助体验——强调 **预警与感知辅助**，**不替代**道路交通安全责任与法规要求。  
- **底座**：与 **NearLink、BLE 发现、DeviceSecurityKit、安全定位、TEE 安全相机** 同一条「连接 + 信任」主线延伸，便于决赛阶段与全栈仓合并放大。

---

## 🎬 用户场景

<p align="center">
  <b>10-360p.mp4</b> · 骑行场景一 &nbsp;&nbsp;|&nbsp;&nbsp; <b>20-360p.mp4</b> · 骑行场景二
</p>

### 典型骑行场景痛点

| 痛点 | 传统方式 | Ctrl4U 方案 |
|------|---------|------------|
| **打方向灯** | 单手脱把操作手机，极其危险 | 手指轻触 Ring Control，星闪近场低延迟响应（目标体验） |
| **鸣笛示警** | 无法及时提醒后方来车 | 指环一键触发喇叭，安全预警 |
| **无人机跟拍** | 需要停车、拿出手机、操作 App | 骑行中手势控制无人机起降/跟随 |
| **头盔相机控制** | 需停车开启/关闭录制 | 指环直接控制第一视角相机拍照/录像 |
| **隐私安全** | 相机/位置数据无防护 | TEE 安全相机 + 防篡改定位 + 防窥蒙层 |

### 目标用户画像

- **骑行运动爱好者**：城市通勤骑手、公路/山地骑行玩家
- **运动影像创作者**：需要第一视角 + 第三视角（无人机）跟拍素材
- **安全敏感人群**：夜间或复杂路况骑行，需要及时的方向灯和喇叭信号

---

## 🏗️ 整体解决方案架构

```
┌──────────────────────────────────────────────────────────────┐
│                     Ring Control 智能指环                      │
│          (方向灯 / 喇叭 / 无人机 / 相机 手势指令)                │
└────────────────────────┬─────────────────────────────────────┘
                         │ 星闪 (NearLink) / 蓝牙
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                    Ctrl4U (HarmonyOS App)                     │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────────────────┐ │
│  │ 行车安全控制  │ │ 无人机跟拍控制 │ │  头盔相机安全控制       │ │
│  │ · 方向灯      │ │ · 起降        │ │  · 安全拍照/录像        │ │
│  │ · 喇叭        │ │ · 跟随        │ │  · 第一视角预览         │ │
│  │ · GPS安全定位 │ │ · 返航        │ │  · TEE签名验证          │ │
│  └─────────────┘ └──────────────┘ └────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │              安全隐私基础设施 (DeviceSecurityKit)          │ │
│  │   系统完整性检测  │  URL威胁检测  │  防窥蒙层  │  证书链验证  │ │
│  └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### 硬件生态

| 设备 | 连接方式 | 控制内容 |
|------|---------|---------|
| **Ring Control 智能指环** | 星闪 (NearLink) / BLE | 方向灯、喇叭、无人机、相机指令发送 |
| **无人机** | 通过手机中转 | 起降、跟随、返航 |
| **头盔第一视角相机** | 通过手机控制 | 安全拍照/录像、实时预览 |

---

## 🎯 创新方向覆盖

### 1. 安全隐私保护（核心方向）

骑行场景中，位置和影像数据的安全至关重要：

| 能力 | 场景价值 |
|------|---------|
| **系统完整性检测** (`checkSysIntegrity`) | 确保 App 运行环境未被 Root/篡改，防止骑行数据被劫持 |
| **安全地理位置** (`SecureLocation`) | TEE 可信执行环境 + ECC256 签名，位置信息不可伪造——骑行轨迹可作为比赛/保险凭证 |
| **安全相机** (`SecureCamera`) | 头盔相机拍照经前端 SecureSession + 签名验证，防止图像被替换篡改 |
| **URL 威胁检测** (`checkUrlThreat`) | 访问骑行社区/官网前实时检测钓鱼链接 |
| **防窥蒙层** (`DLP Anti-Peep`) | 公共场合（路口等红灯时）防止旁人窥屏，保护个人骑行数据 |
| **证书链验证** (`CertChain`) | 解析 PKIX 证书链、提取 ECC256 公钥，用于 **DeviceSecurityKit 安全定位 / 安全相机** 等证明链校验（当前工程未将同一套逻辑用于星闪外设鉴权） |

### 2. 全场景一体协同（核心方向）

| 能力 | 场景价值 |
|------|---------|
| **星闪 (NearLink) 连接** | 低延迟、低功耗近场链路；与经典蓝牙的量化对比需以实测或芯片/厂商规格为准 |
| **SLE 属性读写订阅** | 通用 SSAP 读写与通知；**语义级手势（转向灯/喇叭等）需在固件协议确定后**映射到具体特征 UUID |
| **蓝牙备选通道** | **已实现**：`ConnectivityKit` 低功耗扫描发现周边设备；未配对时仍可跳转系统蓝牙完成配对 |
| **多设备类型适配** | Phone / Tablet / Wearable / TV / Car，骑行场景全部覆盖 |

### 3. 创新方向覆盖总览

| 创新方向 | 覆盖状态 | 核心能力 |
|---------|---------|---------|
| **安全隐私保护** | ✅ 核心已落地 | DeviceSecurityKit（URL / 防窥 / 安全定位）+ `CertChain` 用于证明链 |
| **全场景一体协同** | ✅ 核心已落地 / 蓝牙扫描已补 | NearLinkKit（星闪）+ SLE SSAP；`BleDiscovery` BLE 扫描；`module.json5` 多设备类型 |
| **AI 智能化体验** | ✅ 已落地 | DeepSeek SSE 骑行助手对话 + URL 威胁检测 |
| **3D 空间化** | ✅ 初赛呈现 / 🔜 官方 AR 演进 | `Hero3D`（ArkUI 空间拓扑）；**AI 安全眼镜 + 官方 AR/道路感知** 见 README「官方 3D / AR 与穿戴演进」 |

---

## 🏗️ 技术架构

```
┌─────────────────────────────────────────────────┐
│                   UI Layer                        │
│  Index.ets (主页面)  │  SleDevicePage.ets (设备)  │
│  SleScanTabContent   │  SseClient (AI SSE)       │
│  Hero3D              │  SecureCameraDemoPage     │
│  各类 Dialog 组件    │                            │
├─────────────────────────────────────────────────┤
│                 Model Layer                       │
│  SafetyDetectModel  │  SecureCamera  │  SecureLocation │
├─────────────────────────────────────────────────┤
│               Common / Utils                      │
│  AntiPeepUtils  │  CertChain  │  BleDiscovery │  SLE Helper      │
├─────────────────────────────────────────────────┤
│           HarmonyOS System APIs                   │
│  DeviceSecurityKit  │  NearLinkKit  │  LocationKit│
│  CameraKit  │  CryptoKit  │  ConnectivityKit (BLE)  │
├─────────────────────────────────────────────────┤
│              Ring Control 硬件                     │
│         星闪/BLE 通信 · 手势识别 · 指令发送          │
└─────────────────────────────────────────────────┘
```

### 申请的权限

| 权限 | 骑行场景用途 |
|------|------------|
| `ohos.permission.ACCESS_BLUETOOTH` | 蓝牙连接 Ring Control 指环 |
| `ohos.permission.DISCOVER_BLUETOOTH` | 发现周边骑行设备 |
| `ohos.permission.LOCATION` | GPS 骑行轨迹记录 + 安全定位 |
| `ohos.permission.APPROXIMATELY_LOCATION` | 辅助定位，适配骑行场景 |
| `ohos.permission.CAMERA` | 头盔安全相机拍照 |
| `ohos.permission.ACCESS_NEARLINK` | 星闪扫描连接 Ring Control |
| `ohos.permission.INTERNET` | 骑行社区/官网访问 |
| `ohos.permission.DLP_GET_HIDE_STATUS` | 防窥状态检测 |

---

## 📁 项目结构

```
Ctrl4U/
├── 10-360p.mp4                        # 骑行场景演示视频一
├── 20-360p.mp4                        # 骑行场景演示视频二
├── 2026harmony.md                     # 竞赛参赛说明
├── 作品介绍_Ctrl4U.md                  # 参赛用作品介绍（创新点与提交清单）
├── 项目差异对比报告.md                  # 版本差异分析
├── README.md                          # 本文件
├── entry/
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/          # 应用入口
│   │   │   ├── pages/
│   │   │   │   ├── Index.ets          # 主页面（设备 + AI + 设置）
│   │   │   │   ├── SleDevicePage.ets  # 星闪设备 SSAP 调试页
│   │   │   │   ├── SecureCameraDemoPage.ets # TEE 安全相机演示（XComponent）
│   │   │   │   └── SleScanTabContent.ets # 星闪设备扫描列表
│   │   │   ├── components/
│   │   │   │   └── Hero3D.ets         # 骑行设备拓扑动效
│   │   │   ├── services/
│   │   │   │   └── SseClient.ets      # AI SSE（DeepSeek / 可选后端）
│   │   │   ├── model/
│   │   │   │   ├── SafetyDetectModel.ts # 安全检测（系统完整性 + URL）
│   │   │   │   ├── SecureCamera.ets   # TEE 安全相机（模块）
│   │   │   │   └── SecureLocation.ets # TEE 安全地理位置
│   │   │   ├── sle/
│   │   │   │   └── helper.ts          # 星闪扫描/连接/读写/订阅封装
│   │   │   ├── common/
│   │   │   │   ├── Config.ets         # AI 端点与 DeepSeek API Key
│   │   │   │   ├── BleDiscovery.ets   # BLE 扫描（ConnectivityKit）
│   │   │   │   ├── CertChain.ets      # 证书链解析与 PKIX 验证
│   │   │   │   └── utils/
│   │   │   │       └── AntiPeepUtils.ets # DLP 防窥蒙层工具
│   │   │   └── dialogs/               # 授权/写入/跳转设置对话框
│   │   ├── resources/
│   │   │   ├── base/media/            # 图标与媒体资源
│   │   │   │   ├── logo.png           # 应用 Logo
│   │   │   │   ├── device.png         # 设备图标
│   │   │   │   ├── setting.png        # 设置图标
│   │   │   │   ├── signal.png         # 信号图标
│   │   │   │   ├── stand.mp4          # 待机动画
│   │   │   │   ├── run.mp4            # 骑行动画
│   │   │   │   └── eye.mp4            # 交互动画
│   │   │   └── rawfile/               # 原始文件资源
│   │   └── module.json5               # 模块配置（权限/能力声明）
│   └── build-profile.json5            # 构建配置
├── hvigor/                             # 构建工具
└── AppScope/                           # 应用级配置与图标
```

---

## 🚀 快速开始

### 环境要求

- **HarmonyOS SDK**: API 11+（基于 6.1.0 模型版本）
- **DevEco Studio**: 5.0.0+
- **硬件**: Ring Control 智能指环（星闪版）；支持星闪的 HarmonyOS 手机

### 构建运行

```bash
# 1. 使用 DevEco Studio 打开项目

# 2. 同步依赖 & 构建
# Build > Build HAP(s)

# 3. 安装到设备后运行
# 确保 Ring Control 设备已开机并处于星闪广播状态
# 进入 App > 点击「开始扫描」> 选择设备 > 进入控制页
#
# 4. 演示「骑行 AI 助手」：在 entry/.../common/Config.ets 中填入 DEEPSEEK_API_KEY
```

### 使用流程

```
App 启动 → 扫描星闪设备 → 选择 Ring Control → 连接成功
                                                │
                        ┌───────────────────────┤
                        ▼                       ▼
              读取 GATT 服务列表          订阅属性通知
                        │                       │
                        ▼                       ▼
              通用 SSAP 读/写/订阅（十六进制载荷）   属性通知回调
                        │
                        ▼
              日志面板：定位、防窥、安全检测与 AI 等状态
```

---

## 🔧 开源场景化能力

| 组件 | 说明 | 可复用场景 |
|------|------|-----------|
| `CertChain` | PEM 证书链解析、PKIX 验证、ECC256 公钥提取 | TEE 证明链 / 可复用于需 PKIX 的 IoT 身份场景 |
| `AntiPeepUtils` | DLP 防窥蒙层封装（开关检测/状态监听/遮罩设置） | 金融/医疗等隐私 App |
| `SafetyDetectModel` | 系统完整性 + URL 威胁检测统一封装 | 所有需要安全检测的应用 |
| `SLE Helper` | 星闪扫描/连接/读写/订阅全流程封装 | IoT 近场通信应用 |
| `BleDiscovery` | `access` 开关检测 + `ble.startBLEScan` 周边发现 | 可穿戴 / 传感器 BLE 发现 |

---

## 📄 开源协议

本项目基于 Apache License 2.0 开源。

---

## 👨‍💻 开发团队

- **YEDALL LIMITED**
- **作者**: Reed Xia
- **官网**: [https://yedall.com](https://yedall.com)

---

## 📸 界面概览

| 首页 · 设备连接 | 星闪 / AI / 设置 | 设置 · 安全面板 |
|:---:|:---:|:---:|
| 设备卡片 + 动效 + 日志 | 扫描列表 + **骑行 AI 助手**（流式对话） | 定位精度 / 防窥 / 关于与 URL 检测 |

---

<p align="center">
  <sub>Built with ❤️ on HarmonyOS | 让骑行更安全、更自由</sub>
</p>
