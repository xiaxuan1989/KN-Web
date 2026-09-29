export type Vec3 = [number, number, number];
export type CameraMode = 'orbit' | 'free';

// Application.cpp:727,3272 overrides Camera.cpp's constructor value 30 with
// camsmth=1 every frame. Roll keeps Camera.cpp's separate 1/3 coefficient.
const ROTATION_DAMPING = 1;
const ROLL_DAMPING = 1 / 3;
const DISTANCE_DAMPING = 9.6;

const dot = (a: Vec3, b: Vec3): number => a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
const cross = (a: Vec3, b: Vec3): Vec3 => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
const normalize = (v: Vec3): Vec3 => v.map((x) => x / Math.hypot(...v)) as Vec3;
const combine = (a: Vec3, b: Vec3, x: number, y: number): Vec3 => a.map((v, i) => x*v+y*b[i]) as Vec3;

export interface CameraBasis {
  position: Vec3;
  forward: Vec3;
  right: Vec3;
  up: Vec3;
}

export class Camera {
  position: Vec3 = [0, 2, 10];
  yaw = 0;
  pitch = -Math.atan2(2, 10);
  private swayYaw = 0;
  private swayPitch = 0;
  private swayRoll = 0;
  private targetSwayYaw = 0;
  private targetSwayPitch = 0;
  private targetSwayRoll = 0;
  private pendingX = 0;
  private pendingY = 0;
  private pendingRoll = 0;
  private currentMode: CameraMode = 'orbit';
  private freeFrame?: CameraBasis;
  private targetOrbitDistance?: number;
  private movementSpeed = 3;

  get mode(): CameraMode { return this.currentMode; }

  reset(): void {
    this.position = [0, 2, 10];
    this.yaw = 0;
    this.pitch = -Math.atan2(2, 10);
    this.currentMode = 'orbit';
    this.freeFrame = undefined;
    this.movementSpeed = 3;
    this.clearSway();
    this.cancelMotion();
  }

  toggleMode(): void {
    this.cancelMotion();
    const frame = this.basis();
    if (this.mode === 'orbit') {
      this.freeFrame = frame;
      this.currentMode = 'free';
      return;
    }
    // Keep the black hole as the Web scene's orbit target. Reconstruct local
    // sway (including any free-flight roll) so switching never snaps the view.
    const radius = Math.hypot(...this.position);
    if (radius > 1e-9) {
      this.yaw = Math.atan2(-this.position[0], this.position[2]);
      this.pitch = Math.asin(Math.max(-1, Math.min(1, -this.position[1]/radius)));
    }
    this.currentMode = 'orbit';
    this.clearSway();
    const base = this.basis();
    this.swayYaw = Math.atan2(dot(frame.forward, base.right), dot(frame.forward, base.forward));
    this.swayPitch = Math.asin(Math.max(-1, Math.min(1, dot(frame.forward, base.up))));
    const unrolled = this.basis();
    this.swayRoll = Math.atan2(dot(frame.right, unrolled.up), dot(frame.right, unrolled.right));
    this.freeFrame = undefined;
    this.cancelMotion();
  }

  // NPGS Camera.cpp: ProcessOrbital keeps position on a sphere around the
  // target, while ProcessSwayMovement changes the local viewing offset only.
  orbit(deltaX: number, deltaY: number): void {
    if (this.mode !== 'orbit') return;
    this.pendingX += deltaX;
    this.pendingY += deltaY;
  }

  private applyOrbit(deltaX: number, deltaY: number): void {
    const radius = Math.hypot(...this.position);
    if (radius < 1e-9 || (deltaX === 0 && deltaY === 0)) return;
    this.yaw = (Math.atan2(-this.position[0], this.position[2]) - deltaX * 0.003) % (2 * Math.PI);
    const limit = Math.PI / 2 - 0.01;
    this.pitch = Math.max(-limit, Math.min(limit, Math.asin(-this.position[1] / radius) + deltaY * 0.003));
    const cp = Math.cos(this.pitch);
    this.position = [-radius * Math.sin(this.yaw) * cp, -radius * Math.sin(this.pitch), radius * Math.cos(this.yaw) * cp];
  }

  look(deltaX: number, deltaY: number): void {
    if (this.mode === 'free') {
      this.pendingX += deltaX;
      this.pendingY += deltaY;
      return;
    }
    // Keep targets unwrapped: wrapping just the target creates a full-turn
    // reversal when current and target straddle the ±pi / 2pi boundary.
    this.targetSwayYaw += deltaX * 0.003;
    const limit = 89 * Math.PI / 180;
    this.targetSwayPitch = Math.max(-limit, Math.min(limit, this.targetSwayPitch - deltaY * 0.003));
  }

  resetSway(): void {
    this.targetSwayYaw = 0;
    this.targetSwayPitch = 0;
    this.targetSwayRoll = 0;
  }

  // Camera.inl::ProcessMouseScroll: positive offset is wheel-up. Orbit changes
  // distance, free flight changes speed; neither operation changes the lens.
  scroll(offsetY: number): void {
    if (!Number.isFinite(offsetY) || offsetY === 0) return;
    if (this.mode === 'free') {
      this.movementSpeed = Math.max(1e-4, Math.min(1e6, this.movementSpeed * Math.pow(1.2, offsetY)));
      return;
    }
    const radius = Math.hypot(...this.position);
    if (radius < 1e-9) return;
    const target = this.targetOrbitDistance ?? radius;
    this.targetOrbitDistance = Math.max(1e-4, Math.min(1e6, target * Math.pow(1.2, -offsetY)));
  }

  private clearSway(): void {
    this.swayYaw = 0;
    this.swayPitch = 0;
    this.swayRoll = 0;
    this.resetSway();
  }

  roll(direction: number, seconds: number): void {
    if (this.mode !== 'free' || !direction) return;
    this.pendingRoll += direction * 75 * Math.PI / 180 * Math.min(0.05, Math.max(0, seconds));
  }

  // Match NPGS ProcessTimeEvolution: accumulate requested angles, then consume
  // 1-exp(-k*dt) each frame, including frames after mouse/key release.
  update(seconds: number): void {
    const dt = Math.min(0.05, Math.max(0, seconds));
    if (!dt) return;
    const rotationFactor = -Math.expm1(-ROTATION_DAMPING * dt);
    const rollFactor = -Math.expm1(-ROLL_DAMPING * dt);
    const consume = (pending: number, factor: number): number => Math.abs(pending) < 1e-10 ? pending : pending * factor;
    const dx = consume(this.pendingX, rotationFactor), dy = consume(this.pendingY, rotationFactor);
    this.pendingX -= dx;
    this.pendingY -= dy;
    if (this.mode === 'orbit') {
      if (this.targetOrbitDistance !== undefined) {
        const radius = Math.hypot(...this.position);
        if (radius > 1e-9) {
          const difference = this.targetOrbitDistance - radius;
          const next = Math.abs(difference) < 1e-10 * Math.max(1, radius)
            ? this.targetOrbitDistance
            : radius + difference * Math.min(1, DISTANCE_DAMPING * dt);
          // Radial dolly, independent of right-button sway: orientation and
          // background ray directions are unchanged when zooming alone.
          this.position = this.position.map((value) => value * next / radius) as Vec3;
          if (next === this.targetOrbitDistance) this.targetOrbitDistance = undefined;
        }
      }
      this.swayYaw += consume(this.targetSwayYaw - this.swayYaw, rotationFactor);
      this.swayPitch += consume(this.targetSwayPitch - this.swayPitch, rotationFactor);
      this.swayRoll += consume(this.targetSwayRoll - this.swayRoll, rotationFactor);
      this.applyOrbit(dx, dy);
    } else {
      const roll = consume(this.pendingRoll, rollFactor);
      this.pendingRoll -= roll;
      if (dx !== 0 || dy !== 0 || roll !== 0) this.applyFreeRotation(dx, dy, roll);
    }
  }

  // Used only at lifecycle boundaries, not ordinary button/key release.
  cancelMotion(): void {
    this.targetOrbitDistance = undefined;
    this.pendingX = 0;
    this.pendingY = 0;
    this.pendingRoll = 0;
    this.targetSwayYaw = this.swayYaw;
    this.targetSwayPitch = this.swayPitch;
    this.targetSwayRoll = this.swayRoll;
  }

  private applyFreeRotation(deltaX: number, deltaY: number, roll: number): void {
    const frame = this.freeFrame!;
    // Inverse of original view Yaw*Pitch*Roll: camera-to-world applies
    // inverse Roll, then inverse Pitch, then inverse Yaw in its local frame.
    const rolledRight = combine(frame.right, frame.up, Math.cos(roll), -Math.sin(roll));
    const rolledUp = cross(rolledRight, frame.forward);
    const yaw = deltaX * 0.003, pitch = deltaY * 0.003;
    const pitchForward = combine(frame.forward, rolledUp, Math.cos(pitch), Math.sin(pitch));
    const right = combine(rolledRight, pitchForward, Math.cos(yaw), Math.sin(yaw));
    const forward = normalize(combine(pitchForward, rolledRight, Math.cos(yaw), -Math.sin(yaw)));
    const up = normalize(cross(right, forward));
    this.freeFrame = { position: [...this.position], forward, right: normalize(cross(forward, up)), up };
  }

  basis(): CameraBasis {
    if (this.mode === 'free') {
      const frame = this.freeFrame!;
      return { position: [...this.position], forward: [...frame.forward], right: [...frame.right], up: [...frame.up] };
    }
    const cy = Math.cos(this.yaw), sy = Math.sin(this.yaw);
    const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch);
    // Right-handed coordinates: +Y up; initial view toward -Z.
    const forward: Vec3 = [sy * cp, sp, -cy * cp];
    const right: Vec3 = [cy, 0, sy];
    const up: Vec3 = [-sy * sp, cp, cy * sp];
    const ys = Math.sin(this.swayYaw), yc = Math.cos(this.swayYaw);
    const ps = Math.sin(this.swayPitch), pc = Math.cos(this.swayPitch);
    // Equivalent to NPGS Cam2WorldBase * SwayYaw * SwayPitch; offsets live
    // in the orbital frame, so an orbit never discards a right-drag head turn.
    const localToWorld = (x: number, y: number, z: number): Vec3 => [0, 1, 2].map(
      (axis) => x * right[axis] + y * up[axis] + z * forward[axis],
    ) as Vec3;
    const lookRight = localToWorld(yc, 0, -ys);
    const lookUp = localToWorld(-ys * ps, pc, -yc * ps);
    return {
      position: [...this.position],
      forward: localToWorld(ys * pc, ps, yc * pc),
      right: combine(lookRight, lookUp, Math.cos(this.swayRoll), Math.sin(this.swayRoll)),
      up: combine(lookUp, lookRight, Math.cos(this.swayRoll), -Math.sin(this.swayRoll)),
    };
  }

  move(right: number, up: number, forward: number, seconds: number, fast: boolean): void {
    if (this.mode === 'orbit') {
      const radians = 90 * Math.PI / 180 * Math.min(0.05, Math.max(0, seconds));
      this.orbit(right * radians / 0.003, -forward * radians / 0.003);
      return;
    }
    const length = Math.hypot(right, up, forward);
    if (!length) return;
    const basis = this.basis();
    // Clamp stalled frames; diagonal movement has the same speed as one axis.
    const distance = Math.min(0.05, Math.max(0, seconds)) * this.movementSpeed * (fast ? 5 : 1) / length;
    for (let axis = 0; axis < 3; axis++) {
      this.position[axis] += distance * (
        right * basis.right[axis] + up * basis.up[axis] + forward * basis.forward[axis]
      );
    }
  }
}
