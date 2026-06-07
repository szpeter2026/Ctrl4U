import { abilityAccessCtrl, bundleManager, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { promptAction, router, window } from '@kit.ArkUI';
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { SleScanTabContent } from './SleScanTabContent';
import safetyDetectModel from '../model/SafetyDetectModel';
import secureLocationService from '../model/SecureLocation';
import {
  AntiPeepCallback,
  canUseAntiPeep,
  isAntiPeepOn,
  listenOffAntiPeepStatus,
  listenOnAntiPeepStatus,
  showSystemMaskLayer,
} from '../common/utils/AntiPeepUtils';
import { Hero3D } from '../components/Hero3D';
import { SseClient, SseCallbacks, SseState } from '../services/SseClient';
import { Config } from '../common/Config';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  isBluetoothAdapterOn,
  requestBleScanPermissions,
  startBleDeviceScan,
  stopBleDeviceScan,
  BleFoundDevice
} from '../common/BleDiscovery';
interface Want {
  action: string;
  uri?: string;
  entities?: string[];
  /** 部分系统版本解析 https 外链时需要，便于路由到浏览器 */
  type?: string;
}

interface DeviceItem {
  name: string;
  sliderValue: number;
}

interface WindowProperties {
  id?: number;
  windowId?: number;
}

// ── AI 助手类型定义 ──
interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
  time: string
}

enum AiStatus {
  IDLE = 'idle',
  CONNECTING = 'connecting',
  STREAMING = 'streaming',
  ERROR = 'error'
}

enum VoiceStatus {
  IDLE = 'idle',             // 等待用户说话
  REQUESTING_MIC = 'mic',    // 正在请求麦克风权限
  LISTENING = 'listening',   // 正在聆听
  TRANSCRIBING = 'transcribing', // 识别中
  ERROR = 'error'            // 识别失败
}

const DEFAULT_DEVICE_LIST: DeviceItem[] = [
  { name: 'Ring Key', sliderValue: 48 }
];

const ABOUT_APP_LABEL = 'Ctrl4U';
/** 防窥蒙层开关与关于页展示的官网 */
const ABOUT_WEBSITE_HUMAN = 'https://yedall.com';

@Entry
@Component
struct Index {
  private hasRequestedStartupLocation: boolean = false;
  /** 一次「+」触发的 BLE 扫描去重 id */
  private bleScanSeenIds: string[] = [];
  private bleAutoStopTimerId: number = -1;
  /** 冷启动跑一次系统完整性检测 */
  private hasRunSysIntegrityProbe: boolean = false;
  private isListenOn: boolean = false;
  @State findDeviceEnabled: boolean = false;
  @State restorePageEnabled: boolean = false;
  @State privacyShieldEnabled: boolean = false;
  @State pageRestoreEnabled: boolean = false;
  @State currentTab: number = 0;
  /** 精度优先：用于冷启动 GPS / DeviceSecurityKit 安全定位策略（默认关闭，速度优先） */
  @State locationPriorityAccuracyModeOn: boolean = false;
  /** Ring Control 全屏页显隐（与定位精度开关分离，避免误进 Ring 页） */
  @State showRingControlPage: boolean = false;
  @State entertainmentModeOn: boolean = true;
  @State exerciseModeOn: boolean = true;
  @State mouseModeOn: boolean = true;
  @State legacyDevices: DeviceItem[] = [];
  @State appVersionName: string = '';
  // 性能优化：延迟初始化视频控制器，减少启动时间
  private standVideoController: VideoController | null = null;
  @State mainVideoSrc: Resource | null = null;
  @State mainVideoLoop: boolean = true;
  @State isVideoInitialized: boolean = false;
  @State runClipPlaybackActive: boolean = false;
  /** +按钮忙碌动画状态：点击后显示LoadingProgress，3秒后弹出消息并恢复 */
  @State plusButtonBusy: boolean = false;
  @State logLines: string[] = [
    '[INFO] 应用启动完成',
    '[INFO] 页面初始化完成',
    '[DEBUG] 等待设备连接...'
  ];

  // ── AI 助手状态 ──
  @State chatMessages: ChatMessage[] = [];
  @State isAiStreaming: boolean = false;
  @State aiStatus: AiStatus = AiStatus.IDLE;

  // ── 语音输入状态 ──
  @State voiceStatus: VoiceStatus = VoiceStatus.IDLE;
  @State isVoiceListening: boolean = false;
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private voiceSessionId: string = '';

  private appendLog(level: 'INFO' | 'DEBUG' | 'WARN' | 'ERROR', message: string): void {
    const now = new Date();
    const stamp =
      `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds()
        .toString()
        .padStart(2, '0')}`;
    const next = [...this.logLines, `[${stamp}] [${level}] ${message}`];
    this.logLines = next.length > 200 ? next.slice(next.length - 200) : next;

  }

  /** 延迟初始化视频资源 - 性能优化 */
  private initVideoResources(): void {
    if (this.isVideoInitialized) return;
    
    this.standVideoController = new VideoController();
    this.mainVideoSrc = $rawfile('stand.mp4');
    this.isVideoInitialized = true;
  }

  /** DeviceSecurityKit.checkSysIntegrity — 延迟到后台执行，避免阻塞启动 */
  private runStartupSysIntegrityProbe(): void {
    // 性能优化：延迟3秒执行，不阻塞UI渲染
    setTimeout(() => {
      if (this.hasRunSysIntegrityProbe) return;
      this.hasRunSysIntegrityProbe = true;
      
      safetyDetectModel.checkSysIntegrity((result: String) => {
        const text = `${result}`;
        if (text.indexOf('failed') >= 0 || text.indexOf('errCode') >= 0) {
          this.appendLog('WARN', `系统完整性: ${text}`);
        } else {
          this.appendLog('INFO', `系统完整性检测已完成（应答长度 ${text.length}）`);
        }
      });
    }, 3000);
  }

  // ── AI 助手方法 ──
  private getTimeStamp(): string {
    const now = new Date();
    return `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;
  }

  private addChatMessage(role: 'user' | 'assistant', content: string): void {
    this.chatMessages = [...this.chatMessages, {
      role,
      content,
      time: this.getTimeStamp()
    }];
  }

  // 纯语音发送 — 戒指设备无键盘，语音识别后直接调用
  private sendVoiceMessage(msg: string): void {
    if (!Config.hasApiKey) {
      promptAction.showToast({ message: '请先在 entry/src/main/ets/common/Config.ets 填入 DEEPSEEK_API_KEY' });
      return;
    }
    if (!msg || this.isAiStreaming) return;

    this.addChatMessage('user', msg);
    this.isAiStreaming = true;
    this.aiStatus = AiStatus.CONNECTING;
    this.voiceStatus = VoiceStatus.IDLE;
    this.appendLog('INFO', `🎤 语音 → DeepSeek: "${msg.substring(0, 20)}..."`);

    const callbacks: SseCallbacks = {
      onToken: (token: string) => {
        const msgs = [...this.chatMessages];
        const lastIdx = msgs.length - 1;
        if (lastIdx >= 0 && msgs[lastIdx].role === 'assistant') {
          msgs[lastIdx] = { role: 'assistant', content: msgs[lastIdx].content + token, time: msgs[lastIdx].time };
          this.chatMessages = msgs;
        }
      },
      onDone: (fullText: string, _conversationId: string) => {
        this.isAiStreaming = false;
        this.aiStatus = AiStatus.IDLE;
        const msgs = [...this.chatMessages];
        const lastIdx = msgs.length - 1;
        if (lastIdx >= 0 && msgs[lastIdx].role === 'assistant') {
          msgs[lastIdx] = { role: 'assistant', content: fullText || msgs[lastIdx].content, time: msgs[lastIdx].time };
          this.chatMessages = msgs;
        }
        this.appendLog('INFO', `← DeepSeek 完成 (${fullText.length} 字)`);
        if (!fullText) {
          promptAction.showToast({ message: 'DeepSeek 返回空响应，请检查 API Key 或网络', duration: 3000 });
        }
      },
      onError: (err: Error) => {
        this.isAiStreaming = false;
        this.aiStatus = AiStatus.ERROR;
        const msgs = [...this.chatMessages];
        const lastIdx = msgs.length - 1;
        if (lastIdx >= 0 && msgs[lastIdx].role === 'assistant') {
          msgs[lastIdx] = { role: 'assistant', content: `⚠️ ${err.message}`, time: msgs[lastIdx].time };
          this.chatMessages = msgs;
        }
        this.appendLog('ERROR', `× DeepSeek: ${err.message}`);
        promptAction.showToast({ message: err.message, duration: 4000 });
      },
      onStateChange: (state: SseState) => {
        this.aiStatus = state === SseState.STREAMING ? AiStatus.STREAMING :
                         state === SseState.CONNECTING ? AiStatus.CONNECTING :
                         state === SseState.ERROR ? AiStatus.ERROR : AiStatus.IDLE;
      }
    };

    // 先添加一个空的 assistant 消息槽位
    this.addChatMessage('assistant', '思考中...');

    SseClient.streamChat(msg, null, callbacks);
  }

  // ── 语音输入方法 ──
  private async requestMicrophonePermission(): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      return result.authResults[0] === 0;
    } catch (_e) {
      return false;
    }
  }

  private async startVoiceInput(): Promise<void> {
    if (this.isVoiceListening || this.isAiStreaming) return;
    if (!Config.hasApiKey) {
      promptAction.showToast({ message: '请先配置 DeepSeek API Key' });
      return;
    }

    this.voiceStatus = VoiceStatus.REQUESTING_MIC;
    const hasMic = await this.requestMicrophonePermission();
    if (!hasMic) {
      this.voiceStatus = VoiceStatus.ERROR;
      promptAction.showToast({ message: '需要麦克风权限才能使用语音输入' });
      return;
    }

    try {
      this.asrEngine = await speechRecognizer.createEngine({
        language: 'zh-CN',
        online: 1,
        extraParams: { 'locate': 'CN', 'recognizerMode': 'short' }
      });

      this.voiceSessionId = 'ctrl4u_voice_' + Date.now();
      let resultText = '';

      this.asrEngine.setListener({
        onStart: (_sessionId: string, _eventMessage: string) => {
          this.isVoiceListening = true;
          this.voiceStatus = VoiceStatus.LISTENING;
          this.appendLog('INFO', '语音识别已启动');
        },
        onEvent: (_sessionId: string, _eventCode: number, _eventMessage: string) => {
          // 中间事件，无需处理
        },
        onResult: (_sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
          resultText = result.result;
        },
        onComplete: (_sessionId: string, _eventMessage: string) => {
          this.isVoiceListening = false;
          this.voiceStatus = VoiceStatus.TRANSCRIBING;
          this.appendLog('INFO', `语音识别完成: "${resultText}"`);
          if (resultText.trim()) {
            this.sendVoiceMessage(resultText.trim());
          } else {
            this.voiceStatus = VoiceStatus.IDLE;
            promptAction.showToast({ message: '未识别到语音内容，请重试' });
          }
        },
        onError: (_sessionId: string, errorCode: number, errorMessage: string) => {
          this.isVoiceListening = false;
          this.voiceStatus = VoiceStatus.ERROR;
          this.appendLog('ERROR', `语音识别错误 [${errorCode}]: ${errorMessage}`);
          promptAction.showToast({ message: '语音识别失败，请重试' });
        }
      });

      this.asrEngine.startListening({
        sessionId: this.voiceSessionId,
        audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 },
        extraParams: {
          'recognitionMode': 0,
          'vadBegin': 2000,
          'vadEnd': 1000,
          'maxAudioDuration': 30000
        }
      });
    } catch (err) {
      this.isVoiceListening = false;
      this.voiceStatus = VoiceStatus.ERROR;
      const msg = (err as BusinessError).message || JSON.stringify(err);
      this.appendLog('ERROR', `语音引擎启动失败: ${msg}`);
      promptAction.showToast({ message: '语音识别不可用（可能需要真机）' });
    }
  }

  private stopVoiceInput(): void {
    try {
      this.asrEngine?.finish(this.voiceSessionId);
    } catch (_e) { /* 忽略 */ }
    this.isVoiceListening = false;
    this.voiceStatus = VoiceStatus.IDLE;
  }

  // 语音按钮图标
  private getMicIcon(): string {
    switch (this.voiceStatus) {
      case VoiceStatus.REQUESTING_MIC: return '🔐';
      case VoiceStatus.LISTENING: return '⏺';
      case VoiceStatus.TRANSCRIBING: return '📝';
      case VoiceStatus.ERROR: return '⚠️';
      default: return '🎤';
    }
  }

  // 语音按钮提示文字
  private getVoiceHint(): string {
    switch (this.voiceStatus) {
      case VoiceStatus.REQUESTING_MIC: return '请求权限...';
      case VoiceStatus.LISTENING: return '正在聆听...';
      case VoiceStatus.TRANSCRIBING: return '识别中...';
      case VoiceStatus.ERROR: return '点击重试';
      default: return '轻触说话';
    }
  }

  private async requestLocationPermissions(): Promise<boolean> {
    const permissions: Permissions[] = [
      'ohos.permission.LOCATION',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ];
    this.appendLog('INFO', '开始申请定位权限');
    promptAction.showToast({ message: '正在申请定位权限...' });

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(context, permissions) as PermissionRequestResult;
      const denied: string[] = [];
      result.authResults.forEach((auth: number, index: number) => {
        if (auth !== 0) {
          denied.push(permissions[index]);
        }
      });

      if (denied.length > 0) {
        this.appendLog('WARN', `定位权限被拒绝: ${denied.join(', ')}`);
        promptAction.showToast({ message: '定位权限被拒绝，无法获取GPS信息' });
        return false;
      }

      this.appendLog('INFO', '定位权限已授权');
      promptAction.showToast({ message: '定位权限授权成功' });
      return true;
    } catch (err) {
      this.appendLog('ERROR', `定位权限申请失败: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '定位权限申请失败' });
      return false;
    }
  }

  private antiPeepCB: AntiPeepCallback = {
    onStatusChanged: async (status: dlpAntiPeep.DlpAntiPeepStatus): Promise<void> => {
      await this.handleAntiPeepStatus(status);
    }
  }

  /**
   * 当系统防窥开关打开（isDlpAntiPeepSwitchOn）时，为主窗口设置系统防窥遮罩层。
   * @param force 为 true 时跳过 isAntiPeepOn 检测，直接设置遮罩（用于运行时窥屏回调触发）。
   */
  private async syncAntiPeepMaskFromSwitch(force: boolean = false): Promise<void> {
    if (!canUseAntiPeep()) {
      return;
    }
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const win = await window.getLastWindow(ctx);
      const p = win.getWindowProperties() as WindowProperties;
      const wid = p.id ?? p.windowId;
      if (wid === undefined || wid < 0) {
        this.appendLog('WARN', '防窥遮罩：无法取得窗口 id');
        return;
      }
      const shouldApply = force || await isAntiPeepOn();
      if (shouldApply) {
        const ok = await showSystemMaskLayer(wid);
        this.appendLog('INFO', ok ? '防窥遮罩层已设置' : '防窥遮罩层设置失败');
      } else {
        this.appendLog('DEBUG', '防窥开关未开：不显示系统遮罩层');
      }
    } catch (e) {
      this.appendLog('WARN', `同步防窥遮罩失败: ${JSON.stringify(e)}`);
    }
  }

  /**
   * handle screen privacy status
   * */
  private async handleAntiPeepStatus(status: dlpAntiPeep.DlpAntiPeepStatus) {
    await this.syncAntiPeepMaskFromSwitch();
    switch (status) {
      case dlpAntiPeep.DlpAntiPeepStatus.PASS:
        this.appendLog('INFO', '防窥检测：正常显示');
        break;
      case dlpAntiPeep.DlpAntiPeepStatus.HIDE:
        this.appendLog('WARN', '防窥检测：窥屏风险，隐藏内容');
        if (this.showRingControlPage) {
          this.appendLog('WARN', 'Ring Control 页面正展示中，强制启用防窥遮罩层');
          await this.syncAntiPeepMaskFromSwitch(true);
        }
        break;
      default:
        this.appendLog('DEBUG', `防窥检测：其它状态 ${status}`);
        break;
    }
  }

  private async fetchCurrentLocationOnStartup(): Promise<void> {
    if (!(await this.requestLocationPermissions())) {
      return;
    }

    const accuracyFirst = this.locationPriorityAccuracyModeOn;
    this.appendLog(
      'INFO',
      accuracyFirst ? '定位策略：精度优先 + 安全地理位置（DeviceSecurityKit）' : '定位策略：速度优先（FIRST_FIX）+ 安全地理位置（DeviceSecurityKit）'
    );
    try {
      const requestInfo: geoLocationManager.CurrentLocationRequest = accuracyFirst
        ? {
          priority: geoLocationManager.LocationRequestPriority.ACCURACY,
          scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
          maxAccuracy: 10,
          timeoutMs: 10000
        }
        : {
          priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
          scenario: geoLocationManager.LocationRequestScenario.UNSET,
          maxAccuracy: 100,
          timeoutMs: 10000
        };

      const location = await new Promise<geoLocationManager.Location>((resolve, reject) => {
        geoLocationManager.getCurrentLocation(requestInfo, (err, current) => {
          if (err) {
            reject(err);
            return;
          }
          resolve(current);
        });
      });

      this.appendLog('INFO', `GPS定位成功: lat=${location.latitude}, lng=${location.longitude}`);

      if (accuracyFirst) {
        try {
          const secureJson = await secureLocationService.getVerifiedSecureLocationAccuracyPriority();
          this.appendLog('INFO', `安全地理位置验证成功（精度优先）: ${secureJson}`);
        } catch (secureErr) {
          this.appendLog('WARN', `安全地理位置未完成（设备/能力或证书链）: ${JSON.stringify(secureErr)}`);
        }
      } else {
        try {
          const secureJson = await secureLocationService.getVerifiedSecureLocationSpeedPriority();
          this.appendLog('INFO', `安全地理位置验证成功（速度优先）: ${secureJson}`);
        } catch (secureErr) {
          this.appendLog('WARN', `安全地理位置未完成（设备/能力或证书链）: ${JSON.stringify(secureErr)}`);
        }
      }
    } catch (err) {
      this.appendLog('ERROR', `GPS定位失败: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '获取GPS定位失败' });
    }
  }

  /**
   * 精度模式开关打开时触发：发起精度优先的安全地理位置定位流程。
   * 与冷启动定位独立，允许运行时重复调用。
   */
  private async performAccuracyFirstLocation(): Promise<void> {
    this.appendLog('INFO', '========== 精度优先安全定位开始 ==========');

    const hasPermission = await this.requestLocationPermissions();
    if (!hasPermission) {
      this.appendLog('WARN', '定位权限未授予，无法执行精度优先安全定位');
      return;
    }

    this.appendLog('INFO', '定位策略：精度优先 + 安全地理位置（DeviceSecurityKit）');

    try {
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.ACCURACY,
        scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
        maxAccuracy: 10,
        timeoutMs: 10000
      };

      this.appendLog('DEBUG', `GPS请求参数: ACCURACY + NAVIGATION, maxAccuracy=10, timeout=10000ms`);
      const location = await new Promise<geoLocationManager.Location>((resolve, reject) => {
        geoLocationManager.getCurrentLocation(requestInfo, (err, current) => {
          if (err) {
            reject(err);
            return;
          }
          resolve(current);
        });
      });

      this.appendLog(
        'INFO',
        `GPS定位成功: lat=${location.latitude.toFixed(6)}, lng=${location.longitude.toFixed(6)}, accuracy=${location.accuracy}m`
      );
      this.appendLog('DEBUG', `GPS原始数据: ${JSON.stringify(location)}`);

      try {
        this.appendLog('INFO', '开始安全地理位置验证（DeviceSecurityKit 精度优先）...');
        const secureJson = await secureLocationService.getVerifiedSecureLocationAccuracyPriority();
        this.appendLog('INFO', `安全地理位置验证成功（精度优先）: ${secureJson}`);
      } catch (secureErr) {
        this.appendLog(
          'WARN',
          `安全地理位置未完成（设备/能力或证书链）: ${JSON.stringify(secureErr)}`
        );
      }
    } catch (locErr) {
      this.appendLog('ERROR', `GPS定位失败: ${JSON.stringify(locErr)}`);
      promptAction.showToast({ message: 'GPS定位失败，请检查定位开关和权限' });
    }

    this.appendLog('INFO', '========== 精度优先安全定位结束 ==========');
  }

  /**
   * 精度模式开关关闭时触发：发起速度优先的安全地理位置定位流程。
   * 使用 FIRST_FIX 快速策略 + DeviceSecurityKit 速度优先安全定位。
   */
  private async performSpeedFirstLocation(): Promise<void> {
    this.appendLog('INFO', '========== 速度优先安全定位开始 ==========');

    const hasPermission = await this.requestLocationPermissions();
    if (!hasPermission) {
      this.appendLog('WARN', '定位权限未授予，无法执行速度优先安全定位');
      return;
    }

    this.appendLog('INFO', '定位策略：速度优先（FIRST_FIX）+ 安全地理位置（DeviceSecurityKit）');

    try {
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.UNSET,
        maxAccuracy: 100,
        timeoutMs: 10000
      };

      this.appendLog('DEBUG', `GPS请求参数: FIRST_FIX + UNSET, maxAccuracy=100, timeout=10000ms`);
      const location = await new Promise<geoLocationManager.Location>((resolve, reject) => {
        geoLocationManager.getCurrentLocation(requestInfo, (err, current) => {
          if (err) {
            reject(err);
            return;
          }
          resolve(current);
        });
      });

      this.appendLog(
        'INFO',
        `GPS定位成功: lat=${location.latitude.toFixed(6)}, lng=${location.longitude.toFixed(6)}, accuracy=${location.accuracy}m`
      );
      this.appendLog('DEBUG', `GPS原始数据: ${JSON.stringify(location)}`);

      try {
        this.appendLog('INFO', '开始安全地理位置验证（DeviceSecurityKit 速度优先）...');
        const secureJson = await secureLocationService.getVerifiedSecureLocationSpeedPriority();
        this.appendLog('INFO', `安全地理位置验证成功（速度优先）: ${secureJson}`);
      } catch (secureErr) {
        this.appendLog(
          'WARN',
          `安全地理位置未完成（设备/能力或证书链）: ${JSON.stringify(secureErr)}`
        );
      }
    } catch (locErr) {
      this.appendLog('ERROR', `GPS定位失败: ${JSON.stringify(locErr)}`);
      promptAction.showToast({ message: 'GPS定位失败，请检查定位开关和权限' });
    }

    this.appendLog('INFO', '========== 速度优先安全定位结束 ==========');
  }

  private async startBluetoothPairing(): Promise<void> {
    this.appendLog('INFO', '「+」：ConnectivityKit BLE 扫描 + 系统蓝牙设置');

    const powered = isBluetoothAdapterOn();
    this.appendLog('INFO', `蓝牙适配器: ${powered ? '已开启' : '未开启或不可用'}`);

    const context = getContext(this) as common.UIAbilityContext;
    const granted = await requestBleScanPermissions(context);
    if (!granted) {
      this.appendLog('WARN', '蓝牙扫描权限未全部授予，跳过 BLE 扫描');
    } else if (powered) {
      this.bleScanSeenIds = [];
      stopBleDeviceScan();
      if (this.bleAutoStopTimerId >= 0) {
        clearTimeout(this.bleAutoStopTimerId);
        this.bleAutoStopTimerId = -1;
      }

      const started = startBleDeviceScan((d: BleFoundDevice) => {
        if (this.bleScanSeenIds.indexOf(d.deviceId) >= 0) {
          return;
        }
        this.bleScanSeenIds.push(d.deviceId);
        const cap = 24;
        if (this.bleScanSeenIds.length <= cap) {
          this.appendLog('INFO', `BLE: ${d.deviceName} | ${d.deviceId} | RSSI ${d.rssi}`);
        } else if (this.bleScanSeenIds.length === cap + 1) {
          this.appendLog('INFO', `BLE: 已达日志上限 ${cap} 条，后续设备略`);
        }
      });

      if (started) {
        this.appendLog('INFO', 'BLE 扫描已启动（约 12 秒后自动停止）');
        this.bleAutoStopTimerId = setTimeout(() => {
          stopBleDeviceScan();
          this.bleAutoStopTimerId = -1;
          this.appendLog('INFO', `BLE 扫描结束，共发现 ${this.bleScanSeenIds.length} 个不同设备 id`);
        }, 12000) as number;
      } else {
        this.appendLog('WARN', 'BLE 扫描未能启动（可能已在扫描或系统异常）');
      }
    }

    const want: Want = { action: 'ohos.settings.intent.action.BLUETOOTH_SETTINGS' };
    try {
      await context.startAbility(want);
      this.appendLog('INFO', '已打开系统蓝牙设置（可继续配对）');
    } catch (err) {
      this.appendLog('ERROR', `打开系统蓝牙设置失败: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '无法打开蓝牙设置，请手动进入系统设置配对' });
    }
  }

  /** 与 AppScope app.versionName 同步，供设置页与关于对话框使用 */
  private async refreshAppVersionLabel(): Promise<void> {
    try {
      const info =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.appVersionName = info.versionName;
    } catch (err) {
      this.appendLog('WARN', `读取版本号失败: ${JSON.stringify(err)}`);
      if (this.appVersionName.length === 0) {
        this.appVersionName = '—';
      }
    }
  }

  /**
   * 「关于我们」：展示应用信息与入口；官网 URL 威胁检测在后台执行并写入日志，不作为主界面反馈。
   */
  private async openAboutUs(): Promise<void> {
    await this.refreshAppVersionLabel();
    const ver = this.appVersionName.length > 0 ? this.appVersionName : '—';
    try {
      const dialogResult = await promptAction.showDialog({
        title: '关于我们',
        message:
          `${ABOUT_APP_LABEL}\n版本 ${ver}\n\n智能穿戴设备配套应用。\n官网：${ABOUT_WEBSITE_HUMAN}`,
        buttons: [
          { text: '关闭', color: '#182431' },
          { text: '访问官网', color: '#007DFF' }
        ]
      });
      if (dialogResult.index === 1) {
        // URL 安全检查前置：先检测再决定是否打开浏览器
        const isSafe = await this.checkAboutWebsiteSafety();
        if (isSafe) {
          await this.openUserManual();
        } else {
          this.appendLog('WARN', '官网链接安全检测未通过，已拦截打开');
          promptAction.showToast({ message: '官网链接安全检测未通过，已拦截' });
        }
      }
    } catch (err) {
      this.appendLog('ERROR', `关于我们对话框失败: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '无法打开关于信息，请稍后重试' });
    }
  }

  /**
   * 对官网 URL 进行安全威胁检测，返回 true 表示安全可访问。
   */
  private async checkAboutWebsiteSafety(): Promise<boolean> {
    const url = ABOUT_WEBSITE_HUMAN;
    try {
      const result = await new Promise<string>((resolve, reject) => {
        safetyDetectModel.checkUrlThreat(resolve, url);
      });
      this.appendLog('INFO', `官网链接安全检测: ${result}`);
      // UrlThreatType: 0=NOT_THREAT 为安全，其余 1=MALWARE 2=PHISHING 3=OTHER 4=UNKNOWN 均为风险
      const threatMatch = result.match(/threat:\s*(\d+)/);
      if (threatMatch) {
        const threat = parseInt(threatMatch[1]);
        return threat === 0; // 仅 NOT_THREAT(0) 视为安全
      }
      // 无法解析结果，保守起见重试一次
      this.appendLog('WARN', '安全检测结果解析失败，默认拦截');
      return false;
    } catch (err) {
      this.appendLog('ERROR', `官网链接安全检测异常: ${JSON.stringify(err)}`);
      // 检测失败时默认拦截，安全优先
      return false;
    }
  }

  /**
   * 关于我们-访问官网：使用系统浏览器打开官网。优先隐式意图（viewData + browsable），失败时再尝试仅 uri + MIME，适配不同 HarmonyOS 版本。
   */
  private async openUserManual(): Promise<void> {
    const url = ABOUT_WEBSITE_HUMAN;
    this.appendLog('INFO', `打开官网: ${url}`);
    const context = getContext(this) as common.UIAbilityContext;

    const primaryWant: Want = {
      action: 'ohos.want.action.viewData',
      uri: url,
      type: 'text/plain',
      entities: ['entity.system.browsable']
    };
    try {
      await context.startAbility(primaryWant);
      promptAction.showToast({ message: '正在打开浏览器…' });
      return;
    } catch (err1) {
      this.appendLog('WARN', `打开官网(隐式意图)失败: ${JSON.stringify(err1)}`);
    }

    const fallbackWant: Want = {
      action: 'ohos.want.action.viewData',
      uri: url,
      type: 'text/plain'
    };
    try {
      await context.startAbility(fallbackWant);
      promptAction.showToast({ message: '正在打开浏览器…' });
    } catch (err2) {
      this.appendLog('ERROR', `打开官网链接失败: ${JSON.stringify(err2)}`);
      promptAction.showToast({ message: '无法在浏览器中打开链接，请稍后重试' });
    }
  }

  private playRunClipOnce(): void {
    this.runClipPlaybackActive = true;
    this.mainVideoSrc = $rawfile('run.mp4');
    this.mainVideoLoop = false;
    this.appendLog('INFO', '视频区播放 run.mp4（单次）');
  }

  private restoreStandVideoLoop(): void {
    this.runClipPlaybackActive = false;
    this.mainVideoSrc = $rawfile('eye.mp4');
    this.mainVideoLoop = true;
  }

  @Builder
  private logPanel() {
    Column() {
      Text('运行与诊断日志')
        .fontSize(14)
        .fontColor('#007DFF')
        .fontWeight(FontWeight.Medium)
        .margin({ left: 12, right: 12, top: 8, bottom: 6 })

      Scroll() {
        Column() {
          ForEach(this.logLines, (line: string, index: number) => {
            Text(line)
              .width('100%')
              .textAlign(TextAlign.Start)
              .fontSize(12)
              .margin({ bottom: 4 })
          }, (line: string, index: number) => `${index}-${line}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.On)
      .scrollBarWidth(6)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#F7F8FA')
  }

  @Builder
  private settingRow(title: string, value?: string) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111111')

      Blank()

      if (value !== undefined) {
        Text(value)
          .fontSize(14)
          .fontColor('#8D8D8D')
      }
    }
    .width('100%')
    .height(72)
    .padding({ left: 20, right: 20 })
    .backgroundColor('#F8F8F8')
  }

  @Builder
  private settingsPage() {
    Column({ space: 8 }) {
      Row() {
        Text('查找设备')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.findDeviceEnabled })
          .onChange((value: boolean) => {
            this.findDeviceEnabled = value;
            this.appendLog('INFO', `设置页-查找设备: ${value ? '开启' : '关闭'}`);
          })
      }
      .width('100%')
      .height(72)
      .padding({ left: 20, right: 20 })
      .backgroundColor('#F8F8F8')

      Row() {
        Text('精度模式')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.locationPriorityAccuracyModeOn })
          .onChange((value: boolean) => {
            this.locationPriorityAccuracyModeOn = value;
            this.appendLog('INFO', `设置页-精度模式: ${value ? '开启' : '关闭'}`);
            if (value) {
              this.performAccuracyFirstLocation();
            } else {
              this.performSpeedFirstLocation();
            }
          })
      }
      .width('100%')
      .height(72)
      .padding({ left: 20, right: 20 })
      .backgroundColor('#F8F8F8')

      Row() {
        Text('防窥蒙层')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.privacyShieldEnabled })
          .onChange((value: boolean) => {
            this.privacyShieldEnabled = value;
            this.appendLog('INFO', `设置页-防窥蒙层: ${value ? '开启' : '关闭'}`);
          })
      }
      .width('100%')
      .height(72)
      .padding({ left: 20, right: 20 })
      .backgroundColor('#F8F8F8')

      Row() {
        Text('关于我们')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#007DFF')
          .onClick(() => {
            void this.openAboutUs();
          })

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.pageRestoreEnabled })
          .onChange((value: boolean) => {
            this.pageRestoreEnabled = value;
            this.appendLog('INFO', `设置页-页面复原: ${value ? '开启' : '关闭'}`);
          })
      }
      .width('100%')
      .height(72)
      .padding({ left: 20, right: 20 })
      .backgroundColor('#F8F8F8')

      this.settingRow('App 版本', this.appVersionName.length > 0 ? this.appVersionName : '—')
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 12, bottom: 0 })
    .backgroundColor('#F8F8F8')
  }

  @Builder
  private legacyDeviceCard(item: DeviceItem) {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.8'))
          .width(74)
          .height(74)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
          .onClick(() => {
            this.showRingControlPage = true;
            this.appendLog('INFO', '打开 Ring Key 页面');
          })

        Column({ space: 8 }) {
          Text(item.name)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111111')
            .width(88)
            .maxLines(2)
          Image($r('app.media.signal'))
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
        }
        .alignItems(HorizontalAlign.Start)
        .width(88)

        Column({ space: 10 }) {
          Slider({
            value: item.sliderValue,
            min: 0,
            max: 100
          })
            .blockColor('#FFFFFF')
            .trackColor('#DCDCDC')
            .selectedColor('#1E93FF')
            .width('100%')

          Button('已绑定')
            .fontColor('#FFFFFF')
            .fontSize(16)
            .backgroundColor('#A6A7AD')
            .borderRadius(20)
            .width('100%')
            .height(40)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }

  @Builder
  private devicePlaceholderCard() {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.8'))
          .width(74)
          .height(74)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
          .opacity(0.40)

        Column({ space: 8 }) {
          Text('待连接设备')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#999999')
            .maxLines(2)
          Image($r('app.media.signal'))
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
            .opacity(0.40)
        }
        .alignItems(HorizontalAlign.Start)
        .width(88)

        Column({ space: 10 }) {
          Slider({
            value: 0,
            min: 0,
            max: 100
          })
            .blockColor('#FFFFFF')
            .trackColor('#DCDCDC')
            .selectedColor('#B8B8B8')
            .width('100%')
            .enabled(false)

          Button('未连接')
            .fontColor('#FFFFFF')
            .fontSize(16)
            .backgroundColor('#D8D8D8')
            .borderRadius(20)
            .width('100%')
            .height(40)
            .enabled(false)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor('#FAFAFA')
    .borderRadius(18)
    .borderWidth(1)
    .borderColor('#E8E8E8')
  }

  @Builder
  private standVideoPanel() {
    Column({ space: 8 }) {
      Video({
        src: this.mainVideoSrc,
        controller: this.standVideoController
      })
        .width('100%')
        .aspectRatio(16 / 9)
        .controls(true)
        .autoPlay(true)
        .loop(this.mainVideoLoop)
        .objectFit(ImageFit.Contain)
        .backgroundColor('#000000')
        .onFinish(() => {
          if (this.runClipPlaybackActive) {
            this.restoreStandVideoLoop();
          }
        })
        .onError(() => {
          if (this.runClipPlaybackActive) {
            this.appendLog('WARN', 'run.mp4 播放异常，恢复 eye.mp4');
            this.restoreStandVideoLoop();
          }
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 4, bottom: 8 })
  }

  @Builder
  private legacyDefaultPage() {
    Column() {
      Column({ space: 16 }) {
        if (this.legacyDevices.length === 0) {
          this.devicePlaceholderCard();
        } else {
          ForEach(this.legacyDevices, (item: DeviceItem) => {
            this.legacyDeviceCard(item);
          }, (item: DeviceItem, index: number) => `${item.name}-${index}`)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12 })

      Hero3D()

      this.standVideoPanel()

      this.logPanel()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EDEDED')
  }

  @Builder
  private ringControlModeRow(title: string, subtitle: string, isOn: boolean, onChange: (v: boolean) => void) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')
        Text(subtitle)
          .fontSize(12)
          .fontColor('#888888')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor('#34C759')
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private ringControlPage() {
    Column() {
      Row() {
        Text('←')
          .fontSize(22)
          .fontColor(Color.White)
          .padding({ right: 12 })
          .onClick(() => {
            this.showRingControlPage = false;
          })

        Text('Ring Control')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank()
          .width(34)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 48, bottom: 14 })
      .backgroundColor('#007DFF')

      Scroll() {
        Column() {
          Column() {
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 200, height: 200 })
                .fill(Color.Transparent)
                .stroke('#D8D8D8')
                .strokeWidth(10)

              Image($r('app.media.9'))
                .width(110)
                .height(110)
                .objectFit(ImageFit.Cover)
            }
            .margin({ top: 28, bottom: 12 })

            Row({ space: 8 }) {
              Text('62%')
                .fontSize(32)
                .fontColor('#333333')
              Text('▮▮▮▯')
                .fontSize(14)
                .fontColor('#666666')
            }
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .padding({ bottom: 8 })

          Column({ space: 1 }) {
            this.ringControlModeRow('跟拍模式', '无人机，位置', this.entertainmentModeOn, (v: boolean) => {
              this.entertainmentModeOn = v;
              this.appendLog('INFO', `Ring·跟拍模式: ${v ? '开' : '关'}（SSAP 语义指令待固件 UUID）`);
            })
            Divider().color('#F0F0F0').margin({ left: 20, right: 20 })
            this.ringControlModeRow('运动模式', '转向灯，鸣笛', this.exerciseModeOn, (v: boolean) => {
              this.exerciseModeOn = v;
              this.appendLog('INFO', `Ring·运动模式: ${v ? '开' : '关'}（SSAP 语义指令待固件 UUID）`);
            })
            Divider().color('#F0F0F0').margin({ left: 20, right: 20 })
            this.ringControlModeRow('第一视角', '录像，拍照', this.mouseModeOn, (v: boolean) => {
              this.mouseModeOn = v;
              this.appendLog('INFO', `Ring·第一视角: ${v ? '开' : '关'}（可进入下方 TEE 安全相机演示）`);
            })
          }
          .width('100%')

          Button('TEE 安全相机演示')
            .width('100%')
            .margin({ left: 20, right: 20, top: 10 })
            .fontColor(Color.White)
            .backgroundColor('#34C759')
            .onClick(() => {
              router.pushUrl({ url: 'pages/SecureCameraDemoPage' }).catch((e: Error) => {
                this.appendLog('ERROR', `打开安全相机页失败: ${e.message}`);
              });
            })

          Column({ space: 6 }) {
            Text('当前版本')
              .fontSize(14)
              .fontColor('#111111')
            Text('0042')
              .fontSize(36)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111111')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 20, bottom: 20 })
          .backgroundColor('#F3F3F5')
          .margin({ top: 12, bottom: 12 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F5F5F7')

      Button('固件升级')
        .width('100%')
        .height(64)
        .fontSize(24)
        .fontColor('#B5C9EC')
        .backgroundColor('#007DFF')
        .borderRadius(0)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F7')
  }

  // ── AI 骑行助手页 ──
  @Builder
  private aiChatPage() {
    Column() {
      // 标题栏
      Row() {
        Text('🚴')
          .fontSize(20)
        Text('骑行 AI 助手')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')
          .margin({ left: 8 })
        Blank()
        if (this.aiStatus === AiStatus.STREAMING) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color('#007DFF')
        } else if (this.aiStatus === AiStatus.ERROR) {
          Text('⚠️')
            .fontSize(16)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 12 })

      Divider().color('#F0F0F0').margin({ left: 18, right: 18 })

      // 消息列表
      Scroll() {
        Column({ space: 12 }) {
          if (this.chatMessages.length === 0) {
            Column({ space: 8 }) {
              Text('🤖')
                .fontSize(40)
              Text('我是 Ctrl4U 骑行 AI 助手')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333')
              Text('轻触下方 🎤 按钮开始语音对话')
                .fontSize(13)
                .fontColor('#888888')
                .textAlign(TextAlign.Center)
              Text('骑行安全、指环使用、跟拍技巧...随时问我')
                .fontSize(12)
                .fontColor('#AAAAAA')
                .textAlign(TextAlign.Center)
              if (!Config.hasApiKey) {
                Text('提示：流式对话需配置 DeepSeek API Key')
                  .fontSize(12)
                  .fontColor('#C2410C')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 12, left: 20, right: 20 })
                Text('路径：entry/src/main/ets/common/Config.ets → DEEPSEEK_API_KEY')
                  .fontSize(11)
                  .fontColor('#C2410C')
                  .textAlign(TextAlign.Center)
                  .opacity(0.9)
              }
            }
            .width('100%')
            .padding({ top: 60, bottom: 40 })
            .alignItems(HorizontalAlign.Center)
          }

          ForEach(this.chatMessages, (msg: ChatMessage, index: number) => {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text(msg.role === 'user' ? '🙋' : '🤖')
                  .fontSize(14)
                Text(msg.time)
                  .fontSize(11)
                  .fontColor('#BBBBBB')
              }
              .alignItems(VerticalAlign.Center)

              Text(msg.content)
                .fontSize(14)
                .fontColor(msg.role === 'user' ? '#0055CC' : '#333333')
                .textAlign(msg.role === 'user' ? TextAlign.End : TextAlign.Start)
                .width('100%')
                .lineHeight(22)
            }
            .width('100%')
            .padding({
              left: msg.role === 'user' ? 48 : 12,
              right: msg.role === 'user' ? 12 : 48,
              top: 6,
              bottom: 6
            })
          }, (msg: ChatMessage, index: number) => `${msg.role}-${index}-${msg.time}`)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)

      // 语音输入区 — 戒指设备纯语音交互
      Column() {
        Divider().color('#F0F0F0')
        Column({ space: 8 }) {
          if (this.isAiStreaming) {
            // AI 回复中 — 显示脉冲动画
            LoadingProgress()
              .width(36)
              .height(36)
              .color('#007DFF')
            Text(this.aiStatus === AiStatus.CONNECTING ? '连接 DeepSeek...' : 'AI 回复中...')
              .fontSize(13)
              .fontColor('#888888')
          } else {
            // 大麦克风按钮
            Column() {
              Stack({ alignContent: Alignment.Center }) {
                // 脉冲波纹（录音时）
                if (this.voiceStatus === VoiceStatus.LISTENING) {
                  ForEach([1, 2, 3], (_v: number, index: number) => {
                    Circle()
                      .width(48 + index * 18)
                      .height(48 + index * 18)
                      .fillOpacity(0.08)
                      .fill('#007DFF')
                  })
                }

                // 主按钮
                Column() {
                  Text(this.getMicIcon())
                    .fontSize(28)
                    .fontColor(this.voiceStatus === VoiceStatus.LISTENING ? '#FFFFFF' : '#007DFF')
                }
                .width(this.voiceStatus === VoiceStatus.LISTENING ? 56 : 64)
                .height(this.voiceStatus === VoiceStatus.LISTENING ? 56 : 64)
                .borderRadius(this.voiceStatus === VoiceStatus.LISTENING ? 28 : 32)
                .backgroundColor(this.voiceStatus === VoiceStatus.LISTENING ? '#FF4444' : '#E8F0FF')
                .justifyContent(FlexAlign.Center)
              }
              .width(100)
              .height(100)

              Text(this.getVoiceHint())
                .fontSize(13)
                .fontColor(this.voiceStatus === VoiceStatus.LISTENING ? '#FF4444' : '#888888')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              if (this.voiceStatus === VoiceStatus.IDLE || this.voiceStatus === VoiceStatus.ERROR) {
                this.startVoiceInput();
              }
            })
          }
        }
        .width('100%')
        .padding({ top: 14, bottom: 16 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }

  @Builder
  private bottomTab(icon: Resource, label: string, index: number) {
    Column({ space: 5 }) {
      Image(icon)
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .opacity(this.currentTab === index ? 1 : 0.75)
      Text(label)
        .fontSize(14)
        .fontColor(this.currentTab === index ? '#007DFF' : '#111111')
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = index;
      if (index !== 0) {
        this.showRingControlPage = false;
      }
      this.appendLog('INFO', `切换到${label}页`);
    })
  }

  build() {
    Column() {
      if (this.showRingControlPage) {
        this.ringControlPage()
      } else {
      Row() {
        Image($r('app.media.alaph'))
          .width(128)
          .height(36)
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            this.currentTab = 0;
            if (this.pageRestoreEnabled) {
              this.legacyDevices = [];
              this.showRingControlPage = false;
              this.appendLog('INFO', '页面复原已开启：已清空设备列表并恢复初始内容');
            } else {
              this.legacyDevices = [...DEFAULT_DEVICE_LIST];
              this.appendLog('INFO', '已恢复默认设备列表');
            }
          })

        Blank()

        Column() {
          if (this.plusButtonBusy) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color(Color.Blue)
          } else {
            Text('+')
              .fontSize(36)
              .fontColor('#007DFF')
              .fontWeight(FontWeight.Bold)
              .width(32)
              .height(32)
              .textAlign(TextAlign.Center)
          }
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.plusButtonBusy = true;
          void this.startBluetoothPairing();
          this.playRunClipOnce();
          setTimeout(() => {
            this.plusButtonBusy = false;
            promptAction.showDialog({
              title: '提示',
              message: '操作完成',
              buttons: [{ text: '确定', color: '#007DFF' }]
            });
          }, 3000);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Column() {
        if (this.currentTab === 0) {
          Column() {
            this.legacyDefaultPage()
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)
        } else if (this.currentTab === 1) {
          Column() {
            SleScanTabContent()
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)
          .backgroundColor('#EDEDED')

        } else if (this.currentTab === 2) {
          Column() {
            this.aiChatPage()
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)

        } else {
          Column() {
            Column() {
              this.settingsPage()
            }
            .width('100%')

            this.logPanel()
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)
          .backgroundColor('#F8F8F8')
          .alignItems(HorizontalAlign.Start)
        }

        Row() {
          this.bottomTab($r('app.media.device'), '设备', 0)
          this.bottomTab($r('app.media.signal'), '星闪', 1)
          this.bottomTab($r('app.media.setting'), 'AI 助手', 2)
          this.bottomTab($r('app.media.setting'), '设置', 3)
        }
        .height(86)
        .width('100%')
        .backgroundColor('#FFFFFF')
      }
      .layoutWeight(1)
      .width('100%')
      }
    }
    .height('100%')
    .width('100%')
  }

  aboutToAppear(): void {
    void this.refreshAppVersionLabel();

    if (canUseAntiPeep()) {
      const ok = listenOnAntiPeepStatus(this.antiPeepCB);
      this.isListenOn = ok;
      if (ok) {
        this.appendLog('INFO', '防窥屏状态监听已开启');
      }
      void this.syncAntiPeepMaskFromSwitch();
    }

    if (!this.hasRunSysIntegrityProbe) {
      this.hasRunSysIntegrityProbe = true;
      // 性能优化：系统完整性检测已延迟到后台执行
    this.runStartupSysIntegrityProbe();
    
    // 性能优化：延迟初始化视频资源
    setTimeout(() => {
      this.initVideoResources();
    }, 1000);
    }

    if (this.hasRequestedStartupLocation) {
      return;
    }
    this.hasRequestedStartupLocation = true;
    this.fetchCurrentLocationOnStartup();
  }

  aboutToDisappear(): void {
    if (this.isListenOn) {
      listenOffAntiPeepStatus();
      this.isListenOn = false;
    }
    stopBleDeviceScan();
    if (this.bleAutoStopTimerId >= 0) {
      clearTimeout(this.bleAutoStopTimerId);
      this.bleAutoStopTimerId = -1;
    }
    // 释放语音引擎
    try {
      this.asrEngine?.shutdown();
      this.asrEngine = undefined;
    } catch (_e) { /* 忽略 */ }
  }
}