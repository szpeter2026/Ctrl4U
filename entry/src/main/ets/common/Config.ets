/**
 * Config.ets — AI 端点与模式配置
 *
 * Ctrl4U 默认使用 DeepSeek 直连（SSE），无需自有后端。
 *
 * 竞赛提交前请务必：
 * 1. 在 https://platform.deepseek.com 申请 API Key，将密钥填入下方 DEEPSEEK_API_KEY（仅本地/私有构建，勿提交到公开仓库或 ZIP）。
 * 2. 打包 ZIP 时使用不含密钥的 Config 副本，或在提交后于本地重置该字段。
 *
 * 若密钥留空：AI 页会报错提示，星闪与安全相关演示不受影响。
 */

export enum AiEndpointMode {
  /** 直连 DeepSeek API（默认，竞赛演示用） */
  DEEPSEEK_DIRECT = 'deepseek_direct',
  /** 后端代理模式（需对接 YeDall ai-brain-service） */
  BACKEND = 'backend'
}

// 当前 AI 端点模式
const CURRENT_AI_MODE: AiEndpointMode = AiEndpointMode.DEEPSEEK_DIRECT

export class Config {
  static readonly AI_ENDPOINT_MODE: AiEndpointMode = CURRENT_AI_MODE

  // DeepSeek 直连配置
  // ⚠️ 竞赛演示：填入有效 API 密钥后即可启用 AI 对话功能
  // ⚠️ 提交时已清空密钥，请在此填入你自己的 DeepSeek API Key
  static readonly DEEPSEEK_API_KEY: string = '' // ← 在此填入 DeepSeek API Key
  static readonly DEEPSEEK_BASE_URL: string = 'https://api.deepseek.com'
  static readonly DEEPSEEK_MODEL: string = 'deepseek-v4-pro' // Chat Completions API: deepseek-v4-pro / deepseek-v4-flash / deepseek-reasoner

  // 后端代理模式（保留接口，暂不使用）
  static readonly AI_BASE_URL: string = 'http://127.0.0.1:3003'

  // 超时配置（毫秒）
  static readonly REQUEST_TIMEOUT: number = 15000
  static readonly SSE_TIMEOUT: number = 300000  // 5 分钟：DeepSeek 深度思考模型可能需要 10~60s 才开始输出

  static get isDeepSeekDirect(): boolean {
    return CURRENT_AI_MODE === AiEndpointMode.DEEPSEEK_DIRECT
  }

  static get hasApiKey(): boolean {
    return this.DEEPSEEK_API_KEY.length > 0
  }
}
