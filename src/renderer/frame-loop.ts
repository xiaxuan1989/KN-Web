interface FrameLoopCallbacks {
  draw: (time: number) => void;
  waitForGpu: () => Promise<unknown>;
  completed: (time: number) => void;
  failed: (error: unknown) => void;
}

const MAX_FRAMES_IN_FLIGHT = 2;

// Yield a task between submissions so input and canvas presentation can run
// without RAF pacing. Prepare the next frame while the GPU finishes earlier
// work, but bound the queue to avoid accumulating latency.
export class FrameLoop {
  private running = false;
  private disposed = false;
  private scheduled = false;
  private inFlight = 0;
  private faulted = false;
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
    if (this.disposed || this.faulted) return;
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
    if (!this.running || this.disposed || this.scheduled || this.inFlight >= MAX_FRAMES_IN_FLIGHT) return;
    this.scheduled = true;
    this.channel.port2.postMessage(null);
  }

  private async frame(): Promise<void> {
    if (!this.running || this.disposed || this.inFlight >= MAX_FRAMES_IN_FLIGHT) return;
    this.inFlight++;
    const generation = this.generation;
    try {
      this.callbacks.draw(this.now());
      // Capture this submission's completion before scheduling another draw.
      // Each invocation owns one slot and counts exactly one rendered frame;
      // onSubmittedWorkDone also covers earlier work, which is not recounted.
      const completion = this.callbacks.waitForGpu();
      this.schedule();
      await completion;
      if (this.running && !this.disposed && this.generation === generation) {
        this.callbacks.completed(this.now());
      }
    } catch (error) {
      if (!this.disposed && !this.faulted) {
        this.faulted = true;
        this.pause();
        this.callbacks.failed(error);
      }
    } finally {
      // Keep outstanding slots across pause/resume; old completions release
      // capacity without entering the new generation's FPS measurement.
      this.inFlight--;
      this.schedule();
    }
  }
}

// Completed rendering throughput, independent of the display refresh rate.
// Normalize by actual elapsed time, including delayed completion callbacks.
export class CompletedFpsCounter {
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
    const elapsed = time - this.previousTime;
    if (elapsed < 1000) return false;
    this.value = Math.round(this.frames * 1000 / elapsed);
    this.frames = 0;
    this.previousTime = time;
    return true;
  }
}
