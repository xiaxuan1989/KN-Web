import './style.css';
import { Renderer } from './renderer/renderer';
import { Camera } from './camera/camera.ts';
import { DEFAULT_PARAMETERS } from './physics/parameters.ts';
import { bindControls } from './ui/controls.ts';
import { WEBGPU_REQUIREMENTS } from './renderer/webgpu-support.ts';

const canvas = document.querySelector<HTMLCanvasElement>('#gpu-canvas')!;
const status = document.querySelector<HTMLParagraphElement>('#status')!;
const adapter = document.querySelector<HTMLElement>('#adapter')!;
const prepassResolution = document.querySelector<HTMLElement>('#prepass-resolution')!;
const resolution = document.querySelector<HTMLElement>('#resolution')!;
const taaWeight = document.querySelector<HTMLElement>('#taa-weight')!;
const observerStatus = document.querySelector<HTMLElement>('#observer-status')!;
const fps = document.querySelector<HTMLElement>('#fps')!;
const retry = document.querySelector<HTMLButtonElement>('#retry')!;
const position = document.querySelector<HTMLElement>('#position')!;
const direction = document.querySelector<HTMLElement>('#direction')!;
const elapsed = document.querySelector<HTMLElement>('#elapsed')!;
const verification = document.querySelector<HTMLElement>('#verification')!;
const verify = document.querySelector<HTMLButtonElement>('#verify')!;
const reset = document.querySelector<HTMLButtonElement>('#reset-camera')!;
const cameraMode = document.querySelector<HTMLElement>('#camera-mode')!;
const inputHelp = document.querySelector<HTMLElement>('#input-help')!;
document.querySelector<HTMLElement>('#browser-support')!.textContent = WEBGPU_REQUIREMENTS;
const parameters = { ...DEFAULT_PARAMETERS };
const camera = new Camera();
const controls = bindControls(parameters);
const events = new AbortController();
const panel = document.querySelector<HTMLElement>('#diagnostics-panel')!;
const panelToggle = document.querySelector<HTMLButtonElement>('#panel-toggle')!;
function setPanelExpanded(expanded: boolean): void {
  panel.hidden = !expanded;
  panelToggle.textContent = expanded ? '收起面板' : '展开面板';
  panelToggle.setAttribute('aria-expanded', String(expanded));
}
setPanelExpanded(true);
panelToggle.addEventListener('click', () => setPanelExpanded(panel.hidden === true), { signal: events.signal });
let renderer: Renderer | undefined;

function start(): void {
  renderer?.dispose();
  status.textContent = '正在初始化 WebGPU…';
  status.dataset.state = 'loading';
  adapter.textContent = '等待设备';
  resolution.textContent = '—';
  prepassResolution.textContent = '—';
  fps.textContent = '—';
  taaWeight.textContent = '—';
  retry.hidden = true;
  verify.disabled = true;
  verification.textContent = '等待 GPU 回读';

  renderer = new Renderer(canvas, parameters, camera, {
    onLoading: (message) => { status.textContent = message; },
    onReady: (name) => {
      status.textContent = 'WebGPU 运行中';
      status.dataset.state = 'ready';
      adapter.textContent = name;
      verify.disabled = false;
    },
    onStats: (stats) => {
      resolution.textContent = `${stats.width} × ${stats.height}`;
      prepassResolution.textContent = stats.prepassEnabled ? `${stats.prepassWidth} × ${stats.prepassHeight}` : '关闭 · 全分辨率追踪';
      fps.textContent = stats.fps === null ? '—' : stats.fps.toFixed(1);
      taaWeight.textContent = stats.temporalWeight === null ? '关闭' : `${(stats.temporalWeight*100).toFixed(2)}% 当前帧`;
      observerStatus.textContent = stats.observerStatus;
      position.textContent = stats.position.map((value) => value.toFixed(2)).join(', ');
      direction.textContent = stats.direction.map((value) => value.toFixed(3)).join(', ');
      elapsed.textContent = `${stats.time.toFixed(1)} s`;
      controls.sync();
    },
    onError: (message) => {
      fps.textContent = '—';
      status.textContent = message;
      status.dataset.state = 'error';
      retry.hidden = false;
      verify.disabled = true;
    },
    onVerification: (message) => { verification.textContent = message; },
    onCameraMode: (mode) => {
      cameraMode.textContent = mode === 'orbit' ? '轨道模式' : '自由视角';
      inputHelp.textContent = mode === 'orbit'
        ? 'T 切换自由视角。左键 / WASD 绕黑洞转，右键独立摆头，松手后惯性滑停；中键平滑回正，滚轮拉近 / 拉远黑洞，FOV 不变。'
        : 'T 切换轨道模式。左键转向，QE 滚转，松手后惯性滑停；WASD / RF 平移，滚轮调整移动速度。返回轨道模式后，环绕中心和轴会平滑归位。';
    },
  });
  void renderer.start();
}

retry.addEventListener('click', start, { signal: events.signal });
verify.addEventListener('click', async () => {
  verify.disabled = true;
  await renderer?.verifyUniforms();
  if (status.dataset.state === 'ready') verify.disabled = false;
}, { signal: events.signal });
reset.addEventListener('click', () => renderer?.resetCamera(), { signal: events.signal });
start();

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    renderer?.dispose();
    controls.dispose();
    events.abort();
  });
}
