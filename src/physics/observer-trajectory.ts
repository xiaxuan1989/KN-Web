import type { CameraBasis, Vec3 } from '../camera/camera.ts';
import { radiusLightYears } from '../renderer/temporal.ts';

// Application.cpp::GeodesicIntegrator, double precision on the CPU.
// Order is X[4], U[4], Ex[4], Ey[4], Ez[4], with coordinates (x,y,z,t).
type Matrix = number[][];
const zeros = (): Matrix => Array.from({ length: 4 }, () => [0,0,0,0]);
const dot = (a: readonly number[], b: readonly number[]): number => a.reduce((sum,v,i) => sum+v*b[i],0);
const changeIndex = (v: readonly number[], g: Matrix): number[] => g.map(row => dot(row,v));
const cross = (a: readonly number[], b: readonly number[]): number[] => [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
export interface TetradFrame { position: number[]; U: number[]; e1: number[]; e2: number[]; e3: number[]; outgoing: boolean; sign?: number }
export type BoostDirection = 'look' | 'velocity';

// Original accel_cam=(D-A,R-F,S-W), rotated by inverse camera orientation.
export function observerAcceleration(axes: Vec3, basis: CameraBasis, thrust: number): Vec3 {
  const f = Math.fround, length = f(Math.sqrt(axes.reduce((sum,x) => sum+x*x,0)));
  if (length <= .1) return [0,0,0];
  const local = axes.map(x => f(x*f(1/length)));
  return [0,1,2].map(i => {
    const x = f(f(basis.right[i])*local[0]), y = f(f(basis.up[i])*local[1]);
    const z = f(f(basis.forward[i])*local[2]);
    return f(f(f(x+y)+z)*f(thrust));
  }) as Vec3;
}

export function scrollObserverThrust(thrust: number, notches: number): number {
  const value=Math.fround(Math.fround(thrust)*Math.fround(Math.pow(Math.fround(1.2),Math.fround(notches))));
  return Number.isFinite(value) && value>0 ? value : thrust;
}

export function observerMetric(X: readonly number[], a: number, Q: number, fade=1, sign=1, outgoing=false) {
  const [x,y,z]=X,a2=a*a,u=x*x+y*y+z*z-a2,S=Math.sqrt(u*u+4*a2*y*y);
  const r2=u>=0 ? .5*(u+S) : 2*a2*y*y/Math.max(1e-20,S-u);
  const r=sign*Math.sqrt(Math.max(r2,0));
  const f=Math.abs(r)>1e-6 ? (r*r*r-Q*Q*r*r)/Math.max(1e-20,r*r*r*r+a2*y*y)*fade : 0;
  const dir=outgoing?-1:1,inv=1/Math.max(1e-20,r2+a2);
  const lower=[(dir*r*x-a*z)*inv,dir*y/r,(dir*r*z+a*x)*inv,1],upper=[...lower.slice(0,3),-1];
  const down=zeros(),up=zeros();
  for(let i=0;i<4;i++) for(let j=0;j<4;j++) {
    const eta=i===j?(i===3?-1:1):0;
    down[i][j]=eta+f*lower[i]*lower[j];up[i][j]=eta-f*upper[i]*upper[j];
  }
  return {down,up,r};
}

export function observerConnection(X: readonly number[], a: number, Q: number, fade=1, sign=1, outgoing=false) {
  const [x,y,z]=X,a2=a*a,Q2=Q*Q,u=x*x+y*y+z*z-a2,S=Math.max(1e-20,Math.sqrt(u*u+4*a2*y*y));
  const r2=u>=0?.5*(u+S):2*a2*y*y/Math.max(1e-20,S-u),r=sign*Math.sqrt(Math.max(r2,0));
  const Y=Math.abs(r)>1e-10?y/r:Math.abs(a)>1e-20?(y>=0?1:-1)*sign*Math.sqrt(Math.max(0,r2-u))/Math.abs(a):0;
  const dr=[r*x/S,Y*(r2+a2)/S,r*z/S,0],N=r*r*r-Q2*r2,D=r2*r2+a2*y*y,di=1/Math.max(1e-20,D),f=N*di*fade;
  const df=[0,0,0,0],dP=[0,0,0,0],P=-Q*r*r*r*di*fade;
  for(let k=0;k<3;k++) {
    const dN=(3*r2-2*Q2*r)*dr[k],dD=4*r*r2*dr[k]+(k===1?2*a2*y:0);
    df[k]=(dN*D-N*dD)*di*di*fade;
    dP[k]=(-Q*3*r*r*dr[k]*D-(-Q*r*r*r)*dD)*di*di*fade;
  }
  const dir=outgoing?-1:1,inv=1/Math.max(1e-20,r2+a2);
  const l=[(dir*r*x-a*z)*inv,dir*Y,(dir*r*z+a*x)*inv,1],lu=[...l.slice(0,3),-1],dl=zeros();
  for(let k=0;k<3;k++) {
    const dinv=-inv*inv*2*r*dr[k];
    dl[k][0]=(dir*x*dr[k]+(k===0?dir*r:0)-(k===2?a:0))*inv+(dir*r*x-a*z)*dinv;
    dl[k][1]=k===0?-dir*Y*x/S:k===1?dir*r*(1-Y*Y)/S:-dir*Y*z/S;
    dl[k][2]=(dir*z*dr[k]+(k===2?dir*r:0)+(k===0?a:0))*inv+(dir*r*z+a*x)*dinv;
  }
  const up=zeros(),F=zeros(),dg=Array.from({length:4},zeros),gamma=Array.from({length:4},zeros);
  for(let i=0;i<4;i++) for(let j=0;j<4;j++) {
    up[i][j]=(i===j?(i===3?-1:1):0)-f*lu[i]*lu[j];
    F[i][j]=(i<3?dP[i]*l[j]+P*dl[i][j]:0)-(j<3?dP[j]*l[i]+P*dl[j][i]:0);
    for(let k=0;k<3;k++) dg[k][i][j]=df[k]*l[i]*l[j]+f*dl[k][i]*l[j]+f*l[i]*dl[k][j];
  }
  for(let k=0;k<4;k++) for(let i=0;i<4;i++) for(let j=0;j<4;j++)
    for(let rho=0;rho<4;rho++) gamma[k][i][j]+=.5*up[k][rho]*(dg[i][rho][j]+dg[j][rho][i]-dg[rho][i][j]);
  return {gamma,F,up};
}

function intermediateSign(start: readonly number[],current: readonly number[],sign: number,a: number): number {
  if(start[1]*current[1]<0) {
    const t=start[1]/(start[1]-current[1]);
    if(Math.hypot(start[0]+t*(current[0]-start[0]),start[2]+t*(current[2]-start[2]))<Math.abs(a)) return -sign;
  }
  return sign;
}

function transform(X: readonly number[],P: readonly number[],a: number,Q: number,sign: number,outgoing: boolean) {
  const [x,y,z,t]=X,[px,py,pz,pt]=P,a2=a*a,Q2=Q*Q,u=x*x+y*y+z*z-a2,v=4*a2*y*y;
  const r2=u>=0?.5*(u+Math.sqrt(u*u+v)):.5*v/Math.max(1e-20,Math.sqrt(u*u+v)-u),r=sign*Math.sqrt(Math.max(r2,0));
  const delta=r*r-r+a2+Q2,sd=(delta>=0?1:-1)*Math.max(Math.abs(delta),1e-16),D=Math.max(r**4+a2*y*y,1e-12);
  const grad=[r*r*r*x/D,r*(r*r+a2)*y/D,r*r*r*z/D],disc=.25-a2-Q2;
  let F=0,g=0;
  if(disc>1e-16) {const k=Math.sqrt(disc),frac=Math.abs(r-(.5+k))/Math.max(Math.abs(r-(.5-k)),1e-16);F=Math.log(Math.max(Math.abs(delta),1e-16))+(.5-Q2)/k*Math.log(Math.max(frac,1e-16));g=a/k*Math.log(Math.max(frac,1e-16));}
  else if(disc< -1e-16) {const k=Math.sqrt(-disc),at=Math.atan((r-.5)/k);F=Math.log(Math.max(Math.abs(delta),1e-16))+2*(.5-Q2)/k*at;g=2*a/k*at;}
  else {const rm=r-.5,srm=(rm>=0?1:-1)*Math.max(Math.abs(rm),1e-16);F=2*Math.log(Math.max(Math.abs(rm),1e-16))-2*(.5-Q2)/srm;g=-2*a/srm;}
  g+=2*Math.atan2(a,r);
  const fp=2*(r-Q2)/sd,gp=2*a/sd-2*a/(r*r+a2),K=fp*pt+gp*(z*px-x*pz),dir=outgoing?-1:1;
  const angle=-dir*g,c=Math.cos(angle),s=Math.sin(angle),p=[px+dir*grad[0]*K,py+dir*grad[1]*K,pz+dir*grad[2]*K];
  return {X:[x*c+z*s,y,z*c-x*s,t-dir*F],P:[p[2]*s+p[0]*c,p[1],-p[0]*s+p[2]*c,pt]};
}

export class ObserverTrajectory {
  state: number[] = Array(20).fill(0);
  outgoing=false;
  sign=1;
  properTime=0;
  acceleration: Vec3=[0,0,0];
  charge=0;
  stopped=false;
  extensionEnabled=false;

  initialize(position: Vec3,velocity: Vec3,a: number,Q: number,sign: 1 | -1=1): void {
    this.outgoing=false;this.sign=sign;this.properTime=0;this.stopped=false;
    const pos=position.map(Math.fround),vel=velocity.map(Math.fround);
    const Y=this.state=[...pos,0,...Array(16).fill(0)],g=observerMetric(Y,a,Q,1,this.sign).down;
    const product=(a: number[],b: number[])=>{
      let sum=0;for(let i=0;i<4;i++)for(let j=0;j<4;j++)sum+=g[i][j]*a[i]*b[j];return sum;
    };
    let v=[...vel,1],square=product(v,v);
    if(square>=-1e-6) {
      v=g[3][3]<-1e-6?[0,0,0,1]:[-pos[0]*.1,-pos[1]*.1,-pos[2]*.1,1];square=product(v,v);
      if(square>=0){v=[0,0,0,1];square=-1;}
    }
    const U=v.map(x=>x/Math.sqrt(-square));Y.splice(4,4,...U);const ud=changeIndex(U,g);
    // GLM's initialization reference axes are float32; integration is double.
    const f=Math.fround;
    const fnorm=(v:number[])=>{
      const square=f(f(f(v[0]*v[0])+f(v[1]*v[1]))+f(v[2]*v[2]));
      const inverse=f(1/f(Math.sqrt(square)));
      return v.map(x=>f(x*inverse));
    };
    const mr=fnorm(pos).map(x=>-x),up=Math.abs(mr[1])>.999?[1,0,0]:[0,1,0];
    const mp=fnorm(cross(up,mr).map(f)),mt=cross(mp,mr).map(f),axes=[mr,mt,mp],basis:number[][]=[],lower:number[][]=[];
    const project=(e:number[])=>{
      const proj=dot(e,ud);e=e.map((x,i)=>x+proj*U[i]);const down=changeIndex(e,g),n=Math.sqrt(Math.max(1e-9,dot(e,down)));
      return {e:e.map(x=>x/n),down:down.map(x=>x/n)};
    };
    for(let k=0;k<3;k++) {
      let e=[...axes[k],0];
      if(k>0) {const p=dot(e,ud);e=e.map((x,i)=>x+p*U[i]);for(let j=0;j<k;j++){const d=dot(e,lower[j]);e=e.map((x,i)=>x-d*basis[j][i]);}}
      const normalized=project(e);basis.push(normalized.e);lower.push(normalized.down);
    }
    for(let k=0;k<3;k++) for(let i=0;i<4;i++) Y[8+4*k+i]=mr[k]*basis[0][i]+mt[k]*basis[1][i]+mp[k]*basis[2][i];
    this.orthonormalize(a,Q);
  }

  orthonormalize(a:number,Q:number): void {
    const Y=this.state,g=observerMetric(Y,a,Q,1,this.sign,this.outgoing).down;
    const product=(o1:number,o2:number)=>{
      let sum=0;for(let i=0;i<4;i++)for(let j=0;j<4;j++)sum+=g[i][j]*Y[o1+i]*Y[o2+j];return sum;
    };
    const factor=1/Math.sqrt(Math.max(1e-12,Math.abs(product(4,4))));for(let i=0;i<4;i++)Y[4+i]*=factor;
    const norm=product(4,4);
    for(let k=0;k<3;k++) {
      const off=8+4*k,p=product(off,4)/Math.min(-1e-12,norm);for(let i=0;i<4;i++)Y[off+i]-=p*Y[4+i];
      for(let j=0;j<k;j++){const o=8+4*j,pr=product(off,o)/Math.max(1e-12,product(o,o));for(let i=0;i<4;i++)Y[off+i]-=pr*Y[o+i];}
      const n=1/Math.sqrt(Math.max(1e-12,Math.abs(product(off,off))));for(let i=0;i<4;i++)Y[off+i]*=n;
    }
  }

  // Application.cpp instantaneous rapidity boost, including its tangent fallback
  // and the transformation of all three transported basis vectors.
  boost(rapidity:number,direction:BoostDirection,basis:CameraBasis,a:number,Q:number): boolean {
    const y=Math.fround(rapidity);
    if(!Number.isFinite(y))return false;
    const old=this.state.slice(),U=old.slice(4,8),g=observerMetric(old,a,Q,1,this.sign,this.outgoing).down;
    const product=(A:number[],B:number[])=>{
      let sum=0;for(let i=0;i<4;i++)for(let j=0;j<4;j++)sum+=g[i][j]*A[i]*B[j];return sum;
    };
    let E=[0,0,0,0];
    const alongLook=()=>{for(let j=0;j<3;j++)for(let i=0;i<4;i++)E[i]+=Math.fround(basis.forward[j])*old[8+4*j+i];};
    if(direction==='look')alongLook();
    else {
      const D=[...U.slice(0,3),0],du=product(D,U);E=D.map((x,i)=>x+du*U[i]);
      const norm=product(E,E);
      if(norm>1e-12)E=E.map(x=>x/Math.sqrt(norm));else alongLook();
    }
    const c=Math.cosh(y),s=Math.sinh(y);
    for(let i=0;i<4;i++)this.state[4+i]=c*U[i]+s*E[i];
    for(let j=0;j<3;j++) {
      const d=product(old.slice(8+4*j,12+4*j),E);
      for(let i=0;i<4;i++)this.state[8+4*j+i]+=(c-1)*d*E[i]+s*d*U[i];
    }
    this.orthonormalize(a,Q);
    if(!this.state.every(Number.isFinite) || Math.abs(product(this.state.slice(4,8),this.state.slice(4,8))+1)>1e-5) {
      this.state=old;return false;
    }
    return true;
  }

  switchCoordinates(a:number,Q:number): void {
    const Y=this.state,g=observerMetric(Y,a,Q,1,this.sign,this.outgoing),next=Y.slice();
    for(let k=0;k<4;k++) {
      const off=4+4*k,cov=changeIndex(Y.slice(off,off+4),g.down),converted=transform(Y,cov,a,Q,this.sign,this.outgoing);
      if(k===0)next.splice(0,4,...converted.X);
      next.splice(off,4,...converted.P);
    }
    const inverse=observerMetric(next,a,Q,1,this.sign,!this.outgoing).up;
    for(let k=0;k<4;k++){const off=4+4*k;next.splice(off,4,...changeIndex(next.slice(off,off+4),inverse));}
    if(Y.slice(4,8).reduce((s,v)=>s+Math.abs(v),0)>2*next.slice(4,8).reduce((s,v)=>s+Math.abs(v),0)) {this.state=next;this.outgoing=!this.outgoing;}
  }

  derivative(Y:number[],a:number,Q:number,sign=this.sign): number[] {
    const {gamma,F,up}=observerConnection(Y,a,Q,1,sign,this.outgoing),d=Array(20).fill(0),U=Y.slice(4,8);
    const lorentzDown=changeIndex(U,F).map(x=>x*this.charge),lorentzUp=changeIndex(lorentzDown,up);
    for(let i=0;i<4;i++)d[i]=U[i];
    for(let k=0;k<4;k++) {
      const off=4+4*k,V=Y.slice(off,off+4);
      for(let i=0;i<4;i++) for(let mu=0;mu<4;mu++) for(let nu=0;nu<4;nu++) d[off+i]-=gamma[i][mu][nu]*U[mu]*V[nu];
      for(let i=0;i<4;i++) {
        if(k===0)d[off+i]+=this.acceleration[0]*Y[8+i]+this.acceleration[1]*Y[12+i]+this.acceleration[2]*Y[16+i]+lorentzUp[i];
        else d[off+i]+=U[i]*(this.acceleration[k-1]+dot(lorentzDown,V));
      }
    }
    return d;
  }

  step(dt:number,a:number,Q:number): void {
    this.switchCoordinates(a,Q);const Y=this.state;
    const k1=this.derivative(Y,a,Q),stage=(k:number[],h:number)=>Y.map((v,i)=>v+h*k[i]);
    const y2=stage(k1,.5*dt),k2=this.derivative(y2,a,Q,intermediateSign(Y,y2,this.sign,a));
    const y3=stage(k2,.5*dt),k3=this.derivative(y3,a,Q,intermediateSign(Y,y3,this.sign,a));
    const y4=stage(k3,dt),k4=this.derivative(y4,a,Q,intermediateSign(Y,y4,this.sign,a));
    this.state=Y.map((v,i)=>v+dt/6*(k1[i]+2*k2[i]+2*k3[i]+k4[i]));
    this.sign=intermediateSign(Y,this.state,this.sign,a);this.orthonormalize(a,Q);
  }

  advance(seconds:number,timeRate:number,mass:number,a:number,Q:number): void {
    if(this.stopped)return;
    const dt=seconds*timeRate*299792458/radiusLightYears(mass)/9460730472580800,dir=dt>=0?1:-1;
    let remaining=Math.abs(dt);
    for(let count=0;remaining>1e-9 && count<1500;count++) {
      const Y=this.state,R=Math.sqrt(Math.max(1e-12,(Math.hypot(Y[0],Y[2])-Math.abs(a))**2+Y[1]*Y[1]));
      const scaled=Math.max(R/2,1),gravity=.005*scaled*Math.sqrt(scaled),kinematic=.05*R/Math.max(1e-6,Math.hypot(...Y.slice(4,7)));
      const step=Math.min(remaining,Math.max(.0005,Math.min(5,gravity,kinematic)));
      const old=this.state.slice(),oldChart=this.outgoing,oldSign=this.sign;
      this.step(step*dir,a,Q);
      // Retain the positive-sheet rollback with extension disabled; allow the
      // native signed RK stages and final sheet crossing when enabled.
      if((!this.extensionEnabled && this.sign<0) || !this.state.every(Number.isFinite) || Math.abs(observerMetric(this.state,a,Q,1,this.sign,this.outgoing).r)<1e-6) {
        this.state=old;this.outgoing=oldChart;this.sign=oldSign;this.stopped=true;break;
      }
      this.properTime+=step*dir;remaining-=step;
    }
  }

  frame(basis:CameraBasis): TetradFrame {
    const rotated=(axis:number[])=>[0,1,2,3].map(i=>-axis.reduce((sum,v,j)=>sum+v*this.state[8+4*j+i],0));
    return {position:this.state.slice(0,4),U:this.state.slice(4,8),e1:rotated(basis.right),e2:rotated(basis.up),e3:rotated(basis.forward.map(v=>-v)),outgoing:this.outgoing,sign:this.sign};
  }
}
