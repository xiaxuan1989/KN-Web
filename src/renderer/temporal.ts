import type { CameraBasis } from '../camera/camera.ts';
import type { Parameters } from '../physics/parameters.ts';

export const BLOOM_WEIGHTS = [1, 1.5, 1, 1.5, 1.8, 1, 1, 1] as const;
export function bloomSizes(width: number, height: number): [number, number][] {
  const sizes: [number, number][] = [];
  for (let i = 0; i < BLOOM_WEIGHTS.length; i++) {
    width = Math.max(1, Math.floor(width / 2));
    height = Math.max(1, Math.floor(height / 2));
    sizes.push([width, height]);
    if (width === 1 && height === 1) break;
  }
  return sizes;
}

function halton(index: number, base: number): number {
  let value = 0, fraction = 1;
  while (index > 0) {
    fraction /= base;
    value += fraction * (index % base);
    index = Math.floor(index / base);
  }
  return value;
}

// No flat-screen reprojection for curved geodesics: invalidate on any scene change.
// Display-only exposure/bloom edits do not invalidate linear HDR history.
export function historyKey(p: Parameters, camera: CameraBasis, width: number, height: number): string {
  return JSON.stringify([width, height, p.massSolar, p.spin, p.charge, p.fovDegrees, p.quality,
    p.frequencyShift, p.backShiftMax, p.backgroundBrightness, p.fitWindow, p.renderWidth, p.renderHeight, p.prepass, p.debugView, p.background, p.postProcessing, p.taa,
    camera.position, camera.forward, camera.right, camera.up]);
}

export class TemporalState {
  private key = '';
  private count = 0;
  private index = 0;
  reset(): void { this.key = ''; this.count = 0; this.index = 0; }
  next(key: string, enabled: boolean): { weight: number; jitter: [number, number]; samples: number } {
    if (!enabled || key !== this.key) this.reset();
    this.key = key;
    this.count = Math.min(this.count + 1, 32);
    const sample = this.index++ % 32;
    // Centre the first frame (including every moving frame); jitter only stable frames.
    const jitter: [number, number] = enabled && this.count > 1
      ? [halton(sample + 1, 2) - 0.5, halton(sample + 1, 3) - 0.5] : [0, 0];
    return { weight: 1 / this.count, jitter, samples: this.count };
  }
}
