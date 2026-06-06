// SseClient.ets — DeepSeek SSE 流式对话客户端
//
// Ctrl4U 专用版：纯前端直连 DeepSeek API，无需 YeDall 后端依赖。
//
// 使用方式：
// 1. 在 Config.ets 中填入 DEEPSEEK_API_KEY
// 2. 调用 SseClient.streamChat(message, null, { onToken, onDone, onError })
//
// Ctrl4U 骑行 AI 助手场景：
// "帮我开启跟拍模式" / "打开方向灯" / "骑行数据有什么异常？"

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { Config } from '../common/Config'
import { BusinessError } from '@kit.BasicServicesKit'

export interface SseCallbacks {
  onToken: (token: string) => void
  onDone: (fullText: string, conversationId: string) => void
  onError: (error: Error) => void
  onStateChange?: (state: SseState) => void
}

export enum SseState {
  CONNECTING = 'connecting',
  STREAMING = 'streaming',
  DONE = 'done',
  ERROR = 'error'
}

interface ChatMessagePayload {
  role: string
  content: string
}

interface ChatCompletionBody {
  model: string
  messages: ChatMessagePayload[]
  stream: boolean
}

export class SseClient {
  private static activeRequest: http.HttpRequest | null = null

  /**
   * 发起 SSE 流式对话请求
   *
   * Ctrl4U 默认路径：DeepSeek 直连模式
   * 备选路径：YeDall 后端代理（需 ai-brain-service 运行于 localhost:3003）
   */
  static async streamChat(
    message: string,
    conversationId: string | null,
    callbacks: SseCallbacks
  ): Promise<void> {
    // 默认走 DeepSeek 直连
    if (Config.isDeepSeekDirect) {
      return SseClient.streamChatDeepSeek(message, callbacks)
    }

    // 备选：YeDall 后端代理模式
    return SseClient.streamChatBackend(message, conversationId, callbacks)
  }

  /**
   * DeepSeek API 直连模式（Ctrl4U 默认）
   *
   * 对齐 DeepSeek Chat Completions API：
   *   POST https://api.deepseek.com/v1/chat/completions
   *   Body: { model, messages: [{role, content}], stream: true }
   *   响应: SSE data: {"choices":[{"delta":{"content":"..."}}]} ... data: [DONE]
   */
  static async streamChatDeepSeek(
    message: string,
    callbacks: SseCallbacks
  ): Promise<void> {
    if (!Config.hasApiKey) {
      callbacks.onError(new Error('DeepSeek API 密钥未配置，请在 common/Config.ets 中填入 DEEPSEEK_API_KEY'))
      callbacks.onStateChange?.(SseState.ERROR)
      return
    }

    const req = http.createHttp()
    SseClient.activeRequest = req

    let fullText = ''
    let buffer = ''
    let hasError = false

    const textDecoderOptions: util.TextDecoderOptions = {
      fatal: false,
      ignoreBOM: true
    }
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', textDecoderOptions)

    callbacks.onStateChange?.(SseState.CONNECTING)
    console.info('[SseClient] → POST', Config.DEEPSEEK_BASE_URL + '/v1/chat/completions')
    console.info('[SSE-DEBUG] 1️⃣ 请求已发出, readTimeout=' + Config.SSE_TIMEOUT + 'ms')

    let httpStatus = 0

    req.on('headersReceive', (header: Object) => {
      try {
        httpStatus = (header as Record<string, Object>)['responseCode'] as number || 0
        const contentType = (header as Record<string, Object>)['Content-Type'] as string || ''
        console.info('[SseClient] ← HTTP', httpStatus)
        console.info('[SSE-DEBUG] 2️⃣ 响应头已收到, Content-Type:', contentType)
      } catch (_e) { /* ignore */ }
      if (httpStatus >= 400) {
        hasError = true
        callbacks.onError(new Error(`HTTP ${httpStatus}: DeepSeek 服务拒绝请求`))
        callbacks.onStateChange?.(SseState.ERROR)
        req.destroy()
        return
      }
      callbacks.onStateChange?.(SseState.STREAMING)
    })

    req.on('dataReceive', (data: ArrayBuffer) => {
      if (hasError) return
      try {
        const chunk: string = decoder.decodeToString(new Uint8Array(data), { stream: true })
        console.info('[SseClient] ← data chunk:', chunk.substring(0, 120))
        console.info('[SSE-DEBUG] 3️⃣ 收到数据块: ' + data.byteLength + ' bytes, 已累计 ' + fullText.length + ' 字')
        buffer += chunk

        const events: string[] = buffer.split('\n\n')
        buffer = events.pop() || ''

        for (const event of events) {
          const trimmed: string = event.trim()
          if (!trimmed) continue

          const lines: string[] = trimmed.split('\n')
          for (const line of lines) {
            if (!line.startsWith('data:')) continue

            const jsonStr: string = line.substring(5).trim()  // 兼容 data: 和 data: 

            if (jsonStr === '[DONE]') {
              callbacks.onDone(fullText, '')
              callbacks.onStateChange?.(SseState.DONE)
              return
            }

            try {
              const parsed: Record<string, Object> = JSON.parse(jsonStr)
              const choices: Object | undefined = parsed['choices']
              if (choices !== undefined && Array.isArray(choices) && (choices as Object[]).length > 0) {
                const firstChoice: Record<string, Object> = (choices as Object[])[0] as Record<string, Object>
                const delta: Object | undefined = firstChoice['delta']
                if (delta !== undefined) {
                  const content: string = (delta as Record<string, Object>)['content'] as string || ''
                  if (content) {
                    fullText += content
                    callbacks.onToken(content)
                  }
                }
                const finishReason: string = firstChoice['finish_reason'] as string || ''
                if (finishReason === 'stop') {
                  callbacks.onDone(fullText, '')
                  callbacks.onStateChange?.(SseState.DONE)
                  return
                }
              }
            } catch (_parseErr) {
              // 跳过无法解析的行
            }
          }
        }
      } catch (err) {
        console.error('[SSE-DeepSeek] Parse error:', JSON.stringify(err))
      }
    })

    req.on('dataEnd', () => {
      console.info('[SSE-DEBUG] 4️⃣ 流已结束, fullText=' + fullText.length + '字, buffer剩余=' + buffer.length + '字节')
      if (hasError) return
      if (buffer.trim()) {
        const lastLine: string = buffer.trim()
        if (lastLine.startsWith('data:') && lastLine !== 'data: [DONE]') {
          const jsonStr: string = lastLine.substring(5).trim()  // 兼容 data: 和 data: 
          try {
            const parsed: Record<string, Object> = JSON.parse(jsonStr)
            const choices: Object | undefined = parsed['choices']
            if (choices !== undefined && Array.isArray(choices) && (choices as Object[]).length > 0) {
              const firstChoice: Record<string, Object> = (choices as Object[])[0] as Record<string, Object>
              const delta: Object | undefined = firstChoice['delta']
              if (delta !== undefined) {
                const content: string = (delta as Record<string, Object>)['content'] as string || ''
                if (content) {
                  fullText += content
                  callbacks.onToken(content)
                }
              }
            }
          } catch (_e) { /* ignore */ }
        }
      }
      if (!hasError) {
        if (!fullText && buffer) {
          // 收到非 SSE 格式响应，可能是错误 JSON
          console.warn('[SseClient] non-SSE response:', buffer.substring(0, 200))
          try {
            const errParsed: Record<string, Object> = JSON.parse(buffer.trim())
            const errObj = errParsed['error']
            if (errObj) {
              callbacks.onError(new Error((errObj as Record<string, Object>)['message'] as string || 'DeepSeek API 错误'))
              callbacks.onStateChange?.(SseState.ERROR)
              return
            }
          } catch (_e2) { /* ignore */ }
        }
        callbacks.onDone(fullText, '')
        callbacks.onStateChange?.(SseState.DONE)
      }
    })

    try {
      // Ctrl4U 骑行 AI 助手系统提示词
      const systemPrompt = `你是 Ctrl4U 骑行智能助手。你的职责是：
1. 回答骑行安全问题（头盔、方向灯、鸣笛时机等）
2. 解答 Ring Control 智能指环的使用方法
3. 提供运动相机和无人机跟拍的建议
4. 注意：你不生成代码，仅提供骑行相关的智能建议和对话

用户消息：${message}`

      const sysMsg: ChatMessagePayload = { role: 'system', content: systemPrompt }
      const userMsg: ChatMessagePayload = { role: 'user', content: message }
      const chatBody: ChatCompletionBody = {
        model: Config.DEEPSEEK_MODEL,
        messages: [sysMsg, userMsg],
        stream: true
      }
      const body: string = JSON.stringify(chatBody)

      req.requestInStream(`${Config.DEEPSEEK_BASE_URL}/v1/chat/completions`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${Config.DEEPSEEK_API_KEY}`,
          'Accept': 'text/event-stream'
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: Config.SSE_TIMEOUT,
        usingProtocol: http.HttpProtocol.HTTP1_1
      }).then(() => {
        // 检查点1：请求已发出，等待 headers
      }).catch((err: BusinessError) => {
        hasError = true
        console.error('[SseClient] requestInStream failed:', err.code, err.message)
        callbacks.onError(new Error(`DeepSeek 请求失败: ${err.message}`))
        callbacks.onStateChange?.(SseState.ERROR)
        SseClient.activeRequest = null
      })
    } catch (err) {
      hasError = true
      const errorMsg: string = err instanceof Error ? err.message : JSON.stringify(err)
      console.error('[SseClient] exception:', errorMsg)
      callbacks.onError(new Error(errorMsg))
      callbacks.onStateChange?.(SseState.ERROR)
      SseClient.activeRequest = null
    }
  }

  /**
   * YeDall 后端代理模式（保留接口，需要 ai-brain-service 运行）
   *
   * 需要：
   * 1. Docker 启动 ai-brain-service（localhost:3003）
   * 2. 在 Config.ets 中切换 AI_ENDPOINT_MODE = BACKEND
   */
  private static async streamChatBackend(
    message: string,
    conversationId: string | null,
    callbacks: SseCallbacks
  ): Promise<void> {
    const req = http.createHttp()
    SseClient.activeRequest = req

    let fullText = ''
    let buffer = ''
    let hasError = false

    const textDecoderOptions: util.TextDecoderOptions = {
      fatal: false,
      ignoreBOM: true
    }
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', textDecoderOptions)

    callbacks.onStateChange?.(SseState.CONNECTING)

    req.on('headersReceive', (_header: Object) => {
      callbacks.onStateChange?.(SseState.STREAMING)
    })

    req.on('dataReceive', (data: ArrayBuffer) => {
      if (hasError) return
      try {
        const chunk: string = decoder.decodeToString(new Uint8Array(data), { stream: true })
        buffer += chunk

        const events: string[] = buffer.split('\n\n')
        buffer = events.pop() || ''

        for (const event of events) {
          const trimmed: string = event.trim()
          if (!trimmed) continue

          const lines: string[] = trimmed.split('\n')
          for (const line of lines) {
            if (!line.startsWith('data:')) continue

            const jsonStr: string = line.substring(5).trim()  // 兼容 data: 和 data: 
            if (jsonStr === '[DONE]') {
              callbacks.onDone(fullText, conversationId || '')
              callbacks.onStateChange?.(SseState.DONE)
              return
            }

            try {
              const parsed: Record<string, Object> = JSON.parse(jsonStr)
              const typ: string = parsed['type'] as string
              if (typ === 'error') {
                hasError = true
                callbacks.onError(new Error(parsed['message'] as string || '服务端错误'))
                callbacks.onStateChange?.(SseState.ERROR)
                return
              }
              const token: string = (parsed['token'] as string) || (parsed['text'] as string) || ''
              if (token) {
                fullText += token
                callbacks.onToken(token)
              }
            } catch (_parseErr) { /* skip */ }
          }
        }
      } catch (err) {
        console.error('[SSE-Backend] Parse error:', JSON.stringify(err))
      }
    })

    req.on('dataEnd', () => {
      if (!hasError) {
        callbacks.onDone(fullText, conversationId || '')
        callbacks.onStateChange?.(SseState.DONE)
      }
    })

    try {
      const body: string = JSON.stringify({
        message: message,
        session_id: conversationId || undefined
      })

      req.requestInStream(`${Config.AI_BASE_URL}/api/ai/chat/stream`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream'
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: Config.SSE_TIMEOUT,
        usingProtocol: http.HttpProtocol.HTTP1_1
      }).catch((err: BusinessError) => {
        hasError = true
        callbacks.onError(new Error(`后端请求失败: ${err.message}`))
        callbacks.onStateChange?.(SseState.ERROR)
        SseClient.activeRequest = null
      })
    } catch (err) {
      hasError = true
      callbacks.onError(new Error(err instanceof Error ? err.message : JSON.stringify(err)))
      callbacks.onStateChange?.(SseState.ERROR)
      SseClient.activeRequest = null
    }
  }

  /** 中断当前 SSE 连接 */
  static abort(): void {
    if (SseClient.activeRequest) {
      SseClient.activeRequest.off('headersReceive')
      SseClient.activeRequest.off('dataReceive')
      SseClient.activeRequest.off('dataEnd')
      SseClient.activeRequest.destroy()
      SseClient.activeRequest = null
    }
  }
}
