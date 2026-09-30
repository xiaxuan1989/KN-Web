// NPGS BlackHole_common.glsl GridColor / GridColorSimple.
// Native surface order is preserved; roots are sorted within each surface only.
// Whitehole=0; trace integration remains restricted to the positive-r sheet.
const kPi: f32 = 3.14159265358979323846;

fn Vec2ToTheta(v1: vec2<f32>, v2: vec2<f32>) -> f32 {
    var VecDot: f32   = dot(v1, v2);
    var VecCross: f32 = v1.x * v2.y - v1.y * v2.x;
    var Angle: f32    = asin(0.999999 * VecCross / (length(v1) * length(v2)));
    var Dx: f32 = step(0.0, VecDot);
    var Cx: f32 = step(0.0, VecCross);
    return mix(mix(-kPi - Angle, kPi - Angle, Cx), Angle, Dx);
}

fn KelvinToRgb(Kelvin: f32) -> vec3<f32> {
    if (Kelvin < 400.01) { return vec3<f32>(0.0); }
    var Teff: f32     = (Kelvin - 6500.0) / (6500.0 * Kelvin * 2.2);
    var RgbColor: vec3<f32> = vec3<f32>(0.0);
    RgbColor.r = exp(2.05539304e4 * Teff);
    RgbColor.g = exp(2.63463675e4 * Teff);
    RgbColor.b = exp(3.30145739e4 * Teff);
    var BrightnessScale: f32 = 1.0 / max(max(1.5 * RgbColor.r, RgbColor.g), RgbColor.b);
    if (Kelvin < 1000.0) { BrightnessScale *= (Kelvin - 400.0) / 600.0; }
    RgbColor *= BrightnessScale;
    return RgbColor;
}

fn GetZamoOmega(r: f32, a: f32, Q: f32, y: f32) -> f32 {
    var r2: f32 = r * r;
    var a2: f32 = a * a;
    var y2: f32 = y * y;
    var cos2: f32 = min(1.0, y2 / (r2 + 1e-9));
    var sin2: f32 = 1.0 - cos2;
    var Delta: f32 = r2 - r + a2 + Q * Q;
    var A_metric: f32 = (r2 + a2) * (r2 + a2) - Delta * a2 * sin2;
    return a * (r - Q * Q) / max(1e-9, A_metric);
}

fn IntersectKerrEllipsoid(O: vec3<f32>, D: vec3<f32>, r: f32, a: f32) -> vec2<f32> {
    var r2: f32 = r * r;
    var a2: f32 = a * a;
    var R_eq_sq: f32 = r2 + a2;
    var R_pol_sq: f32 = r2;
    var A: f32 = R_eq_sq;
    var B: f32 = R_pol_sq;
    var qa: f32 = B * (D.x * D.x + D.z * D.z) + A * D.y * D.y;
    var qb: f32 = 2.0 * (B * (O.x * D.x + O.z * D.z) + A * O.y * D.y);
    var qc: f32 = B * (O.x * O.x + O.z * O.z) + A * O.y * O.y - A * B;
    if (abs(qa) < 1e-9) { return vec2<f32>(-1.0); }
    var disc: f32 = qb * qb - 4.0 * qa * qc;
    if (disc < 0.0) { return vec2<f32>(-1.0); }
    var sqrtDisc: f32 = sqrt(disc);
    var t1: f32 = (-qb - sqrtDisc) / (2.0 * qa);
    var t2: f32 = (-qb + sqrtDisc) / (2.0 * qa);
    return vec2<f32>(t1, t2);
}

fn GridColorSimple(BaseColor: vec4<f32>, RayPos: vec4<f32>, LastRayPos: vec4<f32>, P_cov: vec4<f32>, LastP_cov: vec4<f32>, PhysicalSpinA: f32, PhysicalQ: f32, isoutgoing: bool, EndStepSign: f32, dlambda: f32, showInnerGrid: bool, gridTime: f32) -> vec4<f32> {
    var CurrentResult: vec4<f32> = BaseColor;
    if (CurrentResult.a > 0.99) { return CurrentResult; }
    var SignedGridRadii: array<f32,5>;
    var GridColors: array<vec3<f32>,5>;
    var GridCount: i32 = 0;
    var StartStepSign: f32 = EndStepSign;
    var bHasCrossed: bool = false;
    var t_cross: f32 = -1.0;
    var DiskHitPos: vec3<f32> = vec3<f32>(0.0);
    var DiskHitX: vec4<f32> = vec4<f32>(0.0);
    var geo_last: KerrGeometry;
    geo_last = ComputeGeometryScalars(LastRayPos.xyz, PhysicalSpinA, PhysicalQ, 1.0, StartStepSign, isoutgoing);
    var V0: vec4<f32> = RaiseIndex(LastP_cov, geo_last);
    var T0: vec4<f32> = V0 * dlambda;
    var geo_curr: KerrGeometry;
    geo_curr = ComputeGeometryScalars(RayPos.xyz, PhysicalSpinA, PhysicalQ, 1.0, EndStepSign, isoutgoing);
    var V1: vec4<f32> = RaiseIndex(P_cov, geo_curr);
    var T1: vec4<f32> = V1 * dlambda;
    if (LastRayPos.y * RayPos.y < 0.0) {
        var denom: f32 = (LastRayPos.y - RayPos.y);
        if(abs(denom) > 1e-9) {
            t_cross = LastRayPos.y / denom;
            for(var iter: i32 = 0; iter < 3; iter++) {
                var t2: f32 = t_cross * t_cross;
                var t3: f32 = t2 * t_cross;
                var h00: f32 = 2.0*t3 - 3.0*t2 + 1.0;
                var h10: f32 = t3 - 2.0*t2 + t_cross;
                var h01: f32 = -2.0*t3 + 3.0*t2;
                var h11: f32 = t3 - t2;
                var yt: f32 = h00*LastRayPos.y + h10*T0.y + h01*RayPos.y + h11*T1.y;
                var dh00: f32 = 6.0*t2 - 6.0*t_cross;
                var dh10: f32 = 3.0*t2 - 4.0*t_cross + 1.0;
                var dh01: f32 = -6.0*t2 + 6.0*t_cross;
                var dh11: f32 = 3.0*t2 - 2.0*t_cross;
                var dyt: f32 = dh00*LastRayPos.y + dh10*T0.y + dh01*RayPos.y + dh11*T1.y;
                t_cross -= yt / (dyt + 1e-12);
            }
            t_cross = clamp(t_cross, 0.0, 1.0);
            var t2: f32 = t_cross * t_cross;
            var t3: f32 = t2 * t_cross;
            var H: vec4<f32> = vec4<f32>(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t_cross, -2.0*t3 + 3.0*t2, t3 - t2);
            DiskHitX = H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1;
            DiskHitPos = DiskHitX.xyz;
            if (length(DiskHitPos.xz) < abs(PhysicalSpinA)) {
                StartStepSign = -EndStepSign;
                bHasCrossed = true;
            }
        }
    }
    var CheckPositive: bool = (StartStepSign > 0.0) || (EndStepSign > 0.0);
    var CheckNegative: bool = (StartStepSign < 0.0) || (EndStepSign < 0.0);
    var HorizonDiscrim: f32 = 0.25 - PhysicalSpinA * PhysicalSpinA - PhysicalQ * PhysicalQ;
    var RH_Outer: f32 = 0.5 + sqrt(max(0.0, HorizonDiscrim));
    var RH_Inner: f32 = 0.5 - sqrt(max(0.0, HorizonDiscrim));
    var HasHorizon: bool = HorizonDiscrim >= 0.0;
    if (CheckPositive) {
        SignedGridRadii[GridCount] = 70.0;
        GridColors[GridCount] = 0.3*vec3<f32>(0.0, 1.0, 1.0);
        GridCount++;
        if (HasHorizon) {
            SignedGridRadii[GridCount] = RH_Outer * 1.06;
            GridColors[GridCount] = 0.3*vec3<f32>(0.0, 1.0, 0.0);
            GridCount++;
            if(showInnerGrid)
            {
                SignedGridRadii[GridCount] = RH_Inner * 0.94;
                GridColors[GridCount] =0.3* vec3<f32>(1.0, 0.0, 0.0);
                GridCount++;
            }
        }
    }
    if (CheckNegative) {
        SignedGridRadii[GridCount] = -70.0;
        GridColors[GridCount] = 0.3*vec3<f32>(1.0, 0.0, 1.0);
        GridCount++;
    }
    var O: vec3<f32> = LastRayPos.xyz;
    var D_vec: vec3<f32> = RayPos.xyz - LastRayPos.xyz;
    for (var i: i32 = 0; i < GridCount; i++) {
        if (CurrentResult.a > 0.99) { break; }
        var TargetSignedR: f32 = SignedGridRadii[i];
        var TargetGeoR: f32 = abs(TargetSignedR);
        var TargetColor: vec3<f32> = GridColors[i];
        var roots: vec2<f32> = IntersectKerrEllipsoid(O, D_vec, TargetGeoR, PhysicalSpinA);
        var t_hits: array<f32,2>;
        t_hits[0] = roots.x;
        t_hits[1] = roots.y;
        if (t_hits[0] > t_hits[1]) {
            var temp: f32 = t_hits[0]; t_hits[0] = t_hits[1]; t_hits[1] = temp;
        }
        for (var j: i32 = 0; j < 2; j++) {
            var t: f32 = t_hits[j];
            if (t >= 0.0 && t <= 1.0) {
                var HitPointSign: f32 = StartStepSign;
                if (bHasCrossed) {
                    if (t > t_cross) {
                        HitPointSign = EndStepSign;
                    }
                }
                if (HitPointSign * TargetSignedR < 0.0) { continue; }
                for(var iter: i32 = 0; iter < 2; iter++) {
                    var t2: f32 = t*t; var t3: f32 = t2*t;
                    var H: vec4<f32> = vec4<f32>(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t, -2.0*t3 + 3.0*t2, t3 - t2);
                    var pos: vec3<f32> = (H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1).xyz;
                    var curR: f32 = KerrSchildRadius(pos, PhysicalSpinA, HitPointSign);
                    var dt: f32 = 0.001;
                    var nt: f32 = t + dt;
                    var nt2: f32 = nt*nt; var nt3: f32 = nt2*nt;
                    var nH: vec4<f32> = vec4<f32>(2.0*nt3 - 3.0*nt2 + 1.0, nt3 - 2.0*nt2 + nt, -2.0*nt3 + 3.0*nt2, nt3 - nt2);
                    var npos: vec3<f32> = (nH.x*LastRayPos + nH.y*T0 + nH.z*RayPos + nH.w*T1).xyz;
                    var nextR: f32 = KerrSchildRadius(npos, PhysicalSpinA, HitPointSign);
                    var dr_dt: f32 = (nextR - curR) / dt;
                    t -= (curR - TargetSignedR) / (dr_dt + 1e-12);
                }
                if (t < 0.0 || t > 1.0) { continue; }
                var t2: f32 = t*t; var t3: f32 = t2*t;
                var H: vec4<f32> = vec4<f32>(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t, -2.0*t3 + 3.0*t2, t3 - t2);
                var HitX: vec4<f32> = H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1;
                var HitPos: vec3<f32> = HitX.xyz;
                var HitTime: f32 = HitX.w;
                var CheckR: f32 = KerrSchildRadius(HitPos, PhysicalSpinA, HitPointSign);
                if (abs(CheckR - TargetSignedR) > 0.1 * TargetGeoR + 0.1) { continue; }
                var HitP_cov: vec4<f32> = mix(LastP_cov, P_cov, t);
                var PatternPos: vec3<f32> = HitPos;
                var PatternTime: f32 = HitTime;
                if (isoutgoing) {
                    var tempX: vec4<f32> = vec4<f32>(HitPos, HitTime);
                    var dummyP: vec4<f32> = vec4<f32>(0.0);
                    tempX = transformKerrSchild_YSpin(State(tempX,dummyP), HitPointSign, 0.5, PhysicalSpinA, PhysicalQ, true).X;
                    PatternPos = tempX.xyz;
                    PatternTime = tempX.w;
                }
                var Omega: f32 = GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ, PatternPos.y);
                var Phi_raw: f32 = Vec2ToTheta(normalize(PatternPos.zx), vec2<f32>(0.0, 1.0));
                var Phi: f32 = Phi_raw + Omega * PatternTime + gridTime*GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ, 0.0);
                var CosTheta: f32 = clamp(PatternPos.y / TargetGeoR, -1.0, 1.0);
                var Theta: f32 = acos(CosTheta);
                var SinTheta: f32 = sqrt(max(0.0, 1.0 - CosTheta * CosTheta));
                var DensityPhi: f32 = 24.0;
                var DensityTheta: f32 = 13.0;
                var DistFactor: f32 = min(20.0,length(PatternPos));
                var LineWidth: f32 = 0.002 * DistFactor;
                LineWidth = clamp(LineWidth, 0.01, 0.15);
                var PatternPhi: f32 = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
                var GridPhi: f32 = smoothstep(LineWidth / max(0.005, SinTheta), 0.0, PatternPhi);
                var PatternTheta: f32 = abs(fract(Theta / kPi * DensityTheta) - 0.5);
                var GridTheta: f32 = smoothstep(LineWidth, 0.0, PatternTheta);
                var GridIntensity: f32 = max(GridPhi, GridTheta);
                var Omega_zamo: f32 = GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ, HitPos.y);
                var VelSpatial: vec3<f32> = Omega_zamo * vec3<f32>(HitPos.z, 0.0, -HitPos.x);
                var U_zamo_unnorm: vec4<f32> = vec4<f32>(VelSpatial, 1.0);
                var geo_hit: KerrGeometry;
                geo_hit = ComputeGeometryScalars(HitPos, PhysicalSpinA, PhysicalQ, 1.0, HitPointSign, isoutgoing);
                var U_zamo_lower: vec4<f32> = LowerIndex(U_zamo_unnorm, geo_hit);
                var norm_sq: f32 = dot(U_zamo_unnorm, U_zamo_lower);
                var norm: f32 = sqrt(max(1e-9, abs(norm_sq)));
                var U_zamo: vec4<f32> = U_zamo_unnorm / norm;
                var E_emit: f32 = -dot(HitP_cov, U_zamo);
                if (GridIntensity > 0.01) {
                    var GridCol: vec4<f32> = vec4<f32>(TargetColor * 2.0, 1.0);
                    if (E_emit < 0.0) {
                        var cMax: f32 = max(max(GridCol.r, GridCol.g), GridCol.b);
                        var cMin: f32 = min(min(GridCol.r, GridCol.g), GridCol.b);
                        GridCol = vec4<f32>(vec3<f32>(cMax + cMin) - GridCol.rgb, GridCol.a);
                        // Native Whitehole=0 suppresses emission, but still accumulates alpha.
                        GridCol = vec4<f32>(0.0);
                    }
                    var Alpha: f32 = GridIntensity * 0.8;
                    CurrentResult = vec4<f32>(CurrentResult.rgb + GridCol.rgb * Alpha * (1.0 - CurrentResult.a), CurrentResult.a);
                    CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
                }
            }
        }
    }
    if (bHasCrossed && CurrentResult.a < 0.99) {
        var HitRho: f32 = length(DiskHitPos.xz);
        var a_abs: f32 = abs(PhysicalSpinA);
        var HitTime_disk: f32 = DiskHitX.w;
        var HitP_cov: vec4<f32> = mix(LastP_cov, P_cov, t_cross);
        var PatternPosDisk: vec3<f32> = DiskHitPos;
        if (isoutgoing) {
            var tempX: vec4<f32> = vec4<f32>(DiskHitPos, HitTime_disk);
            var dummyP: vec4<f32> = vec4<f32>(0.0);
            var diskSign: f32 = select(StartStepSign, -StartStepSign, length(DiskHitPos.xz) < abs(PhysicalSpinA));
            tempX = transformKerrSchild_YSpin(State(tempX,dummyP), diskSign, 0.5, PhysicalSpinA, PhysicalQ, true).X;
            PatternPosDisk = tempX.xyz;
        }
        var Phi_raw: f32 = Vec2ToTheta(normalize(PatternPosDisk.zx), vec2<f32>(0.0, 1.0));
        var Phi: f32 = Phi_raw;
        var DensityPhi: f32 = 24.0;
        var DistFactor: f32 = length(DiskHitPos);
        var LineWidth: f32 = 0.002 * DistFactor;
        LineWidth = clamp(LineWidth, 0.01, 0.1);
        var PatternPhi: f32 = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
        var GridPhi: f32 = smoothstep(LineWidth / max(0.1, HitRho / a_abs), 0.0, PatternPhi);
        var NormalizedRho: f32 = HitRho / max(1e-6, a_abs);
        var DensityRho: f32 = 5.0;
        var PatternRho: f32 = abs(fract(NormalizedRho * DensityRho) - 0.5);
        var GridRho: f32 = smoothstep(LineWidth, 0.0, PatternRho);
        var GridIntensity: f32 = max(GridPhi, GridRho);
        var U_zero: vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        var E_emit_disk: f32 = -dot(HitP_cov, U_zero);
        if (GridIntensity > 0.01) {
            var RingColor: vec3<f32> = 0.3*vec3<f32>(1.0, 1.0, 1.0);
            var GridCol: vec4<f32> = vec4<f32>(RingColor * 5.0, 1.0);
            if (E_emit_disk < 0.0) {
                var cMax: f32 = max(max(GridCol.r, GridCol.g), GridCol.b);
                var cMin: f32 = min(min(GridCol.r, GridCol.g), GridCol.b);
                GridCol = vec4<f32>(vec3<f32>(cMax + cMin) - GridCol.rgb, GridCol.a);
                GridCol = vec4<f32>(0.0);
            }
            var Alpha: f32 = GridIntensity * 0.8;
            CurrentResult = vec4<f32>(CurrentResult.rgb + GridCol.rgb * Alpha * (1.0 - CurrentResult.a), CurrentResult.a);
            CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
        }
    }
    return CurrentResult;
}

fn GridColor(BaseColor: vec4<f32>, RayPos: vec4<f32>, LastRayPos: vec4<f32>, iP_cov: vec4<f32>, iE_obs: f32, PhysicalSpinA: f32, PhysicalQ: f32, isoutgoing: bool, EndStepSign: f32, gridTime: f32) -> vec4<f32> {
    var CurrentResult: vec4<f32> = BaseColor;
    if (CurrentResult.a > 0.99) { return CurrentResult; }
    var SignedGridRadii: array<f32,12>;
    var GridCount: i32 = 0;
    var StartStepSign: f32 = EndStepSign;
    var bHasCrossed: bool = false;
    var t_cross: f32 = -1.0;
    var DiskHitPos: vec3<f32> = vec3<f32>(0.0);
    if (LastRayPos.y * RayPos.y < 0.0) {
        var denom: f32 = (LastRayPos.y - RayPos.y);
        if(abs(denom) > 1e-9) {
            t_cross = LastRayPos.y / denom;
            DiskHitPos = mix(LastRayPos.xyz, RayPos.xyz, t_cross);
            if (length(DiskHitPos.xz) < abs(PhysicalSpinA)) {
                StartStepSign = -EndStepSign;
                bHasCrossed = true;
            }
        }
    }
    var CheckPositive: bool = (StartStepSign > 0.0) || (EndStepSign > 0.0);
    var CheckNegative: bool = (StartStepSign < 0.0) || (EndStepSign < 0.0);
    var HorizonDiscrim: f32 = 0.25 - PhysicalSpinA * PhysicalSpinA - PhysicalQ * PhysicalQ;
    var RH_Outer: f32 = 0.5 + sqrt(max(0.0, HorizonDiscrim));
    var RH_Inner: f32 = 0.5 - sqrt(max(0.0, HorizonDiscrim));
    if (CheckPositive) {
        SignedGridRadii[GridCount] = RH_Outer * 1.06; GridCount++;
        SignedGridRadii[GridCount] = 20.0; GridCount++;
        if (HorizonDiscrim >= 0.0) {
           SignedGridRadii[GridCount] = RH_Inner * 0.94; GridCount++;
        }
    }
    if (CheckNegative) {
        SignedGridRadii[GridCount] = -3.0; GridCount++;
        SignedGridRadii[GridCount] = -10.0; GridCount++;
    }
    var O: vec3<f32> = LastRayPos.xyz;
    var D_vec: vec3<f32> = RayPos.xyz - LastRayPos.xyz;
    for (var i: i32 = 0; i < GridCount; i++) {
        if (CurrentResult.a > 0.99) { break; }
        var TargetSignedR: f32 = SignedGridRadii[i];
        var TargetGeoR: f32 = abs(TargetSignedR);
        var roots: vec2<f32> = IntersectKerrEllipsoid(O, D_vec, TargetGeoR, PhysicalSpinA);
        var t_hits: array<f32,2>;
        t_hits[0] = roots.x;
        t_hits[1] = roots.y;
        if (t_hits[0] > t_hits[1]) {
            var temp: f32 = t_hits[0]; t_hits[0] = t_hits[1]; t_hits[1] = temp;
        }
        for (var j: i32 = 0; j < 2; j++) {
            var t: f32 = t_hits[j];
            if (t >= 0.0 && t <= 1.0) {
                var HitPointSign: f32 = StartStepSign;
                if (bHasCrossed) {
                    if (t > t_cross) {
                        HitPointSign = EndStepSign;
                    }
                }
                if (HitPointSign * TargetSignedR < 0.0) { continue; }
                var HitPos: vec3<f32> = O + D_vec * t;
                var CheckR: f32 = KerrSchildRadius(HitPos, PhysicalSpinA, HitPointSign);
                if (abs(CheckR - TargetSignedR) > 0.1 * TargetGeoR + 0.1) { continue; }
                var HitTime: f32 = mix(LastRayPos.w, RayPos.w, t);
                var Omega: f32 = GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ, HitPos.y);
                var VelSpatial: vec3<f32> = Omega * vec3<f32>(HitPos.z, 0.0, -HitPos.x);
                var U_zamo_unnorm: vec4<f32> = vec4<f32>(VelSpatial, 1.0);
                var geo_hit: KerrGeometry;
                geo_hit = ComputeGeometryScalars(HitPos, PhysicalSpinA, PhysicalQ, 1.0, HitPointSign, isoutgoing);
                var U_zamo_lower: vec4<f32> = LowerIndex(U_zamo_unnorm, geo_hit);
                var norm_sq: f32 = dot(U_zamo_unnorm, U_zamo_lower);
                var norm: f32 = sqrt(max(1e-9, abs(norm_sq)));
                var U_zamo: vec4<f32> = U_zamo_unnorm / norm;
                var E_emit: f32 = -dot(iP_cov, U_zamo);
                var Shift: f32 = 1.0/ max(1e-6, abs(E_emit));
                var PatternPos: vec3<f32> = HitPos;
                var PatternTime: f32 = HitTime;
                if (isoutgoing) {
                    var tempX: vec4<f32> = vec4<f32>(HitPos, HitTime);
                    var dummyP: vec4<f32> = vec4<f32>(0.0);
                    tempX = transformKerrSchild_YSpin(State(tempX,dummyP), HitPointSign, 0.5, PhysicalSpinA, PhysicalQ, true).X;
                    PatternPos = tempX.xyz;
                    PatternTime = tempX.w;
                }
                var Phi_raw: f32 = Vec2ToTheta(normalize(PatternPos.zx), vec2<f32>(0.0, 1.0));
                var Phi: f32 = Phi_raw + Omega * PatternTime + gridTime*GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ, 1.0);
                var CosTheta: f32 = clamp(PatternPos.y / TargetGeoR, -1.0, 1.0);
                var Theta: f32 = acos(CosTheta);
                var SinTheta: f32 = sqrt(max(0.0, 1.0 - CosTheta * CosTheta));
                var DensityPhi: f32 = 24.0;
                var DensityTheta: f32 = 12.0;
                var DistFactor: f32 = length(PatternPos);
                var LineWidth: f32 = 0.001 * DistFactor;
                LineWidth = clamp(LineWidth, 0.01, 0.1);
                var PatternPhi: f32 = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
                var GridPhi: f32 = smoothstep(LineWidth / max(0.005, SinTheta), 0.0, PatternPhi);
                var PatternTheta: f32 = abs(fract(Theta / kPi * DensityTheta) - 0.5);
                var GridTheta: f32 = smoothstep(LineWidth, 0.0, PatternTheta);
                var GridIntensity: f32 = max(GridPhi, GridTheta);
                if (GridIntensity > 0.01) {
                    var BaseTemp: f32 = 6500.0;
                    var BlackbodyColor: vec3<f32> = KelvinToRgb(BaseTemp * Shift);
                    var Intensity: f32 = min(1.5 * pow(Shift, 4.0), 20.0);
                    var GridCol: vec4<f32> = vec4<f32>(BlackbodyColor * Intensity, 1.0);
                    var Alpha: f32 = GridIntensity * 0.5;
                    CurrentResult = vec4<f32>(CurrentResult.rgb + GridCol.rgb * Alpha * (1.0 - CurrentResult.a), CurrentResult.a);
                    CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
                }
            }
        }
    }
    if (bHasCrossed && CurrentResult.a < 0.99) {
        var HitRho: f32 = length(DiskHitPos.xz);
        var a_abs: f32 = abs(PhysicalSpinA);
        var HitTime_disk: f32 = mix(LastRayPos.w, RayPos.w, t_cross);
        var PatternPosDisk: vec3<f32> = DiskHitPos;
        if (isoutgoing) {
            var tempX: vec4<f32> = vec4<f32>(DiskHitPos, HitTime_disk);
            var dummyP: vec4<f32> = vec4<f32>(0.0);
            var diskSign: f32 = select(StartStepSign, -StartStepSign, length(DiskHitPos.xz) < abs(PhysicalSpinA));
            tempX = transformKerrSchild_YSpin(State(tempX,dummyP), diskSign, 0.5, PhysicalSpinA, PhysicalQ, true).X;
            PatternPosDisk = tempX.xyz;
        }
        var Phi_raw: f32 = Vec2ToTheta(normalize(PatternPosDisk.zx), vec2<f32>(0.0, 1.0));
        var Phi: f32 = Phi_raw;
        var DensityPhi: f32 = 24.0;
        var DistFactor: f32 = length(DiskHitPos);
        var LineWidth: f32 = 0.001 * DistFactor;
        LineWidth = clamp(LineWidth, 0.01, 0.1);
        var PatternPhi: f32 = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
        var GridPhi: f32 = smoothstep(LineWidth / max(0.1, HitRho / a_abs), 0.0, PatternPhi);
        var NormalizedRho: f32 = HitRho / max(1e-6, a_abs);
        var DensityRho: f32 = 5.0;
        var PatternRho: f32 = abs(fract(NormalizedRho * DensityRho) - 0.5);
        var GridRho: f32 = smoothstep(LineWidth, 0.0, PatternRho);
        var GridIntensity: f32 = max(GridPhi, GridRho);
        if (GridIntensity > 0.01) {
            var U_zero: vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            var E_emit: f32 = -dot(iP_cov, U_zero);
            var Shift: f32 = 1.0 / max(1e-6, abs(E_emit));
            var BaseTemp: f32 = 6500.0;
            var BlackbodyColor: vec3<f32> = KelvinToRgb(BaseTemp * Shift);
            var Intensity: f32 = min(2.0 * pow(Shift, 4.0), 30.0);
            var GridCol: vec4<f32> = vec4<f32>(BlackbodyColor * Intensity, 1.0);
            var Alpha: f32 = GridIntensity * 0.5;
            CurrentResult = vec4<f32>(CurrentResult.rgb + GridCol.rgb * Alpha * (1.0 - CurrentResult.a), CurrentResult.a);
            CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
        }
    }
    return CurrentResult;
}
