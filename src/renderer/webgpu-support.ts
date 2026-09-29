export const WEBGPU_REQUIREMENTS = '可使用支持 WebGPU 的 Safari、Firefox、Chrome 或 Edge。Safari 需要 Safari 26+ 与 macOS 26+ / iOS 26+ / iPadOS 26+；Firefox 在 Windows 上需要 141+，在 Apple Silicon Mac 上建议 147+。其他平台以浏览器实际支持为准。请通过 HTTPS 或 localhost 访问。';

export function requireWebGPU(secureContext: boolean, gpu: GPU | undefined): GPU {
  if (!secureContext) {
    throw new Error('当前连接不安全，无法启用 WebGPU。请使用 HTTPS，或在本机通过 localhost / 127.0.0.1 打开页面。');
  }
  if (!gpu) {
    throw new Error(`当前浏览器或操作系统未提供 WebGPU。${WEBGPU_REQUIREMENTS}`);
  }
  return gpu;
}

export async function requestWebGPUAdapter(gpu: GPU, signal: AbortSignal): Promise<GPUAdapter> {
  let lastError: unknown;
  // Power preference is only a hint. Let the browser choose its default GPU if
  // the preferred request fails, rather than rejecting an otherwise usable GPU.
  for (const options of [{ powerPreference: 'high-performance' } as GPURequestAdapterOptions, undefined]) {
    signal.throwIfAborted();
    try {
      const adapter = await gpu.requestAdapter(options);
      signal.throwIfAborted();
      if (adapter) return adapter;
    } catch (error) {
      signal.throwIfAborted();
      lastError = error;
    }
  }
  const detail = lastError instanceof Error ? `（${lastError.message}）` : '';
  throw new Error(`浏览器提供了 WebGPU，但未能连接可用 GPU。请检查系统版本、显卡驱动和浏览器硬件加速设置，然后重试。${detail}`);
}

export function adapterDisplayName(adapter: GPUAdapter): string {
  // GPU metadata is diagnostic only; unavailable or privacy-restricted metadata
  // must not prevent an already validated renderer from starting.
  try {
    const info = adapter.info;
    const name = info?.description || [info?.vendor, info?.architecture].filter(Boolean).join(' / ');
    if (name) return name;
  } catch { /* Some implementations restrict adapter information. */ }
  return 'WebGPU 设备（浏览器未公开型号）';
}

export async function checkShaderCompilation(module: GPUShaderModule, label: string): Promise<void> {
  // Older/partial implementations may omit diagnostic messages. Pipeline
  // creation still validates the shader and remains mandatory on every browser.
  if (typeof module.getCompilationInfo !== 'function') return;
  const info = await module.getCompilationInfo();
  const errors = info.messages.filter(message => message.type === 'error');
  if (errors.length) {
    throw new Error(errors.map(message => `${label} ${message.lineNum}:${message.linePos} ${message.message}`).join('\n'));
  }
}
