import type { CameraBasis } from '../camera/camera.ts';
import type { Parameters } from '../physics/parameters.ts';

// Byte sizes and float-word offsets are documented in docs/uniform-layout.md.
export const UNIFORM_SIZES = [32, 32, 64] as const;

export interface FrameData {
  width: number;
  height: number;
  time: number;
  deltaTime: number;
  jitter?: readonly [number, number];
  postProcessing?: boolean;
}

export class UniformData {
  readonly game = new Float32Array(8);
  readonly gameIntegers = new Uint32Array(this.game.buffer);
  readonly blackHole = new Float32Array(8);
  readonly camera = new Float32Array(16);

  update(frame: FrameData, parameters: Parameters, camera: CameraBasis): void {
    this.game.set([frame.width, frame.height, parameters.fovDegrees * Math.PI / 180, frame.time,
      frame.deltaTime, parameters.quality, 0, Number(frame.postProcessing ?? false)]);
    this.gameIntegers[6] = parameters.debugView;
    this.blackHole.set([parameters.massSolar, parameters.spin, parameters.charge, 0,
      Number(parameters.frequencyShift), parameters.backShiftMax, parameters.backgroundBrightness, 0]);
    this.camera.set([...camera.position, 0, ...camera.forward, 0, ...camera.right, frame.jitter?.[0] ?? 0, ...camera.up, frame.jitter?.[1] ?? 0]);
  }

  // Semantic values read by the verification shader, including u32 -> f32.
  expectedReadback(): Float32Array {
    const expected = new Float32Array([...this.game, ...this.blackHole, ...this.camera]);
    expected[6] = this.gameIntegers[6];
    return expected;
  }
}
