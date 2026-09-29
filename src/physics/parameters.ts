export type DebugView = 0 | 1 | 2 | 3 | 4 | 5;

export interface Parameters {
  frequencyShift: boolean;
  backShiftMax: number;
  backgroundBrightness: number;
  postProcessing: boolean;
  taa: boolean;
  timeRate: number;
  bloom: boolean;
  exposure: number;
  gamma: number;
  bloomStrength: number;
  background: 'sky' | 'grid';
  massSolar: number;
  spin: number;
  charge: number;
  fovDegrees: number;
  quality: number;
  fitWindow: boolean;
  renderWidth: number;
  renderHeight: number;
  prepass: boolean;
  debugView: DebugView;
}

// Match NPGS: mass in solar masses, spin a* and charge Q* dimensionless.
// Positions are in Rs; the later geometry port will use CONST_M = 0.5.
export const DEFAULT_PARAMETERS: Readonly<Parameters> = Object.freeze({
  frequencyShift: true, backShiftMax: 1.5, backgroundBrightness: 2,
  postProcessing: true, taa: true, timeRate: 1, bloom: true,
  exposure: 0, gamma: 2.2, bloomStrength: 0.08,
  background: 'sky',
  massSolar: 4_000_000,
  spin: 0.8,
  charge: 0.4,
  fovDegrees: 60,
  quality: 1,
  fitWindow: true, renderWidth: 1280, renderHeight: 960, prepass: true,
  debugView: 3,
});

export const PARAMETER_LIMITS = {
  backShiftMax: [1, 16],
  backgroundBrightness: [0, 100],
  timeRate: [-1e6, 1e6],
  exposure: [-8, 8],
  gamma: [1, 3],
  bloomStrength: [0, 0.5],
  massSolar: [0.1, 1e10],
  spin: [-1.5, 1.5],
  charge: [-1.5, 1.5],
  fovDegrees: [15, 120],
  quality: [0.25, 4],
  renderWidth: [1, 8192],
  renderHeight: [1, 8192],
} as const;

export type NumericParameter = keyof typeof PARAMETER_LIMITS;

export function setParameter(parameters: Parameters, key: NumericParameter, value: number): boolean {
  if (!Number.isFinite(value)) return false;
  const [min, max] = PARAMETER_LIMITS[key];
  if (key === 'renderWidth' || key === 'renderHeight') value = Math.round(value);
  parameters[key] = Math.min(max, Math.max(min, value));
  return true;
}
