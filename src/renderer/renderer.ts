import prepassShader from '../shaders/prepass.wgsl?raw';
import { ScenePasses } from './scene-passes.ts';
import { renderSize } from './render-size.ts';
import spectrumShader from '../shaders/spectrum.wgsl?raw';
import hdrShader from '../shaders/hdr.wgsl?raw';
import postShader from '../shaders/post.wgsl?raw';
import { PostProcessing } from './post-processing.ts';
import { TemporalState } from './temporal.ts';
import { advanceObserverFrame } from './observer-frame.ts';
import { ObserverTrajectory, observerAcceleration, scrollObserverThrust, type BoostDirection } from '../physics/observer-trajectory.ts';
import { prepassFrame } from './uniform-layout.ts';
import fullscreenShader from '../shaders/fullscreen.wgsl?raw';
import commonShader from '../shaders/common.wgsl?raw';
import geometryShader from '../shaders/geometry.wgsl?raw';
import coordinatesShader from '../shaders/coordinates.wgsl?raw';
import diagnosticsShader from '../shaders/diagnostics.wgsl?raw';
import gridShader from '../shaders/grid.wgsl?raw';
import geodesicShader from '../shaders/geodesic.wgsl?raw';
import { Background } from './background.ts';
import { Camera, type CameraMode, type Vec3 } from '../camera/camera.ts';
import { CameraInput } from '../camera/input.ts';
import type { Parameters } from '../physics/parameters.ts';
import { UniformBuffers } from './buffers.ts';
import { WEBGPU_REQUIREMENTS } from './webgpu-support.ts';

export interface RendererStats {
  width: number;
  height: number;
  prepassWidth: number;
  prepassHeight: number;
  prepassEnabled: boolean;
  fps: number | null;
  temporalWeight: number | null;
  observerStatus: string;
  time: number;
  position: Vec3;
  direction: Vec3;
}

export interface RendererCallbacks {
  onReady: (adapter: string) => void;
  onStats: (stats: RendererStats) => void;
  onError: (message: string) => void;
  onVerification: (message: string) => void;
  onCameraMode: (mode: CameraMode) => void;
  onLoading: (message: string) => void;
}

export class Renderer {
  private device?: GPUDevice;
  private context?: GPUCanvasContext;
  private scene?: ScenePasses;
  private prepassUniforms?: UniformBuffers;
  private halfSize: [number,number] = [1,1];
  private usePrepass = false;
  private frameId = 0;
  private disposed = false;
  private fpsFrames = 0;
  private fpsElapsedMs = 0;
  private lastStatsTime = -Infinity;
  private lastFrameTime?: number;
  private elapsedTime = 0;
  private simulationTime = 0;
  private deltaTime = 0;
  private realDeltaTime = 0;
  private uniforms?: UniformBuffers;
  private background?: Background;
  private input?: CameraInput;
  private verifying = false;
  private readonly loading = new AbortController();
  private post?: PostProcessing;
  private readonly temporal = new TemporalState();
  private temporalFrame = { weight: 1, jitter: [0, 0] as [number, number] };
  private postActive = false;
  private trajectory?: ObserverTrajectory;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly parameters: Parameters,
    private readonly camera: Camera,
    private readonly callbacks: RendererCallbacks,
  ) {}

  async start(): Promise<void> {
    try {
      if (!window.isSecureContext) {
        throw new Error('当前连接不安全，无法启用 WebGPU。请使用 HTTPS，或在本机通过 localhost / 127.0.0.1 打开页面。');
      }
      if (!navigator.gpu) {
        throw new Error(`当前浏览器或操作系统未提供 WebGPU。${WEBGPU_REQUIREMENTS}`);
      }
      const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
      if (this.disposed) return;
      if (!adapter) throw new Error('浏览器提供了 WebGPU，但未能连接可用 GPU。请检查系统版本、显卡驱动和浏览器硬件加速设置，然后重试。');

      const device = await adapter.requestDevice({ label: 'KN Phase 6 device' });
      if (this.disposed) {
        device.destroy();
        return;
      }
      this.device = device;
      void device.lost.then((info) => {
        if (!this.disposed) this.fail(`GPU 设备连接已丢失（${info.reason}）：${info.message || '请重新初始化。'}`);
      });
      device.addEventListener('uncapturederror', (event) => {
        if (!this.disposed) this.fail(`WebGPU 错误：${event.error.message}`);
      });

      const context = this.canvas.getContext('webgpu');
      if (!context) throw new Error('当前浏览器无法创建 WebGPU 画布，请更新浏览器与操作系统后重试。');
      this.context = context;
      const format = navigator.gpu.getPreferredCanvasFormat();
      context.configure({ device, format, alphaMode: 'opaque' });
      this.uniforms = new UniformBuffers(device);
      this.prepassUniforms = new UniformBuffers(device);
      this.callbacks.onLoading('正在加载星空 · 0 / 6');
      const background = await Background.create(device, this.loading.signal, (count) => {
        if (!this.disposed) this.callbacks.onLoading(`正在加载星空 · ${count} / 6`);
      });
      if (this.disposed) { background.dispose(); return; }
      this.background = background;
      this.callbacks.onLoading('星空已上传，正在编译透镜管线…');

      this.scene = await ScenePasses.create(device,this.uniforms.layout,this.background.layout,
        [commonShader,geometryShader,coordinatesShader,diagnosticsShader,gridShader, geodesicShader,spectrumShader,hdrShader,fullscreenShader,prepassShader].join('\n'));
      if (this.disposed) { this.scene.dispose(); return; }

      const post = await PostProcessing.create(device, format, postShader);
      if (this.disposed) { post.dispose(); return; }
      this.post = post;

      // Validate and finish the first submission before reporting readiness.
      device.pushErrorScope('validation');
      this.draw();
      const validationError = await device.popErrorScope();
      if (validationError) throw new Error(validationError.message);
      await device.queue.onSubmittedWorkDone();
      if (this.disposed) return;
      await this.verifyUniforms();
      if (this.disposed) return;
      this.input = new CameraInput(this.canvas, this.camera, this.callbacks.onCameraMode, () => this.parameters.observerMode === -1, {
        toggle: () => { this.parameters.observerMode = this.parameters.observerMode === -1 ? 0 : -1;this.prepareTrajectory(); },
        scroll: notches => { this.parameters.observerThrust = scrollObserverThrust(this.parameters.observerThrust,notches); },
      });
      this.callbacks.onCameraMode(this.camera.mode);

      const info = adapter.info;
      this.callbacks.onReady(info.description || [info.vendor, info.architecture].filter(Boolean).join(' / ') || 'WebGPU 设备（浏览器未公开型号）');
      this.reportStats(performance.now());
      document.addEventListener('visibilitychange', this.onVisibilityChange);
      if (!document.hidden) this.frameId = requestAnimationFrame(this.frame);
    } catch (error) {
      if (!this.disposed) this.fail(error instanceof Error ? error.message : String(error));
    }
  }

  dispose(): void {
    this.disposed = true;
    this.loading.abort();
    cancelAnimationFrame(this.frameId);
    document.removeEventListener('visibilitychange', this.onVisibilityChange);
    this.input?.dispose();
    this.uniforms?.dispose();
    this.prepassUniforms?.dispose();
    this.scene?.dispose();
    this.background?.dispose();
    this.post?.dispose();
    this.context?.unconfigure();
    this.device?.destroy();
  }

  async verifyUniforms(): Promise<void> {
    if (this.disposed || !this.uniforms || this.verifying) return;
    this.verifying = true;
    this.callbacks.onVerification('正在通过 WGSL 读取参数…');
    try {
      this.updateUniforms();
      const fullCount = await this.uniforms.verify();
      if (this.disposed) return;
      const halfCount = await this.prepassUniforms!.verify();
      const count = fullCount + halfCount;
      if (!this.disposed) this.callbacks.onVerification(`GPU 回读通过 · ${count} 个分量（全 / 半分辨率）一致`);
    } catch (error) {
      if (!this.disposed) this.fail(error instanceof Error ? error.message : String(error));
    } finally {
      this.verifying = false;
    }
  }

  resetCamera(): void {
    this.input?.clear();
    this.camera.setMass(this.parameters.massSolar);
    this.camera.reset();
    this.temporal.reset();
    this.trajectory = undefined;
    this.callbacks.onCameraMode(this.camera.mode);
  }

  private fail(message: string): void {
    this.dispose();
    this.callbacks.onError(message);
  }

  private readonly onVisibilityChange = (): void => {
    cancelAnimationFrame(this.frameId);
    this.lastFrameTime = undefined;
    this.fpsFrames = 0;
    this.fpsElapsedMs = 0;
    this.lastStatsTime = -Infinity;
    this.temporal.reset();
    if (!document.hidden && !this.disposed) this.frameId = requestAnimationFrame(this.frame);
  };

  private readonly frame = (time: number): void => {
    if (this.disposed) return;
    try {
      // Measure actual animation-frame intervals, before the simulation's 50 ms cap.
      if (this.lastFrameTime !== undefined && time > this.lastFrameTime) {
        this.fpsElapsedMs += time - this.lastFrameTime;
        this.fpsFrames += 1;
      }
      // Native update evolves the camera using the preceding measured interval.
      const cameraDeltaTime = this.lastFrameTime === undefined ? 0 : this.realDeltaTime;
      this.realDeltaTime = this.lastFrameTime === undefined ? 0 : Math.max(0, (time - this.lastFrameTime) / 1000);
      this.deltaTime = Math.min(0.05,this.realDeltaTime);
      this.lastFrameTime = time;
      this.elapsedTime += this.deltaTime;
      this.simulationTime += this.parameters.timeRate*this.realDeltaTime;
      this.camera.setMass(this.parameters.massSolar);
      this.input?.update(cameraDeltaTime);
      this.draw();
      if (time - this.lastStatsTime >= 500) this.reportStats(time);
      this.frameId = requestAnimationFrame(this.frame);
    } catch (error) {
      this.fail(error instanceof Error ? error.message : String(error));
    }
  };

  private draw(): void {
    this.camera.setMass(this.parameters.massSolar);
    const device = this.device!;
    // NPGS follows window size; macOS disables Retina framebuffer scaling.
    // CSS pixels therefore drive the default output, without multiplying by DPR.
    const requestedWidth = this.parameters.fitWindow ? this.canvas.clientWidth : this.parameters.renderWidth;
    const requestedHeight = this.parameters.fitWindow ? this.canvas.clientHeight : this.parameters.renderHeight;
    const { full: [width,height], half } = renderSize(requestedWidth,requestedHeight,device.limits.maxTextureDimension2D);
    this.halfSize = half;
    this.usePrepass = this.parameters.prepass && (this.parameters.debugView === 3 || this.parameters.debugView === 4);
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }
    this.post!.resize(width, height);
    this.scene!.resize(...half);
    this.postActive = this.parameters.postProcessing && (this.parameters.debugView === 3 || this.parameters.debugView === 4 || this.parameters.debugView === 5);
    this.prepareTrajectory();
    if (this.trajectory) this.trajectory.acceleration = observerAcceleration(this.input?.thrustAxes() ?? [0,0,0],this.camera.basis(),this.parameters.observerThrust);
    this.temporalFrame = advanceObserverFrame(this.temporal,this.camera.basis(),this.parameters,
      this.realDeltaTime,this.postActive && this.parameters.taa,this.trajectory);
    this.updateUniforms();
    this.uniforms!.upload();
    this.prepassUniforms!.upload();

    const encoder = device.createCommandEncoder({ label: 'Fullscreen frame' });
    this.scene!.encode(encoder,this.post!.scene.createView(),this.uniforms!.bindGroup,this.prepassUniforms!.bindGroup,
      this.background!.bindGroup(this.parameters.background),this.usePrepass,(this.parameters.debugView === 3 || this.parameters.debugView === 4),this.parameters.spatialGrid,
      this.parameters.nativeDebug !== 0 || this.parameters.debugView === 4);
    this.post!.encode(encoder, this.context!.getCurrentTexture().createView(), this.parameters, this.temporalFrame.weight, this.postActive);
    device.queue.submit([encoder.finish()]);
  }

  private reportStats(time: number): void {
    this.lastStatsTime = time;
    const basis = this.camera.basis();
    this.callbacks.onStats({
      width: this.canvas.width, height: this.canvas.height,
      prepassWidth: this.halfSize[0], prepassHeight: this.halfSize[1], prepassEnabled: this.usePrepass,
      fps: this.fpsElapsedMs > 0 ? this.fpsFrames * 1000 / this.fpsElapsedMs : null,
      temporalWeight: this.postActive && this.parameters.taa ? this.temporalFrame.weight : null,
      observerStatus: this.trajectory ? (this.trajectory.stopped ? '四维轨迹已到当前可追踪范围边界；重置相机可重新出发。'
        : `四维轨迹${this.parameters.timeRate === 0 ? '已暂停' : '运行中'} · 固有时间 ${this.trajectory.properTime.toFixed(3)} Rs/c`) : '',
      time: this.elapsedTime, position: this.trajectory ? this.trajectory.state.slice(0,3) as Vec3 : basis.position, direction: basis.forward,
    });
    this.fpsFrames = 0;
    this.fpsElapsedMs = 0;
  }

  private updateUniforms(): void {
    const camera = this.camera.basis();
    const frame = { width: this.canvas.width, height: this.canvas.height, cameraVelocity: this.temporal.cameraVelocity(),
      tetrad: this.trajectory?.frame(camera),
      time: this.elapsedTime, simulationTime: this.simulationTime, deltaTime: this.deltaTime, jitter: this.temporalFrame.jitter, postProcessing: this.postActive };
    this.uniforms!.data.update(frame, this.parameters, camera);
    this.prepassUniforms!.data.update(prepassFrame(frame), this.parameters, camera);
  }

  boostObserver(direction: BoostDirection): boolean {
    if (this.disposed || this.parameters.observerMode !== -1) return false;
    this.prepareTrajectory();
    const p = this.parameters;
    return this.trajectory!.boost(p.boostRapidity,direction,this.camera.basis(),p.spin*.5,p.charge*.5);
  }

  private prepareTrajectory(): void {
    const p = this.parameters;
    if (p.observerMode !== -1) {
      if (this.trajectory) {
        this.trajectory = undefined;
        this.callbacks.onCameraMode(this.camera.mode);
      }
      return;
    }
    if (!this.trajectory) {
      this.trajectory = new ObserverTrajectory();
      const velocity: Vec3 = p.manualVelocity ? [p.velocityX,p.velocityY,p.velocityZ] : this.temporal.cameraVelocity();
      this.trajectory.initialize(this.camera.position,velocity,p.spin*.5,p.charge*.5);
      this.camera.enterObserverMode();
      this.callbacks.onCameraMode(this.camera.mode);
    }
  }
}
