import type { Vec3 } from '../camera/camera.ts';
import type { Parameters } from './parameters.ts';
import { radiusLightYears } from '../renderer/temporal.ts';

// Application.cpp: after trajectory writeback, roaming disk crossing and the
// frame-to-frame inward inner-horizon test. The integrator owns transported sign.
export class UniverseState {
  private previous?: Vec3;
  private previousR?: number;
  private configuration = '';
  reset(): void { this.previous=undefined;this.previousR=undefined;this.configuration=''; }
  update(position: readonly number[], parameters: Parameters, transportedSign?: number): void {
    const p=parameters,f=Math.fround,rs=radiusLightYears(p.massSolar);
    if (!p.maximalExtension) { this.reset();return; }
    const config=`${p.maximalExtension},${p.universeSign},${p.universeIndex}`;
    if(this.configuration && this.configuration!==config)this.reset();
    const current=position.slice(0,3).map(x=>f(x*rs)) as Vec3;
    const M=f(.5*rs),a=f(f(p.spin)*M),Q=f(f(p.charge)*M),a2=f(a*a),Q2=f(Q*Q);
    if (transportedSign===1 || transportedSign===-1) p.universeSign=transportedSign;
    else if(this.previous && f(this.previous[1]*current[1])<=0) {
      const denom=f(this.previous[1]-current[1]);
      if(Math.abs(denom)>0) {
        const t=f(this.previous[1]/denom),x=f(this.previous[0]+f(t*f(current[0]-this.previous[0]))),z=f(this.previous[2]+f(t*f(current[2]-this.previous[2])));
        if(f(f(x*x)+f(z*z))<a2)p.universeSign=p.universeSign===1?-1:1;
      }
    }
    const R2=f(f(f(current[0]*current[0])+f(current[1]*current[1]))+f(current[2]*current[2]));
    const b=f(R2-a2),c=f(a2*f(current[1]*current[1]));
    const r2=f(.5*f(b+f(Math.sqrt(f(f(b*b)+f(4*c)))))),r=f(f(Math.sqrt(Math.max(0,r2)))*p.universeSign);
    const discriminant=f(f(f(M*M)-a2)-Q2);
    if(discriminant>=0 && this.previousR!==undefined) {
      const inner=f(M-f(Math.sqrt(discriminant)));
      if(this.previousR>inner && r<=inner && p.universeSign===1)p.universeIndex=((p.universeIndex+1)%3) as 0|1|2;
    }
    this.previous=current;this.previousR=r;
    this.configuration=`${p.maximalExtension},${p.universeSign},${p.universeIndex}`;
  }
}
