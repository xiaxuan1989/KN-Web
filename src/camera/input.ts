import { Camera, type CameraMode } from './camera.ts';

const MOVEMENT_KEYS = new Set(['KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyR', 'KeyF', 'KeyQ', 'KeyE', 'ShiftLeft', 'ShiftRight']);

export class CameraInput {
  private readonly keys = new Set<string>();
  private readonly controller = new AbortController();
  private pointer: number | null = null;
  private dragButton: 0 | 2 = 0;
  private lastX = 0;
  private lastY = 0;
  private readonly touches = new Map<number, { x: number; y: number }>();
  private touchGesture: { x: number; y: number; distance: number } | null = null;
  private readonly canvas: HTMLCanvasElement;
  private readonly camera: Camera;
  private readonly trajectoryActive: () => boolean;

  constructor(canvas: HTMLCanvasElement, camera: Camera, onModeChange: (mode: CameraMode) => void = () => {},
    trajectoryActive: () => boolean = () => false) {
    this.canvas = canvas;
    this.camera = camera;
    this.trajectoryActive = trajectoryActive;
    const options = { signal: this.controller.signal };
    canvas.addEventListener('keydown', (event) => {
      if (event.isComposing || event.ctrlKey || event.metaKey || event.altKey) return;
      if (event.code === 'KeyT') {
        event.preventDefault();
        if (!event.repeat && !this.trajectoryActive()) {
          this.clear();
          camera.toggleMode();
          onModeChange(camera.mode);
        }
        return;
      }
      if (MOVEMENT_KEYS.has(event.code)) {
        event.preventDefault();
        this.keys.add(event.code);
      }
    }, options);
    window.addEventListener('keyup', (event) => this.keys.delete(event.code), options);
    canvas.addEventListener('contextmenu', (event) => event.preventDefault(), options);
    canvas.addEventListener('auxclick', (event) => { if (event.button === 1) event.preventDefault(); }, options);
    canvas.addEventListener('pointerdown', (event) => {
      if (event.pointerType === 'touch') {
        if (this.pointer !== null) return;
        event.preventDefault();
        canvas.focus({ preventScroll: true });
        this.touches.set(event.pointerId, { x: event.clientX, y: event.clientY });
        canvas.setPointerCapture(event.pointerId);
        this.rebaseTouches();
        return;
      }
      if (this.touches.size) return;
      if (event.button === 1) {
        event.preventDefault();
        this.clear(false);
        canvas.focus({ preventScroll: true });
        if (camera.mode === 'orbit') camera.resetSway();
        return;
      }
      if ((event.button !== 0 && event.button !== 2) || this.pointer !== null) return;
      if (event.button === 2 && camera.mode === 'free') return;
      event.preventDefault();
      canvas.focus({ preventScroll: true });
      this.pointer = event.pointerId;
      this.dragButton = event.button;
      this.lastX = event.clientX;
      this.lastY = event.clientY;
      canvas.setPointerCapture(event.pointerId);
    }, options);
    canvas.addEventListener('pointermove', (event) => {
      if (this.touches.has(event.pointerId)) {
        event.preventDefault();
        this.touches.set(event.pointerId, { x: event.clientX, y: event.clientY });
        return;
      }
      if (event.pointerId !== this.pointer) return;
      // Pointerup fires only when the last mouse button is released. Detect
      // release of our initiating button even when another remains held.
      if ((event.buttons & (this.dragButton === 0 ? 1 : 2)) === 0) {
        this.releasePointer();
        return;
      }
      const dx = event.clientX - this.lastX, dy = event.clientY - this.lastY;
      if (this.dragButton === 0 && camera.mode === 'orbit') camera.orbit(dx, dy);
      else camera.look(dx, dy);
      this.lastX = event.clientX;
      this.lastY = event.clientY;
    }, options);
    for (const type of ['pointerup', 'pointercancel', 'lostpointercapture'] as const) {
      canvas.addEventListener(type, (event) => {
        if (this.touches.has(event.pointerId)) {
          if (type !== 'pointerup') { this.clear(); return; }
          this.updateTouches();
          this.touches.delete(event.pointerId);
          if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
          // Fingers lift one at a time: rebase the remaining contact without
          // discarding the pinch's smooth zoom target or normal release inertia.
          this.touchGesture = this.measureTouches();
          return;
        }
        if (event.pointerId === this.pointer) this.releasePointer();
      }, options);
    }
    canvas.addEventListener('wheel', (event) => {
      event.preventDefault();
      // DOM deltaY has the opposite sign to GLFW OffsetY. Normalize wheel and
      // trackpad units to notches while retaining fractional input.
      const notches = event.deltaMode === 1 ? event.deltaY / 3
        : event.deltaY * (event.deltaMode === 2 ? canvas.clientHeight : 1) / 100;
      camera.scroll(-Math.max(-10, Math.min(10, notches)));
    }, { ...options, passive: false });
    canvas.addEventListener('blur', () => this.clear(), options);
    window.addEventListener('blur', () => this.clear(), options);
    document.addEventListener('visibilitychange', () => { if (document.hidden) this.clear(); }, options);
  }

  update(seconds: number): void {
    // Consume both pointers together. Processing each event as a complete
    // gesture makes a symmetric pinch briefly look like a right-button drag.
    this.updateTouches();
    const axis = (positive: string, negative: string) => Number(this.keys.has(positive)) - Number(this.keys.has(negative));
    if (!this.trajectoryActive()) this.camera.move(axis('KeyD', 'KeyA'), axis('KeyR', 'KeyF'), axis('KeyW', 'KeyS'), seconds,
      this.keys.has('ShiftLeft') || this.keys.has('ShiftRight'));
    this.camera.roll(axis('KeyE', 'KeyQ'), seconds);
    this.camera.update(seconds);
  }

  clear(cancelMotion = true): void {
    this.keys.clear();
    this.releasePointer();
    const pointers = [...this.touches.keys()];
    this.touches.clear();
    this.touchGesture = null;
    for (const pointer of pointers) {
      if (this.canvas.hasPointerCapture(pointer)) this.canvas.releasePointerCapture(pointer);
    }
    if (cancelMotion) this.camera.cancelMotion();
  }

  dispose(): void {
    this.controller.abort();
    this.clear();
  }

  private releasePointer(): void {
    const pointer = this.pointer;
    this.pointer = null;
    if (pointer !== null && this.canvas.hasPointerCapture(pointer)) this.canvas.releasePointerCapture(pointer);
  }

  private measureTouches(): { x: number; y: number; distance: number } | null {
    if (this.touches.size < 1 || this.touches.size > 2) return null;
    const [a, b] = [...this.touches.values()];
    return b ? { x: (a.x+b.x)/2, y: (a.y+b.y)/2, distance: Math.hypot(b.x-a.x,b.y-a.y) }
      : { ...a, distance: 0 };
  }

  private rebaseTouches(): void {
    // A new contact starts a gesture at the current pose. Stop previous motion
    // so a one-finger orbit cannot bleed into a newly started two-finger look.
    this.camera.cancelMotion();
    this.touchGesture = this.measureTouches();
  }

  private updateTouches(): void {
    const current = this.measureTouches(), previous = this.touchGesture;
    this.touchGesture = current;
    if (!current || !previous) return;
    const dx = current.x-previous.x, dy = current.y-previous.y;
    if (this.touches.size === 1) {
      if (this.camera.mode === 'orbit') this.camera.orbit(dx,dy);
      else this.camera.look(dx,dy);
      return;
    }
    // Match the right mouse button (inactive in free-flight mode).
    if (this.camera.mode === 'orbit') this.camera.look(dx,dy);
    if (previous.distance >= 8 && current.distance >= 8) {
      // Spread by a factor of two -> half the orbit radius. Reuse the wheel's
      // 1.2-per-notch conversion and its free-flight speed behavior.
      const notches = Math.log(current.distance/previous.distance)/Math.log(1.2);
      this.camera.scroll(Math.max(-10,Math.min(10,notches)));
    }
  }
}
