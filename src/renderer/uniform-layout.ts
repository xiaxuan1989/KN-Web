import type { CameraBasis } from '../camera/camera.ts';
import type { TetradFrame } from '../physics/observer-trajectory.ts';
import { radiusLightYears } from './temporal.ts';
import type { Parameters } from '../physics/parameters.ts';

// Byte sizes and float-word offsets are documented in docs/uniform-layout.md.
export const UNIFORM_SIZES = [32, 48, 144] as const;

export interface FrameData {
  width: number;
  height: number;
  time: number;
  deltaTime: number;
  simulationTime?: number; // original GameTime, seconds scaled by TimeRate
  tetrad?: TetradFrame;
  cameraVelocity?: readonly [number,number,number];
  jitter?: readonly [number, number];
  postProcessing?: boolean;
}

// NPGS allocates floor(full/2), clamped to 1, but passes full*0.5 as
// Resolution. Do not substitute the integer attachment size, even at 1x1.
export function prepassFrame(frame: FrameData): FrameData {
  return { ...frame, width: frame.width * 0.5, height: frame.height * 0.5,
    jitter: [0.5 * (frame.jitter?.[0] ?? 0), 0.5 * (frame.jitter?.[1] ?? 0)] };
}

export class UniformData {
  readonly game = new Float32Array(8);
  readonly gameIntegers = new Uint32Array(this.game.buffer);
  readonly blackHole = new Float32Array(12);
  readonly camera = new Float32Array(36);

  update(frame: FrameData, parameters: Parameters, camera: CameraBasis): void {
    this.game.set([frame.width, frame.height, parameters.fovDegrees * Math.PI / 180, frame.time,
      frame.deltaTime, parameters.quality, 0, Number(frame.postProcessing ?? false)]);
    this.gameIntegers[6] = parameters.debugView;
    this.blackHole.set([parameters.massSolar, parameters.spin, parameters.charge, parameters.observerMode,
      Number(parameters.frequencyShift), parameters.backShiftMax, parameters.backgroundBrightness, Number(!parameters.prepass), parameters.spatialGrid,
      frame.tetrad?.position[3] ?? (frame.simulationTime ?? frame.time)*299792458/radiusLightYears(parameters.massSolar)/9460730472580800, parameters.debugView === 4 ? 3 : parameters.nativeDebug, 0]);
    this.camera.fill(0);
    this.camera.set([...camera.position, 0, ...camera.forward, 0, ...camera.right, frame.jitter?.[0] ?? 0, ...camera.up, frame.jitter?.[1] ?? 0]);
    this.camera.set([...(parameters.manualVelocity ? [parameters.velocityX,parameters.velocityY,parameters.velocityZ] : frame.cameraVelocity ?? [0,0,0]),0],16);
    if (frame.tetrad) {
      const t = frame.tetrad;
      this.camera.set(t.position,0);
      this.camera.set([0,0,0,Number(t.outgoing)],16);
      this.camera.set([...t.U,...t.e1,...t.e2,...t.e3],20);
    }
  }

  // Semantic values read by the verification shader, including u32 -> f32.
  expectedReadback(): Float32Array {
    const expected = new Float32Array([...this.game, ...this.blackHole, ...this.camera]);
    expected[6] = this.gameIntegers[6];
    return expected;
  }
}
