import { radiusLightYears } from '../renderer/temporal.ts';

export type DebugView = 0 | 1 | 2 | 3 | 4 | 5;

export interface Parameters {
  maximalExtension: boolean;
  specializeExtension: boolean;
  specializeDiagnostics: boolean;
  universeSign: 1 | -1;
  universeIndex: 0 | 1 | 2;
  denseStarEnabled: boolean;
  denseStarRadius: number;
  denseStarBlackbodyIntensityExponent: number;
  denseStarRedshiftColorExponent: number;
  denseStarRedshiftIntensityExponent: number;
  denseStarBrightness: number;
  diskEnabled: boolean;
  jetEnabled: boolean;
  diskInnerRadius: number;
  diskOuterRadius: number;
  diskThickness: number;
  diskHopper: number;
  matterMu: number;
  accretionRate: number;
  diskBrightness: number;
  diskOpacity: number;
  reddening: number;
  diskSaturation: number;
  blackbodyIntensityExponent: number;
  redshiftColorExponent: number;
  redshiftIntensityExponent: number;
  photonRingBoost: number;
  photonRingTemperatureBoost: number;
  boostRotation: number;
  jetRedshiftIntensityExponent: number;
  jetBrightness: number;
  jetSaturation: number;
  jetShiftMax: number;
  nativeDebug: 0 | 1 | 2 | 3 | 4 | 5 | 6;
  spatialGrid: -1 | 0 | 1 | 2;
  observerMode: -1 | 0 | 1 | 2 | 3;
  observerThrust: number;
  observerCharge: number;
  boostRapidity: number;
  manualVelocity: boolean;
  velocityX: number;
  velocityY: number;
  velocityZ: number;
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
// GPU positions are in Rs (CONST_M = 0.5); camera motion preserves native world ly.
export const DEFAULT_PARAMETERS: Readonly<Parameters> = Object.freeze({
  // Native Application.cpp startup configuration: inner > outer and rate below
  // the jet visibility threshold. Preserve these values and the existing sky.
  maximalExtension: false, specializeExtension: true, specializeDiagnostics: true, universeSign: 1, universeIndex: 0,
  denseStarEnabled: false, denseStarRadius: 0,
  denseStarBlackbodyIntensityExponent: 4, denseStarRedshiftColorExponent: 1,
  denseStarRedshiftIntensityExponent: 4, denseStarBrightness: 1,
  diskEnabled: false, jetEnabled: false,
  diskInnerRadius: 200, diskOuterRadius: 25, diskThickness: 0.75, diskHopper: 0.4,
  matterMu: 1, accretionRate: 1e-12, diskBrightness: 1, diskOpacity: 0.5,
  reddening: 0.3, diskSaturation: 0.5, blackbodyIntensityExponent: 1,
  redshiftColorExponent: 1, redshiftIntensityExponent: 4,
  photonRingBoost: 0, photonRingTemperatureBoost: 0, boostRotation: 0,
  jetRedshiftIntensityExponent: 4, jetBrightness: 1, jetSaturation: 0, jetShiftMax: 3,
  nativeDebug: 0, spatialGrid: 0,
  observerMode: 0, manualVelocity: false, velocityX: 0, velocityY: 0, velocityZ: 0,
  observerThrust: 1.5, observerCharge: 0, boostRapidity: 0,
  frequencyShift: true, backShiftMax: 1.5, backgroundBrightness: 2,
  postProcessing: true, taa: true, timeRate: 1, bloom: true,
  exposure: 0, gamma: 2.2, bloomStrength: 0.08,
  background: 'sky',
  massSolar: 14_900_000,
  spin: 0.998,
  charge: 0,
  fovDegrees: 80,
  quality: 1,
  fitWindow: true, renderWidth: 1280, renderHeight: 960, prepass: true,
  debugView: 3,
});

// Native throttle controls have no fixed caps. Zero endpoints for mass,
// quality and FOV are excluded below; Web-only display controls retain their ranges.
export const PARAMETER_LIMITS = {
  denseStarRadius: [-Infinity, Infinity],
  denseStarBlackbodyIntensityExponent: [0, Infinity], denseStarRedshiftColorExponent: [0, Infinity],
  denseStarRedshiftIntensityExponent: [0, Infinity], denseStarBrightness: [0, Infinity],
  diskInnerRadius: [0, Infinity], diskOuterRadius: [0, Infinity],
  diskThickness: [0, Infinity], diskHopper: [0, Infinity],
  matterMu: [0, Infinity], accretionRate: [0, Infinity],
  diskBrightness: [0, Infinity], diskOpacity: [0, Infinity],
  reddening: [0, Infinity], diskSaturation: [0, Infinity],
  blackbodyIntensityExponent: [0, Infinity], redshiftColorExponent: [0, Infinity],
  redshiftIntensityExponent: [0, Infinity],
  photonRingBoost: [0, 10], photonRingTemperatureBoost: [0, 10], boostRotation: [-Infinity, Infinity],
  jetRedshiftIntensityExponent: [0, Infinity], jetBrightness: [0, Infinity],
  jetSaturation: [0, Infinity], jetShiftMax: [0, Infinity],
  observerCharge: [-2, 2],
  velocityX: [-Infinity, Infinity], velocityY: [-Infinity, Infinity], velocityZ: [-Infinity, Infinity],
  backShiftMax: [1, 10000],
  backgroundBrightness: [0, Infinity],
  timeRate: [-Infinity, Infinity],
  exposure: [-8, 8],
  gamma: [1, 3],
  bloomStrength: [0, 0.5],
  massSolar: [-Infinity, Infinity],
  spin: [-Infinity, Infinity],
  charge: [-Infinity, Infinity],
  fovDegrees: [0, 180],
  quality: [0, Infinity],
  renderWidth: [1, Number.MAX_SAFE_INTEGER],
  renderHeight: [1, Number.MAX_SAFE_INTEGER],
} as const;

export type NumericParameter = keyof typeof PARAMETER_LIMITS;

export function setParameter(parameters: Parameters, key: NumericParameter, value: number): boolean {
  if (!Number.isFinite(value) || !Number.isFinite(Math.fround(value))) return false;
  if (['matterMu','accretionRate','diskOuterRadius'].includes(key) && Math.fround(value) <= 0) return false;
  if ((key === 'massSolar' && Math.fround(value) === 0) || (key === 'quality' && Math.fround(value) <= 0)) return false;
  if (key === 'massSolar' && radiusLightYears(value) <= 0) return false;
  if (key === 'fovDegrees' && (Math.fround(value) <= 0 || Math.fround(value) >= 180)) return false;
  // Native Count/budget use signed int. Reject overflow rather than wrap the loop.
  if (key === 'quality') {
    const f = Math.fround, quality = f(value);
    const budget = f(f(1145*quality)*f(1+f(f(0.3)*quality)));
    if (budget >= 2147483647) return false;
  }
  const [min, max] = PARAMETER_LIMITS[key];
  if (key === 'renderWidth' || key === 'renderHeight') value = Math.round(value);
  parameters[key] = Math.min(max, Math.max(min, value));
  return true;
}

// A usable model configuration for exploration; native startup values remain
// available in DEFAULT_PARAMETERS. This preset changes only radiation controls.
export function applyEmissionPreset(parameters: Parameters): void {
  Object.assign(parameters, {
    diskEnabled: true, jetEnabled: true, diskInnerRadius: 3, diskOuterRadius: 25,
    diskThickness: 0.75, diskHopper: 0.4, matterMu: 1, accretionRate: 0.1,
    diskBrightness: 1, diskOpacity: 0.5, reddening: 0.3, diskSaturation: 0.5,
    blackbodyIntensityExponent: 1, redshiftColorExponent: 1, redshiftIntensityExponent: 4,
    photonRingBoost: 0, photonRingTemperatureBoost: 0, boostRotation: 0,
    jetRedshiftIntensityExponent: 4, jetBrightness: 1, jetSaturation: 0, jetShiftMax: 3,
  });
}
