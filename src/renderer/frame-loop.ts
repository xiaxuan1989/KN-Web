interface FrameLoopCallbacks {
  draw: (time: number) => void;
  waitForGpu: () => Promise<unknown>;
  completed: (time: number) => void;
  failed: (error: unknown) => void;
}

// NPGS waits for the preceding frame's fence before reusing shared targets.
// A task between frames lets input and canvas presentation run, without RAF
// pacing or a setTimeout nesting clamp. At most one frame is in flight.
export class FrameLoop {
  private running = false;
  private disposed = false;
  private scheduled = false;
  private busy = false;
  private generation = 0;
  private readonly callbacks: FrameLoopCallbacks;
  private readonly now: () => number;
  private readonly channel: MessageChannel;

  constructor(
    callbacks: FrameLoopCallbacks,
    now: () => number = () => performance.now(),
    channel: MessageChannel = new MessageChannel(),
  ) {
    this.callbacks = callbacks;
    this.now = now;
    this.channel = channel;
    channel.port1.onmessage = () => {
      this.scheduled = false;
      void this.frame();
    };
  }

  start(): void {
    if (this.disposed) return;
    this.running = true;
    this.schedule();
  }

  pause(): void {
    this.running = false;
    this.generation++;
  }

  dispose(): void {
    this.pause();
    this.disposed = true;
    this.channel.port1.close();
    this.channel.port2.close();
  }

  private schedule(): void {
    if (!this.running || this.disposed || this.scheduled || this.busy) return;
    this.scheduled = true;
    this.channel.port2.postMessage(null);
  }

  private async frame(): Promise<void> {
    if (!this.running || this.disposed || this.busy) return;
    this.busy = true;
    const generation = this.generation;
    try {
      this.callbacks.draw(this.now());
      await this.callbacks.waitForGpu();
      if (this.running && !this.disposed && this.generation === generation) {
        this.callbacks.completed(this.now());
      }
    } catch (error) {
      if (!this.disposed) {
        this.pause();
        this.callbacks.failed(error);
      }
    } finally {
      this.busy = false;
      this.schedule();
    }
  }
}

// Application.cpp::update: ++FramePerSec; if elapsed >= 1 s, display the
// integer count, clear it, and start the next window at the current time.
export class NativeFpsCounter {
  private previousTime = 0;
  private frames = 0;
  value: number | null = null;

  reset(time: number): void {
    this.previousTime = time;
    this.frames = 0;
    this.value = null;
  }

  completed(time: number): boolean {
    this.frames++;
    if (time - this.previousTime < 1000) return false;
    this.value = this.frames;
    this.frames = 0;
    this.previousTime = time;
    return true;
  }
}
