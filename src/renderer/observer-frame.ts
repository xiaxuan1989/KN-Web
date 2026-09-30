import type { CameraBasis } from '../camera/camera.ts';
import type { Parameters } from '../physics/parameters.ts';
import type { ObserverTrajectory } from '../physics/observer-trajectory.ts';
import { TemporalState } from './temporal.ts';

// Application.cpp: ordinary camera -> velocity / TAA -> trajectory integration
// -> transported uniforms / zero velocity -> LastCameraWorldPos. Both the
// renderer and the host-sequence oracle use this production entry point.
export function advanceObserverFrame(
  temporal: TemporalState, camera: CameraBasis, parameters: Parameters,
  dt: number, taaEnabled: boolean, trajectory?: ObserverTrajectory,
): { weight: number; jitter: [number,number] } {
  const p = parameters;
  // Manual velocity initializes the trajectory; it must not replace the native
  // camera velocity in every subsequent four-dimensional TAA evaluation.
  const velocity = p.manualVelocity && !trajectory
    ? [p.velocityX,p.velocityY,p.velocityZ] as [number,number,number] : undefined;
  const frame = temporal.next(camera,p.massSolar,p.timeRate,dt,taaEnabled,velocity);
  if (trajectory) {
    trajectory.charge = Math.fround(p.observerCharge);
    trajectory.advance(dt,p.timeRate,p.massSolar,p.spin*.5,p.charge*.5);
    temporal.finishTrajectory(trajectory.state,p.massSolar);
  }
  return frame;
}
