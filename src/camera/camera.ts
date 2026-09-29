import { radiusLightYears } from '../renderer/temporal.ts';
import { DEFAULT_PARAMETERS } from '../physics/parameters.ts';

export type Vec3 = [number, number, number];
export type CameraMode = 'orbit' | 'free';
export interface CameraBasis { position: Vec3; forward: Vec3; right: Vec3; up: Vec3 }

// Application.cpp constructs FCamera(origin, 0.2, 2.5, 80); world units are ly.
export const MOUSE_RADIANS = 0.2 * Math.PI / 180;
const dot = (a: Vec3,b: Vec3) => a[0]*b[0]+a[1]*b[1]+a[2]*b[2];
const cross = (a: Vec3,b: Vec3): Vec3 => [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const normalize = (v: Vec3): Vec3 => v.map(x=>x/Math.hypot(...v)) as Vec3;
const combine = (a: Vec3,b: Vec3,x: number,y: number): Vec3 => a.map((v,i)=>x*v+y*b[i]) as Vec3;
const dtValue = (dt: number) => Number.isFinite(dt) ? Math.max(0,dt) : 0;

// Rotation taking world +Y to the orbit axis (Camera.cpp::CalculateToAxisRotate).
function axisRotate(v: Vec3,axis: Vec3,inverse=false): Vec3 {
  const n: Vec3 = axis[0] === 0 && axis[2] === 0 ? [1,0,0] : normalize([axis[2],0,-axis[0]]);
  const angle = Math.acos(Math.max(-1,Math.min(1,axis[1]))) * (inverse ? -1 : 1);
  const c=Math.cos(angle),s=Math.sin(angle),nv=cross(n,v),d=dot(n,v)*(1-c);
  return v.map((x,i)=>c*x+s*nv[i]+d*n[i]) as Vec3;
}

export class Camera {
  // Rendering and trajectory APIs use Rs; scale changes preserve world ly.
  position: Vec3 = [0,0,0];
  yaw = 0; // -Theta, radians
  pitch = -Math.PI/4; // Phi - pi/2
  private rs = radiusLightYears(DEFAULT_PARAMETERS.massSolar);
  private currentMode: CameraMode = 'orbit';
  private freeFrame?: CameraBasis;
  private center: Vec3 = [0,0,0];
  private targetCenter: Vec3 = [0,0,0];
  private axis: Vec3 = [0,1,0];
  private targetAxis: Vec3 = [0,1,0];
  private distance = 1/this.rs;
  private targetDistance = Math.fround(.0003)/this.rs;
  private movementSpeed = 2.5/this.rs;
  private sinceModeChange = 10;
  private swayYaw = 0;
  private swayPitch = 0;
  private targetSwayYaw = 0;
  private targetSwayPitch = 0;
  private pendingX = 0;
  private pendingY = 0;
  private pendingRoll = 0;

  constructor() { this.applyOrbit(0,0); }
  get mode(): CameraMode { return this.currentMode; }

  setMass(massSolar: number): void {
    const next=radiusLightYears(massSolar);
    if (!(next>0) || next===this.rs) return;
    const scale=this.rs/next;
    this.position=this.position.map(x=>x*scale) as Vec3;
    this.center=this.center.map(x=>x*scale) as Vec3;
    this.targetCenter=this.targetCenter.map(x=>x*scale) as Vec3;
    this.distance*=scale;this.targetDistance*=scale;this.movementSpeed*=scale;
    this.rs=next;
  }

  reset(): void {
    this.currentMode='orbit';this.freeFrame=undefined;
    this.yaw=0;this.pitch=-Math.PI/4;
    this.center=[0,0,0];this.targetCenter=[0,0,0];this.axis=[0,1,0];this.targetAxis=[0,1,0];
    this.distance=1/this.rs;this.targetDistance=Math.fround(.0003)/this.rs;this.movementSpeed=2.5/this.rs;
    this.swayYaw=0;this.swayPitch=0;this.targetSwayYaw=0;this.targetSwayPitch=0;
    this.pendingX=0;this.pendingY=0;this.pendingRoll=0;this.sinceModeChange=10;
    this.applyOrbit(0,0);
  }

  setTargetOrbitCenter(center: Vec3): void { this.targetCenter=[...center]; }
  setTargetOrbitAxis(axis: Vec3): void {
    if (axis.every(Number.isFinite) && Math.hypot(...axis)>0) this.targetAxis=normalize(axis);
  }

  // Native TeleportOrbit: explicit pose fixture / instant orbit repositioning.
  teleportOrbit(yawDegrees: number,polarDegrees: number,distanceRs?: number): void {
    if (this.mode!=='orbit') return;
    if (distanceRs!==undefined && distanceRs>0 && Number.isFinite(distanceRs)) this.targetDistance=distanceRs;
    this.yaw=-((yawDegrees%360+360)%360)*Math.PI/180;
    this.pitch=(Math.max(0,Math.min(180,polarDegrees))-90)*Math.PI/180;
    this.pendingX=0;this.pendingY=0;this.pendingRoll=0;
    this.swayYaw=0;this.swayPitch=0;this.targetSwayYaw=0;this.targetSwayPitch=0;
    this.distance=this.targetDistance;this.center=[...this.targetCenter];this.axis=[...this.targetAxis];
    this.applyOrbit(0,0);
  }

  // T uses the native strict >0.5s debounce. Programmatic observer switches
  // use toggleMode directly, like the original SetCameraMode path.
  requestModeChange(): boolean {
    if (this.sinceModeChange<=.5) return false;
    this.toggleMode();return true;
  }
  toggleMode(): void {
    this.sinceModeChange=0;
    const frame=this.basis();
    if (this.mode==='orbit') { this.freeFrame=frame;this.currentMode='free';return; }
    this.center=combine(this.position,frame.forward,1,this.distance);
    this.axis=normalize(combine(frame.up,frame.forward,1,-1));
    const right=axisRotate(frame.right,this.axis,true),up=axisRotate(frame.up,this.axis,true),front=axisRotate(frame.forward,this.axis,true);
    this.yaw=-Math.atan2(-right[2],right[0]);
    this.pitch=Math.atan2(up[1],-front[1])-Math.PI/2;
    this.currentMode='orbit';this.freeFrame=undefined;
    this.applyOrbit(0,0);
  }

  orbit(dx: number,dy: number): void {
    if(this.mode==='orbit'){this.pendingX+=dx;this.pendingY+=dy;}
  }
  look(dx: number,dy: number): void {
    if(this.mode==='free'){this.pendingX+=dx;this.pendingY+=dy;return;}
    // Our sway yaw is the negative of the original local Y quaternion angle.
    this.targetSwayYaw+=dx*MOUSE_RADIANS;
    this.targetSwayPitch=Math.max(-89*Math.PI/180,Math.min(89*Math.PI/180,this.targetSwayPitch-dy*MOUSE_RADIANS));
  }
  resetSway(): void { this.targetSwayYaw=0;this.targetSwayPitch=0; }
  scroll(offsetY: number): void {
    if(!Number.isFinite(offsetY))return;
    // Only guard numeric overflow/underflow, not a new physical speed range.
    const candidate=(this.mode==='free'?this.movementSpeed:this.targetDistance)*Math.pow(1.2,this.mode==='free'?offsetY:-offsetY);
    if(!(candidate>0) || !Number.isFinite(candidate))return;
    if(this.mode==='free')this.movementSpeed=candidate;else this.targetDistance=candidate;
  }
  roll(direction: number,seconds: number): void {
    if(this.mode==='free')this.pendingRoll+=direction*75*Math.PI/180*dtValue(seconds);
  }

  update(seconds: number): void {
    const dt=dtValue(seconds),factor=-Math.expm1(-dt);
    const dx=this.pendingX*factor,dy=this.pendingY*factor;
    this.pendingX-=dx;this.pendingY-=dy;
    this.swayYaw+=(this.targetSwayYaw-this.swayYaw)*factor;
    this.swayPitch+=(this.targetSwayPitch-this.swayPitch)*factor;
    if(this.mode==='orbit'){
      this.distance+=(this.targetDistance-this.distance)*Math.min(1,9.6*dt);
      const difference=combine(this.targetAxis,this.axis,1,-1),length=Math.hypot(...difference);
      if(length>0){
        const angle=Math.asin(Math.min(1,length/2));
        if(angle>1e-10){
          let tangent=cross(cross(this.axis,difference),this.axis);
          // Native antipodal cross is zero: select a finite tangent there.
          if(Math.hypot(...tangent)<1e-15)tangent=cross(this.axis,Math.abs(this.axis[0])<.9?[1,0,0]:[0,0,1]);
          this.axis=normalize(combine(this.axis,normalize(tangent),1,Math.min(1,3*dt)*2*angle));
        }
      }
      this.center=combine(this.center,this.targetCenter,1-Math.min(1,3*dt),Math.min(1,3*dt));
      this.applyOrbit(dx,dy);
    }else{
      this.swayYaw=0;this.swayPitch=0;this.targetSwayYaw=0;this.targetSwayPitch=0;
      const roll=this.pendingRoll*(-Math.expm1(-dt/3));this.pendingRoll-=roll;
      if(dx!==0 || dy!==0 || roll!==0)this.applyFreeRotation(dx,dy,roll);
    }
    if(this.sinceModeChange<10)this.sinceModeChange+=dt;
  }

  // Browser focus / visibility boundaries clear unconsumed input. Native T
  // itself preserves it. A reset explicitly reestablishes native startup state.
  cancelMotion(): void {
    this.pendingX=0;this.pendingY=0;this.pendingRoll=0;
    this.targetSwayYaw=this.swayYaw;this.targetSwayPitch=this.swayPitch;
    this.targetDistance=this.distance;
  }

  private applyOrbit(dx: number,dy: number): void {
    this.yaw=(this.yaw-dx*MOUSE_RADIANS)%(2*Math.PI);
    this.pitch=Math.max(-Math.PI/2,Math.min(Math.PI/2,this.pitch+dy*MOUSE_RADIANS));
    const front=axisRotate([Math.sin(this.yaw)*Math.cos(this.pitch),Math.sin(this.pitch),-Math.cos(this.yaw)*Math.cos(this.pitch)],this.axis);
    this.position=combine(this.center,front,1,-this.distance);
  }
  private applyFreeRotation(dx: number,dy: number,roll: number): void {
    const frame=this.freeFrame!;
    const rolledRight=combine(frame.right,frame.up,Math.cos(roll),-Math.sin(roll));
    const rolledUp=cross(rolledRight,frame.forward);
    const yaw=dx*MOUSE_RADIANS,pitch=dy*MOUSE_RADIANS;
    const pitchForward=combine(frame.forward,rolledUp,Math.cos(pitch),Math.sin(pitch));
    const right=combine(rolledRight,pitchForward,Math.cos(yaw),Math.sin(yaw));
    const forward=normalize(combine(pitchForward,rolledRight,Math.cos(yaw),-Math.sin(yaw)));
    const up=normalize(cross(right,forward));
    this.freeFrame={position:[...this.position],forward,right:normalize(cross(forward,up)),up};
  }
  basis(): CameraBasis {
    if(this.mode==='free'){
      const b=this.freeFrame!;return {position:[...this.position],forward:[...b.forward],right:[...b.right],up:[...b.up]};
    }
    const cy=Math.cos(this.yaw),sy=Math.sin(this.yaw),cp=Math.cos(this.pitch),sp=Math.sin(this.pitch);
    const front=axisRotate([sy*cp,sp,-cy*cp],this.axis),right=axisRotate([cy,0,sy],this.axis),up=axisRotate([-sy*sp,cp,cy*sp],this.axis);
    const ys=Math.sin(this.swayYaw),yc=Math.cos(this.swayYaw),ps=Math.sin(this.swayPitch),pc=Math.cos(this.swayPitch);
    const world=(x:number,y:number,z:number):Vec3=>[0,1,2].map(i=>x*right[i]+y*up[i]+z*front[i]) as Vec3;
    return {position:[...this.position],forward:world(ys*pc,ps,yc*pc),right:world(yc,0,-ys),up:world(-ys*ps,pc,-yc*ps)};
  }
  move(right: number,up: number,forward: number,seconds: number,_fast=false): void {
    const dt=dtValue(seconds);
    if(this.mode==='orbit'){this.orbit(right*90*Math.PI/180*dt/MOUSE_RADIANS,-forward*90*Math.PI/180*dt/MOUSE_RADIANS);return;}
    const length=Math.hypot(right,up,forward);if(!length)return;
    const b=this.basis(),distance=dt*this.movementSpeed/length;
    this.position=this.position.map((v,i)=>v+distance*(right*b.right[i]+up*b.up[i]+forward*b.forward[i])) as Vec3;
  }
}
