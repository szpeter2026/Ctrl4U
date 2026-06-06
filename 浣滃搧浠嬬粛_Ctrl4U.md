# Ctrl4U — 2026 HarmonyOS 创新赛 · 极客赛道 作品介绍

**作品名称**：Ctrl4U  
**应用包名**：com.yedall.ctrl4u  
**目标系统**：HarmonyOS 6.x（工程 `targetSdkVersion`：6.1.0(23)）

本文档按赛事「作品内容」要求组织，并与当前仓库源码实现状态对齐（见文末「实现状态表」）。

---

## 〇、初赛提交策略与决赛战队规划（简述）

| 阶段 | 策略 |
|------|------|
| **初赛** | 以本仓库 **Ctrl4U 精简包** 为主提交物，**突出 NearLink / 星闪 SSAP 与实物可穿戴（指环）闭环演示**，评委可在短片中快速建立「硬件 + 鸿蒙原生近场」认知。 |
| **四方向补短** | 在精简范围内同时举证 **安全隐私**、**全场景协同**（星闪 + BLE）、**AI**、**3D 空间化**（`Hero3D` + **官方 AR/AI 安全眼镜路线见 README**）。决赛前再与 **YeDall / Ctrl4U-HarmonyOS** 全栈仓合并能力。 |
| **决赛** | 两队集成为「最佳战队」：近场与可穿戴主线保留，叠加 NFC、服务卡片、后端 IoT、叙事材料等，形成 **初赛钩子 → 决赛放大** 的递进叙事。 |

---

## 一、创新场景与体验提升

Ctrl4U 面向骑行与运动影像场景：在双手不离把的前提下，通过近场通信与安全能力，降低「操作手机」带来的分心风险，并为位置与访问链路提供可验证的安全增强。

**体验上的提升包括：**

1. **近场可控**：基于 HarmonyOS **NearLinkKit / 星闪 SSAP** 完成扫描、连接、服务发现、特征读/写与订阅，可在实机上对接外围设备做指令验证。  
2. **安全可感知**：集成 **DeviceSecurityKit**（URL 威胁检测、防窥状态与系统蒙层、安全地理位置与 TEE 侧证明链校验），在设置与关于流程中可演示。  
3. **智能可对话**：内置 **DeepSeek SSE 流式**骑行助手，支持骑行安全、设备使用与跟拍相关问答（需在 `Config.ets` 配置 API Key）。  
4. **多设备形态声明**：`module.json5` 声明 phone / tablet / wearable / tv / car，便于同一套应用在多终端形态上扩展。  
5. **空间与视觉演进**：初赛以 `Hero3D` 呈现骑行装备拓扑；后续对接鸿蒙 **官方 AR / 空间感知** 能力，适配 **AI 安全眼镜等可穿戴**，做 **道路环境感知与轻量辅助预警**（可理解为 **「智驾能力在骑行场景的轻量化微缩」**），与近场、安全定位形成同一主线——**辅助感知，不替代**道路交通安全责任。

---

## 二、产品受众、场景与痛点

| 维度 | 说明 |
|------|------|
| **核心受众** | 城市通勤与运动骑行用户；对安全与隐私敏感、同时有影像记录需求的用户。 |
| **使用场景** | 骑行前/骑行中：近场连接指环类外设；途中需要快速确认定位与安全状态；需要轻量智能问答辅助决策。 |
| **解决的痛点** | 脱把操作手机风险；公共场景下屏幕被窥视；访问外部链接前的钓鱼风险；对「位置类凭证」有防篡改诉求时的可信增强。 |

---

## 三、HarmonyOS 能力集成与技术方案概述

### 3.1 已集成的开放能力与特性

| 能力方向 | 鸿蒙能力 / Kit | 工程中的落点 |
|----------|----------------|----------------|
| 安全隐私保护 | DeviceSecurityKit（safetyDetect、trustedAppService、dlpAntiPeep） | `SafetyDetectModel.ts`、`SecureLocation.ets`、`AntiPeepUtils.ets`；关于官网前 `checkUrlThreat` |
| 安全隐私保护 | CryptoArchitectureKit（ECC256 校验） | `SecureLocation.ets`、`SecureCamera.ets` 与 `CertChain.ets` 协同 |
| 全场景一体协同 | NearLinkKit（scan / ssap / manager） | `sle/helper.ts`、`SleScanTabContent.ets`、`SleDevicePage.ets` |
| AI 智能化体验 | NetworkKit HTTP + 自研 SSE 解析 | `SseClient.ets`、`Index.ets` 聊天页 |
| 多设备 | module 级 deviceTypes | `entry/src/main/module.json5` |

### 3.2 规范与可维护性

- 分层清晰：页面 / 服务（SSE）/ 模型（安全）/ 近场封装（SLE）/ 通用工具（防窥、证书链）。  
- 权限与能力在 `module.json5`、`build-profile.json5` 的 capabilities 中与 DeviceSecurityKit、NearLink 等声明一致。  
- README 增加「能力实现状态」表，避免文档与源码不一致。

### 3.3 可开源共享的技术组件

详见仓库 README「开源场景化能力」：`CertChain`、`AntiPeepUtils`、`SafetyDetectModel`、`SLE Helper` 等均可独立复用。

---

## 四、构建、签名与提交清单（P0）

以下需在 **DevEco Studio** 与赛事提交页完成；仓库内不存放密钥材料。

1. **签名配置**  
   - 在 DevEco 中配置 Release/Debug 签名（`build-profile.json5` 当前 `signingConfigs` 为空，需在 IDE「签名配置」中关联证书，再执行 **Build HAP(s)**）。  
   - **切勿**将 `.p12`、私钥密码、`.csr` 或 API Key 打入提交 ZIP。

2. **AI 演示密钥**  
   - 在 `entry/src/main/ets/common/Config.ets` 的 `DEEPSEEK_API_KEY` 填入有效密钥后，「骑行 AI 助手」页即可流式对话。  
   - 未配置时应用会提示错误，不影响星闪与安全能力演示。

3. **演示视频（1–3 分钟）建议镜头**  
   - 星闪：授权 → 扫描 → 连接 → 设备页一次读/写或订阅。  
   - 安全：设置中精度模式与安全定位日志；防窥相关开关与日志（若设备支持）；冷启动日志中的**系统完整性**一行。  
   - **TEE 安全相机**：Ring Control →「TEE 安全相机演示」→ 预览建立成功或失败提示（展示已接入 DeviceSecurityKit 链路）。  
   - AI：打开 AI 页，发送一条与骑行安全相关的问题，展示流式回复。  
   - 可选：关于我们 → 访问官网，展示 URL 检测通过后再打开浏览器。

4. **ZIP 附件（≤200MB）**  
   - 命名示例：`2026 HarmonyOS 创新赛·极客赛道-Ctrl4U.zip`  
   - 内含：可安装 **HAP**（或构建产物说明）、**本作品介绍**、**演示视频链接或文件**、README。  
   - **排除**：密钥仓库、本地签名配置中的敏感路径截图、含 API Key 的 Config 备份。

---

## 五、实现状态表（与源码一致，便于评委核对）

| 能力 | 状态 |
|------|------|
| 星闪扫描 / 连接 / SSAP 读·写·订阅 | ✅ |
| URL 威胁检测、防窥工具与主窗同步 | ✅ |
| 安全地理位置 + 证明链校验（CertChain） | ✅ |
| 骑行 AI SSE（DeepSeek） | ✅（需 API Key） |
| Ring 模式开关 → 固定指令 UUID 映射 | 🔜 待固件协议与 UUID |
| App 内蓝牙发现/连接（备选通道） | ✅ BLE 扫描 | `BleDiscovery.ets` + 首页「+」约 12s 扫描日志；并打开系统设置 |
| SecureCamera 与业务页集成 | ✅ 演示入口 | Ring Control →「TEE 安全相机演示」；完整抓拍链路见 `SecureCamera.ets` |
| 系统完整性检测 (`checkSysIntegrity`) | ✅ 冷启动执行，日志可验 |
| Hero3D 骑行 3D 拓扑 | ✅ 环绕动效 + 俯视角 + 暂停/继续（ArkUI 变换） |

---

## 六、演示素材与仓库说明

- 视频素材文件名见仓库根目录 `README.md`（如 `10-360p.mp4`、`20-360p.mp4`）。  
- 赛事规则全文见 `2026harmony.md`（组委会原文摘录）。

---

*文档版本与仓库 README「能力实现状态」保持同步维护。*
