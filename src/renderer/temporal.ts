import type { CameraBasis, Vec3 } from '../camera/camera.ts';

const f = Math.fround;
const LIGHT_YEAR = 9460730472580800;
const LIGHT_SPEED = 299792458;
// Keep the original C++ float constants, not updated astronomical constants.
export function radiusLightYears(massSolar: number): number {
  return f(2 * Math.abs(f(massSolar)) * f(6.6743e-11) / LIGHT_SPEED ** 2 * f(1.9884e30) / LIGHT_YEAR);
}
export function blendWeight(dt: number, massSolar: number, timeRate: number): number {
  const timescale = Math.max(Math.min(0.131 * 36 / f(timeRate) * (radiusLightYears(massSolar) / 0.00000465), 0.5), 0.06);
  return f(1 - Math.pow(0.5, dt / timescale));
}

export interface TemporalCamera {
  rotation: number[]; // column-major InverseCamRot 3x3
  relative: Vec3; // black-hole position in camera coordinates / Rs
  world: Vec3; // camera position in light years
}
export function temporalCamera(camera: CameraBasis, massSolar: number): TemporalCamera {
  const rotation = [...camera.right, ...camera.up, ...camera.forward.map(v => -v)].map(f);
  const rs = radiusLightYears(massSolar);
  const world = camera.position.map(v => f(v * rs)) as Vec3;
  const relative = [0,1,2].map(column => {
    const dot = f(f(f(rotation[column*3]*world[0]) + f(rotation[column*3+1]*world[1])) + f(rotation[column*3+2]*world[2]));
    return f(-dot/rs);
  }) as Vec3;
  return { rotation, relative, world };
}

// GLM quat_cast(mat3(previous-current)).w. The input is a MATRIX DIFFERENCE,
// not a relative rotation. Preserve the original test rather than reinterpret it.
export function differenceQuaternionW(previous: number[], current: number[]): number {
  const m = previous.map((v,i) => f(v-current[i]));
  const candidates = [f(f(m[0]+m[4])+m[8]), f(f(m[0]-m[4])-m[8]),
    f(f(m[4]-m[0])-m[8]), f(f(m[8]-m[0])-m[4])];
  let largest = 0;
  for (let i=1; i<4; i++) if (candidates[i]! > candidates[largest]!) largest = i;
  const value = f(f(Math.sqrt(f(candidates[largest]!+1)))*0.5);
  if (largest === 0) return value;
  const numerator = largest === 1 ? f(m[5]-m[7]) : largest === 2 ? f(m[6]-m[2]) : f(m[1]-m[3]);
  return f(numerator*f(0.25/value));
}
const norm = (v: readonly number[]): number => {
  const squared = f(f(f(v[0]*v[0])+f(v[1]*v[1]))+f(v[2]*v[2]));
  return f(Math.sqrt(squared));
};
export function motionRequiresCurrent(previous: TemporalCamera, current: TemporalCamera, velocity: Vec3, dt: number): boolean {
  const w = differenceQuaternionW(previous.rotation,current.rotation);
  const rotationStable = Math.abs(w-0.5) < 0.001*dt || Math.abs(w) < 0.001*dt;
  const displacement = norm(previous.relative.map((v,i) => f(v-current.relative[i])));
  return !rotationStable || displacement > (norm(previous.relative)-1)*0.006*dt || norm(velocity) > 0.0001;
}
export function smoothCameraVelocity(previous: TemporalCamera, current: TemporalCamera, velocity: Vec3,
  dt: number, previousDt: number, timeRate: number): Vec3 {
  const factor = f(1-Math.exp(-dt/0.1));
  const scale = f(LIGHT_YEAR/f(previousDt*timeRate*LIGHT_SPEED));
  const next = velocity.map((v,i) => {
    const instantaneous = f(f(current.world[i]-previous.world[i])*scale);
    return f(v+f(f(instantaneous-v)*factor));
  }) as Vec3;
  return next.every(Number.isFinite) ? next : [0,0,0];
}

export class TemporalState {
  private previous?: TemporalCamera;
  private previousDt = 0;
  private velocity: Vec3 = [0,0,0];
  private frames = 0;
  private enabled = false;
  cameraVelocity(): Vec3 { return [...this.velocity]; }
  reset(): void { this.previous = undefined; this.previousDt = 0; this.velocity = [0,0,0]; this.frames = 0; this.enabled = false; }
  next(camera: CameraBasis, massSolar: number, timeRate: number, dt: number, enabled: boolean, velocityOverride?: Vec3): { weight: number; jitter: [number,number] } {
    const current = temporalCamera(camera,massSolar);
    this.frames++;
    if (this.previous) {
      // Application.cpp initializes CameraVelocity to zero for its first 10 frames.
      this.velocity = this.frames <= 10 ? [0,0,0]
        : smoothCameraVelocity(this.previous,current,this.velocity,dt,this.previousDt,timeRate);
    }
    const moving = this.previous && motionRequiresCurrent(this.previous,current,velocityOverride ?? this.velocity,dt);
    const weight = !enabled || !this.enabled || !this.previous || dt <= 0 || moving ? 1 : blendWeight(dt,massSolar,timeRate);
    this.enabled = enabled;
    this.previous = current;
    this.previousDt = dt;
    // BlackHole_common.glsl multiplies its random jitter by zero.
    return { weight, jitter: [0,0] };
  }
}
