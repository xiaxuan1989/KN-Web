// NPGS BlackHole_common.glsl:118–208, 355–364, 1496–1857, 2570–2805, 3862–3882.
// Port the executed DiskColor / JetColor branches (iWhitehole=0, iPolarization=0,
// iUseImageDisk=0). Both modules intentionally share a persistent sampling phase.
override RADIATION_ENABLED: bool = true;
struct RadiationSettings {
    geometry: vec4<f32>, // inner / outer radius, half thickness (Rs), hopper
    material: vec4<f32>, // mu, Eddington accretion rate, disk brightness, opacity
    color: vec4<f32>,    // reddening, saturation, temperature / shift color exponents
    effects: vec4<f32>,  // shift intensity exponent, ring brightness / temperature, boostRot
    jet: vec4<f32>,      // shift intensity exponent, brightness, saturation, shift max
    control: vec4<f32>,  // disk / jet switches; remaining words reserved
};
fn FiniteEmissionPosition(p: vec3<f32>) -> bool {
    return all((bitcast<vec3<u32>>(p) & vec3<u32>(0x7f800000u)) != vec3<u32>(0x7f800000u));
}
// Keep the original clamped-spin ISCO efficiency calculation, including the
// omission of charge. This is the executed native temperature normalization.
fn DiskThermodynamics(massSolar: f32, spin: f32, mu: f32, rate: f32) -> vec2<f32> {
    let s = clamp(spin, -0.99, 0.99);
    let a2 = s*s;
    let absA = abs(s);
    let commonTerm = pow(1.0-a2, 1.0/3.0);
    let Z1 = 1.0+commonTerm*(pow(1.0+absA,1.0/3.0)+pow(1.0-absA,1.0/3.0));
    let Z2 = sqrt(3.0*a2+Z1*Z1);
    let rootTerm = sqrt(max(0.0,(3.0-Z1)*(3.0+Z1+2.0*Z2)));
    let RmsM = 3.0+Z2-sign(s)*rootTerm;
    let efficiency = sqrt(max(0.001,1.0-(2.0/3.0)/RmsM));
    let argument = 1.52491e30/massSolar*(mu/efficiency)*rate;
    return vec2<f32>(argument,pow(argument*0.05665278,0.25));
}
fn HasDisk(settings: RadiationSettings) -> bool {
    let g = settings.geometry;
    return settings.control.x > 0.5 && IsAccretionDiskVisible(g.x,g.y,g.z,g.w,settings.material.z,settings.material.w);
}
fn HasJet(settings: RadiationSettings) -> bool {
    return settings.control.y > 0.5 && IsJetVisible(settings.material.y,settings.jet.y);
}

fn RandomStep(Input: vec2<f32>, Seed: f32) -> f32 {
    return fract(sin(dot(Input + vec2<f32>(fract(11.4514 * sin(Seed))), vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn CubicInterpolate(x: f32) -> f32 {
    return 3.0 * pow(x, 2.0) - 2.0 * pow(x, 3.0);
}

fn PerlinNoise(Position: vec3<f32>) -> f32 {
    var PosInt: vec3<f32>   = floor(Position);
    var PosFloat: vec3<f32> = fract(Position);

    var Sx: f32 = CubicInterpolate(PosFloat.x);
    var Sy: f32 = CubicInterpolate(PosFloat.y);
    var Sz: f32 = CubicInterpolate(PosFloat.z);

    var v000: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x,       PosInt.y,       PosInt.z),       vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    var v100: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x + 1.0, PosInt.y,       PosInt.z),       vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    var v010: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x,       PosInt.y + 1.0, PosInt.z),       vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    var v110: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x + 1.0, PosInt.y + 1.0, PosInt.z),       vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    var v001: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x,       PosInt.y,       PosInt.z + 1.0), vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    var v101: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x + 1.0, PosInt.y,       PosInt.z + 1.0), vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    var v011: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x,       PosInt.y + 1.0, PosInt.z + 1.0), vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    var v111: f32 = 2.0 * fract(sin(dot(vec3<f32>(PosInt.x + 1.0, PosInt.y + 1.0, PosInt.z + 1.0), vec3<f32>(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;

    return mix(mix(mix(v000, v100, Sx), mix(v010, v110, Sx), Sy),
    mix(mix(v001, v101, Sx), mix(v011, v111, Sx), Sy), Sz);
}

fn SoftSaturate(x: f32) -> f32 {
    return 1.0 - 1.0 / (max(x, 0.0) + 1.0);
}

fn PerlinNoise1D(Position: f32) -> f32 {
    var PosInt: f32   = floor(Position);
    var PosFloat: f32 = fract(Position);
    var v0: f32 = 2.0 * fract(sin(PosInt * 12.9898) * 43758.5453) - 1.0;
    var v1: f32 = 2.0 * fract(sin((PosInt + 1.0) * 12.9898) * 43758.5453) - 1.0;
    return v1 * CubicInterpolate(PosFloat) + v0 * CubicInterpolate(1.0 - PosFloat);
}

fn GenerateAccretionDiskNoise(Position: vec3<f32>, NoiseStartLevel: f32, NoiseEndLevel: f32, ContrastLevel: f32) -> f32 {
    var NoiseAccumulator: f32 = 10.0;
    var noiseStart: f32 = NoiseStartLevel;
    var noiseEnd: f32 = NoiseEndLevel;
    var iStart: i32 = i32(floor(noiseStart));
    var iEnd: i32 = i32(ceil(noiseEnd));

    var maxIterations: i32 = iEnd - iStart;
    for (var delta: i32 = 0; delta < maxIterations; delta++)
    {
        var i: i32 = iStart + delta;
        var iFloat: f32 = f32(i);
        var w: f32 = max(0.0, min(noiseEnd, iFloat + 1.0) - max(noiseStart, iFloat));
        if (w <= 0.0) { continue; }

        var NoiseFrequency: f32 = pow(3.0, iFloat);
        var ScaledPosition: vec3<f32> = NoiseFrequency * Position;
        var noise: f32 = PerlinNoise(ScaledPosition);
        NoiseAccumulator *= (1.0 + 0.1 * noise * w);
    }
    return log(1.0 + pow(0.1 * NoiseAccumulator, ContrastLevel));
}

fn Shape(x: f32, Alpha: f32, Beta: f32) -> f32 {
    var k: f32 = pow(Alpha + Beta, Alpha + Beta) / (pow(Alpha, Alpha) * pow(Beta, Beta));
    return k * pow(x, Alpha) * pow(1.0 - x, Beta);
}

fn GetKeplerianAngularVelocity(Radius: f32, Rs: f32, PhysicalSpinA: f32, PhysicalQ: f32) -> f32 {
    var M: f32 = 0.5 * Rs;
    var Mr_minus_Q2: f32 = M * Radius - PhysicalQ * PhysicalQ;
    if (Mr_minus_Q2 < 0.0) { return 0.0; }
    var sqrt_Term: f32 = sqrt(Mr_minus_Q2);
    var denominator: f32 = Radius * Radius + PhysicalSpinA * sqrt_Term;
    return sqrt_Term / max(1e-6, denominator);
}

fn IsAccretionDiskVisible(InterR: f32, OuterR: f32, Thin: f32, Hopper: f32, Bright: f32, Dark: f32) -> bool {
    if (InterR >= OuterR) { return false; }
    if (Thin <= 0.0 && Hopper == 0.0) { return false; }
    if (Bright <= 0.0 && Dark < 0.0) { return false; }

    return true;
}

fn IsJetVisible(AccretionRate: f32, JetBright: f32) -> bool {
    if (AccretionRate < 1e-2) { return false; }
    if (JetBright <= 0.0) { return false; }
    return true;
}

fn DiskColor(BaseColor: vec4<f32>, RayPos: vec4<f32>, LastRayPos: vec4<f32>, iP_cov: vec4<f32>, lastiP_cov: vec4<f32>, iE_obs: f32, InterRadius: f32, OuterRadius: f32, Thin: f32, Hopper: f32, Brightmut: f32, Darkmut: f32, Reddening: f32, Saturation: f32, DiskTemperatureArgument: f32, BlackbodyIntensityExponent: f32, RedShiftColorExponent: f32, RedShiftIntensityExponent: f32, PeakTemperature: f32, ShiftMax: f32, PhysicalSpinA: f32, PhysicalQ: f32, isoutgoing: bool, ThetaInShell: f32, RayMarchPhase: ptr<function, f32>, blackHoleTime: f32, renderTime: f32, settings: RadiationSettings) -> vec4<f32> {
    var CurrentResult: vec4<f32> = BaseColor;

    var MaxDiskHalfHeight: f32 = Thin + max(0.0, Hopper * OuterRadius) + 2.0;
    if (LastRayPos.y > MaxDiskHalfHeight && RayPos.y > MaxDiskHalfHeight) { return BaseColor; }
    if (LastRayPos.y < -MaxDiskHalfHeight && RayPos.y < -MaxDiskHalfHeight) { return BaseColor; }

    var P0: vec2<f32> = LastRayPos.xz;
    var P1: vec2<f32> = RayPos.xz;
    var V: vec2<f32>  = P1 - P0;
    var LenSq: f32 = dot(V, V);
    var t_closest: f32 = select(0.0, clamp(-dot(P0, V) / LenSq, 0.0, 1.0), LenSq > 1e-8);
    var ClosestPoint: vec2<f32> = P0 + V * t_closest;
    if (dot(ClosestPoint, ClosestPoint) > (OuterRadius * 1.1) * (OuterRadius * 1.1)) { return BaseColor; }

    var StartPos: vec3<f32> = LastRayPos.xyz;
    var EndPos: vec3<f32>   = RayPos.xyz;
    var ChordDelta: vec3<f32> = EndPos - StartPos;
    var ChordDir: vec3<f32> = select(vec3<f32>(0.0, 1.0, 0.0), normalize(ChordDelta), length(ChordDelta) > 1e-8);

    var MidPos: vec3<f32> = 0.5 * (StartPos + EndPos);
    var geo_mid: KerrGeometry;

    geo_mid = ComputeGeometryScalars(MidPos, PhysicalSpinA, PhysicalQ, 1.0, 1.0, isoutgoing);
    var l_dot_dx: f32 = dot(geo_mid.l_down.xyz, ChordDelta);

    var proper_dist: f32 = sqrt(max(1e-9, dot(ChordDelta, ChordDelta) + geo_mid.f * l_dot_dx * l_dot_dx));

    var StartTimeLag: f32 = LastRayPos.w;
    var EndTimeLag: f32   = RayPos.w;

    var R_Start: f32 = KerrSchildRadius(StartPos, PhysicalSpinA, 1.0);
    var R_End: f32   = KerrSchildRadius(RayPos.xyz, PhysicalSpinA, 1.0);
    if (max(R_Start, R_End) < InterRadius * 0.9) { return BaseColor; }

    var TotalDist: f32 = proper_dist;
    var TraveledDist: f32 = 0.0;

    var SafetyLoopCount: i32 = 0;
    let MaxLoops: i32 = 114514;

    while (TraveledDist < TotalDist && SafetyLoopCount < MaxLoops)
    {
        if (CurrentResult.a > 0.99) { break; }
        SafetyLoopCount++;

        var CurrentPos: vec3<f32> = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        var DistanceToBlackHole: f32 = length(CurrentPos);

        var SmallStepBoundary: f32 = max(OuterRadius, 12.0);
        var StepSize: f32 = 1.0;

        StepSize *= 0.15 + 0.25 * min(max(0.0, 0.5 * (0.5 * DistanceToBlackHole / max(10.0 , SmallStepBoundary) - 1.0)), 1.0);
        if ((DistanceToBlackHole) >= 2.0 * SmallStepBoundary) { StepSize *= DistanceToBlackHole; }
        else if ((DistanceToBlackHole) >= 1.0 * SmallStepBoundary) { StepSize *= ((1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0)) * (2.0 * SmallStepBoundary - DistanceToBlackHole) + DistanceToBlackHole * (DistanceToBlackHole - SmallStepBoundary)) / SmallStepBoundary; }
        else { StepSize *= min(1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0), DistanceToBlackHole); }

        StepSize = max(0.01, StepSize);

        var DistToNextSample: f32 = (*RayMarchPhase) * StepSize;
        var NextTarget: f32 = min(TotalDist, TraveledDist + DistToNextSample);

        var PosPrev: vec3<f32> = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        var PosNext: vec3<f32> = mix(StartPos, EndPos, clamp(NextTarget / max(1e-9, TotalDist), 0.0, 1.0));

        var crossed: bool = (PosPrev.y * PosNext.y < 0.0);
        var shouldSample: bool = false;
        var SamplePos: vec3<f32> = PosNext;
        crossed = false; // Native executable disables the thin-plane shortcut.

        if (crossed)
        {
            var t_cross: f32 = abs(PosPrev.y) / max(1e-9, abs(PosPrev.y) + abs(PosNext.y));
            var CPoint: vec3<f32> = mix(PosPrev, PosNext, t_cross);

            SamplePos = CPoint + min(Thin, length(CPoint - PosPrev)) * ChordDir * (-1.0 + 2.0 * RandomStep(10000.0 * (CPoint.zx / OuterRadius), fract(renderTime * 1.0 + 0.5)));
            shouldSample = true;

            (*RayMarchPhase) = 1.0;
            TraveledDist = NextTarget;
        }
        else
        {
            if (NextTarget < TotalDist)
            {
                SamplePos = PosNext;
                shouldSample = true;
                (*RayMarchPhase) = 1.0;
                TraveledDist = NextTarget;
            }
            else
            {
                var DistanceTraveled: f32 = TotalDist - TraveledDist;
                (*RayMarchPhase) -= DistanceTraveled / StepSize;
                if ((*RayMarchPhase) < 0.0) { (*RayMarchPhase) = 0.0; }
                TraveledDist = TotalDist;
            }
        }

        if (shouldSample)
        {
            var TimeInterpolant: f32 = min(1.0, TraveledDist / max(1e-9, TotalDist));
            var CurrentRayTimeLag: f32 = mix(StartTimeLag, EndTimeLag, TimeInterpolant);

            var Sample_X: vec4<f32> = vec4<f32>(SamplePos, CurrentRayTimeLag);
            var Sample_P_cov: vec4<f32> = mix(lastiP_cov, iP_cov, TimeInterpolant);

            if (isoutgoing) {
                let transformed = transformKerrSchild_YSpin(State(Sample_X, Sample_P_cov), 1.0, 0.5, PhysicalSpinA, PhysicalQ, true);
                Sample_X = transformed.X; Sample_P_cov = transformed.P;
            }

            SamplePos = Sample_X.xyz;
            var EmissionTime: f32 = blackHoleTime + Sample_X.w;

            var PosR: f32 = KerrSchildRadius(SamplePos, PhysicalSpinA, 1.0);
            var PosY: f32 = SamplePos.y;

            var GeometricThin: f32 = Thin + max(0.0, (length(SamplePos.xz) - 3.0) * Hopper);
            var InterCloudEffectiveRadius: f32 = (PosR - InterRadius) / min(OuterRadius - InterRadius, 12.0);
            var InnerCloudBound: f32 = max(GeometricThin, Thin * 1.0) * max(0.0, 1.0 - 5.0 * pow(InterCloudEffectiveRadius, 2.0));
            var UnionBound: f32 = max(GeometricThin * 1.5, max(0.0, InnerCloudBound));

            if (abs(PosY) < UnionBound && PosR < OuterRadius && PosR > InterRadius)
            {

                var NoiseLevel: f32 = max(0.0, 2.0 - 0.6 * GeometricThin);
                var x: f32 = (PosR - InterRadius) / max(1e-6, OuterRadius - InterRadius);
                var a_param: f32 = max(1.0, (OuterRadius - InterRadius) / 10.0);
                var EffectiveRadius: f32 = (-1.0 + sqrt(max(0.0, 1.0 + 4.0 * a_param * a_param * x - 4.0 * x * a_param))) / (2.0 * a_param - 2.0);
                if(a_param == 1.0) { EffectiveRadius = x; }

                var DenAndThiFactor: f32 = Shape(EffectiveRadius, 0.9, 1.5);
                var ThicknessCap: f32 = max(1e-6, GeometricThin * DenAndThiFactor);
                if (abs(PosY) < max(ThicknessCap, InnerCloudBound)) {
                    var geo_emit: KerrGeometry;
                    geo_emit = ComputeGeometryScalars(SamplePos, PhysicalSpinA, PhysicalQ, 1.0, 1.0, false);
                    var Sample_P_up: vec4<f32> = RaiseIndex(Sample_P_cov, geo_emit);
                    var local_Dir: vec3<f32> = normalize(Sample_P_up.xyz);
                    var RotPosR_ForThick: f32 = PosR + 0.25 / 3.0 * EmissionTime;
                    var PosLogTheta_ForThick: f32 = Vec2ToTheta(SamplePos.zx, vec2<f32>(cos(-2.0 * log(max(1e-6, PosR))), sin(-2.0 * log(max(1e-6, PosR)))));
                    var ThickNoise: f32 = GenerateAccretionDiskNoise(vec3<f32>(1.5 * PosLogTheta_ForThick, RotPosR_ForThick, 0.0), -0.7 + NoiseLevel, 1.3 + NoiseLevel, 80.0);
                    var PerturbedThickness: f32 = max(1e-6, GeometricThin * DenAndThiFactor * (0.4 + 0.6 * clamp(GeometricThin - 0.5, 0.0, 2.5) / 2.5 + (1.0 - (0.4 + 0.6 * clamp(GeometricThin - 0.5, 0.0, 2.5) / 2.5)) * SoftSaturate(ThickNoise)));

                    if ((abs(PosY) < PerturbedThickness) || (abs(PosY) < InnerCloudBound))
                    {
                        var AngularVelocity: f32 = GetKeplerianAngularVelocity(max(InterRadius, PosR), 1.0, PhysicalSpinA, PhysicalQ);

                        var u: f32 = sqrt(max(1e-6, PosR));
                        var k_cubed: f32 = PhysicalSpinA * 0.70710678;
                        var SpiralTheta: f32;
                        if (abs(k_cubed) < 0.001 * u * u * u) {
                            var inv_u: f32 = 1.0 / u; var eps3: f32 = k_cubed * pow(inv_u, 3.0);
                            SpiralTheta = -16.9705627 * inv_u * (1.0 - 0.25 * eps3 + 0.142857 * eps3 * eps3);
                        } else {
                            var k: f32 = sign(k_cubed) * pow(abs(k_cubed), 0.33333333);
                            var logTerm: f32 = (PosR - k*u + k*k) / max(1e-9, pow(u+k, 2.0));
                            SpiralTheta = (5.6568542 / k) * (0.5 * log(max(1e-9, logTerm)) + 1.7320508 * (atan2(2.0*u - k, 1.7320508 * k) - 1.5707963));
                        }
                        var PosTheta: f32 = Vec2ToTheta(SamplePos.zx, vec2<f32>(cos(-SpiralTheta), sin(-SpiralTheta)));
                        var PosLogarithmicTheta: f32 = Vec2ToTheta(SamplePos.zx, vec2<f32>(cos(-2.0 * log(max(1e-6, PosR))), sin(-2.0 * log(max(1e-6, PosR)))));

                        var inv_r: f32 = 1.0 / max(1e-6, PosR);
                        var inv_r2: f32 = inv_r * inv_r;
                        var V_pot: f32 = inv_r - (PhysicalQ * PhysicalQ) * inv_r2;

                        var g_tt: f32 = -(1.0 - V_pot);
                        var g_tphi: f32 = -PhysicalSpinA * V_pot;
                        var g_phiphi: f32 = PosR * PosR + PhysicalSpinA * PhysicalSpinA + PhysicalSpinA * PhysicalSpinA * V_pot;
                        var norm_metric: f32 = g_tt + 2.0 * AngularVelocity * g_tphi + AngularVelocity * AngularVelocity * g_phiphi;

                        var min_norm: f32 = -0.01;
                        var u_t: f32 = inverseSqrt(max(abs(min_norm), -norm_metric));

                        var P_phi: f32 = - SamplePos.x * Sample_P_cov.z + SamplePos.z * Sample_P_cov.x;
                        var E_emit: f32 = u_t * (iE_obs - AngularVelocity * P_phi);
                        var FreqRatio: f32 = 1.0 / max(1e-6, E_emit);

                        var DiskTemperature: f32 = pow(DiskTemperatureArgument * pow(1.0 / max(1e-6, PosR), 3.0) * max(1.0 - sqrt(InterRadius / max(1e-6, PosR)), 0.000001), 0.25);
                        var VisionTemperature: f32 = DiskTemperature * pow(FreqRatio, RedShiftColorExponent);
                        var BrightWithoutRedshift: f32 = 0.05 * min(OuterRadius / (1000.0), 1000.0 / OuterRadius) + 0.55 / exp(5.0 * EffectiveRadius) * mix(0.2 + 0.8 * abs(local_Dir.y), 1.0, clamp(GeometricThin - 0.8, 0.2, 1.0));
                        BrightWithoutRedshift *= pow(DiskTemperature / PeakTemperature, BlackbodyIntensityExponent);

                        var RotPosR: f32 = PosR + 0.25 / 3.0 * EmissionTime;
                        var Density: f32 = DenAndThiFactor;
                        var SampleColor: vec4<f32> = vec4<f32>(0.0);

                        if (abs(PosY) < PerturbedThickness)
                        {
                            var Levelmut: f32 = 0.91 * log(1.0 + (0.06 / 0.91 * max(0.0, min(1000.0, PosR) - 10.0)));
                            var Conmut: f32 = 80.0 * log(1.0 + (0.1 * 0.06 * max(0.0, min(1000000.0, PosR) - 10.0)));

                            SampleColor = vec4<f32>(GenerateAccretionDiskNoise(vec3<f32>(0.1 * RotPosR, 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * PosTheta), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 4.0 - Levelmut, 80.0 - Conmut));

                            if(PosTheta + kPi < 0.1 * kPi) {
                                SampleColor *= (PosTheta + kPi) / (0.1 * kPi);
                                SampleColor += (1.0 - ((PosTheta + kPi) / (0.1 * kPi))) * vec4<f32>(GenerateAccretionDiskNoise(vec3<f32>(0.1 * RotPosR, 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * (PosTheta + 2.0 * kPi)), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 4.0 - Levelmut, 80.0 - Conmut));
                            }

                            if(PosR > max(0.15379 * OuterRadius, 0.15379 * 64.0)) {
                                var TimeShiftedRadiusTerm: f32 = PosR * (4.65114e-6) - 0.1 / 3.0 * EmissionTime;
                                var Spir: f32 = (GenerateAccretionDiskNoise(vec3<f32>(0.1 * (TimeShiftedRadiusTerm - 0.08 * OuterRadius * PosLogarithmicTheta), 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * PosLogarithmicTheta), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 3.0 - Levelmut, 80.0 - Conmut));
                                if(PosLogarithmicTheta + kPi < 0.1 * kPi) {
                                    Spir *= (PosLogarithmicTheta + kPi) / (0.1 * kPi);
                                    Spir += (1.0 - ((PosLogarithmicTheta + kPi) / (0.1 * kPi))) * (GenerateAccretionDiskNoise(vec3<f32>(0.1 * (TimeShiftedRadiusTerm - 0.08 * OuterRadius * (PosLogarithmicTheta + 2.0 * kPi)), 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * (PosLogarithmicTheta + 2.0 * kPi)), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 3.0 - Levelmut, 80.0 - Conmut));
                                }
                                SampleColor *= (mix(1.0, clamp(0.7 * Spir * 1.5 - 0.5, 0.0, 3.0), 0.5 + 0.5 * max(-1.0, 1.0 - exp(-1.5 * 0.1 * (100.0 * PosR / max(OuterRadius, 64.0) - 20.0)))));
                            }

                            var VerticalMixFactor: f32 = max(0.0, (1.0 - abs(PosY) / PerturbedThickness));
                            Density *= 0.7 * VerticalMixFactor * Density;
                            SampleColor = vec4<f32>(SampleColor.xyz * (Density * 1.4), SampleColor.w);
                            SampleColor.a *= (Density) * (Density) / 0.3;

                            var RelHeight: f32 = clamp(abs(PosY) / PerturbedThickness, 0.0, 1.0);
                            SampleColor = vec4<f32>(SampleColor.xyz * (max(0.0, (0.2 + 2.0 * sqrt(max(0.0, RelHeight * RelHeight + 0.001))))), SampleColor.w);
                        }

                        SampleColor = vec4<f32>(SampleColor.xyz * (1.0 + clamp(settings.effects.y, 0.0, 10.0) * clamp(0.3 * ThetaInShell - 0.1, 0.0, 1.0)), SampleColor.w);
                        VisionTemperature *= 1.0 + clamp(settings.effects.z, 0.0, 10.0) * clamp(0.3 * ThetaInShell - 0.1, 0.0, 1.0);

                        var InnerAngVel: f32 = GetKeplerianAngularVelocity(max(3.0, InterRadius), 1.0, PhysicalSpinA, PhysicalQ);
                        var InnerCloudTimePhase: f32 = kPi / (kPi / max(1e-6, InnerAngVel)) * EmissionTime;
                        var InnerRotArg: f32 = 0.666666 * InnerCloudTimePhase;
                        var PosThetaForInnerCloud: f32 = Vec2ToTheta(SamplePos.zx, vec2<f32>(cos(InnerRotArg), sin(InnerRotArg)));

                        if (abs(PosY) < InnerCloudBound)
                        {
                            var DustIntensity: f32 = max(1.0 - pow(PosY / (GeometricThin * max(1.0 - 5.0 * pow(InterCloudEffectiveRadius, 2.0), 0.0001)), 2.0), 0.0);
                            if (DustIntensity > 0.0) {
                                var DustNoise: f32 = GenerateAccretionDiskNoise(vec3<f32>(1.5 * fract((1.5 * PosThetaForInnerCloud + InnerCloudTimePhase) / 2.0 / kPi) * 2.0 * kPi, PosR, PosY), 0.0, 6.0, 80.0);

                                var BlendWidth: f32 = 0.1 * kPi;
                                if (PosThetaForInnerCloud + kPi < BlendWidth) {
                                    var BlendFactor: f32 = (PosThetaForInnerCloud + kPi) / BlendWidth;

                                    var WrappedTheta: f32 = PosThetaForInnerCloud + 2.0 * kPi;
                                    var DustNoiseWrapped: f32 = GenerateAccretionDiskNoise(vec3<f32>(1.5 * fract((1.5 * WrappedTheta + InnerCloudTimePhase) / 2.0 / kPi) * 2.0 * kPi, PosR, PosY), 0.0, 6.0, 80.0);

                                    DustNoise = mix(DustNoiseWrapped, DustNoise, BlendFactor);
                                }

                                var DustVal: f32 = DustIntensity * DustNoise;
                                SampleColor += 0.02 * vec4<f32>(vec3<f32>(DustVal), 0.2 * DustVal) * sqrt(max(0.0, 1.0001 - local_Dir.y * local_Dir.y));
                            }
                        }

                        SampleColor = vec4<f32>(SampleColor.xyz * (BrightWithoutRedshift * KelvinToRgb(VisionTemperature)), SampleColor.w);
                        SampleColor = vec4<f32>(SampleColor.xyz * (min(pow(FreqRatio, RedShiftIntensityExponent), ShiftMax)), SampleColor.w);
                        SampleColor = vec4<f32>(SampleColor.xyz * (min(1.0, 1.3 * (OuterRadius - PosR) / (OuterRadius - InterRadius))), SampleColor.w);
                        SampleColor.a   *= 0.125;

                        var DilutionOuterRadius: f32 = mix(min(OuterRadius, 25.0), OuterRadius, smoothstep(6.0, max(0.05 * OuterRadius, 12.0), PosR));
                        var BoostFactor: vec4<f32> = max(
                        mix(vec4<f32>(5.0 / (max(Thin, 0.2) + (0.0 + Hopper * 0.5) * DilutionOuterRadius)), vec4<f32>(vec3<f32>(0.3 + 0.7 * 5.0 / (Thin + (0.0 + Hopper * 0.5) * DilutionOuterRadius)), 1.0), 0.0),

                        mix(vec4<f32>(100.0 / DilutionOuterRadius), vec4<f32>(vec3<f32>(0.3 + 0.7 * 100.0 / DilutionOuterRadius), 1.0), exp(-pow(20.0 * PosR / DilutionOuterRadius, 2.0)))
                        );
                        SampleColor *= BoostFactor;

                        var InnerBrightenFac: f32 = mix(3.0, 2.0, clamp((OuterRadius - 50.0) / 50.0, 0.0, 1.0));
                        var InnerBrightenRatio: f32 = 1.0 - clamp(6.0 * (PosR - InterRadius) / (OuterRadius - InterRadius), 0.0, 1.0);
                        InnerBrightenRatio *= InnerBrightenRatio;

                        SampleColor = vec4<f32>(SampleColor.xyz * (mix(1.0, max(1.0, abs(local_Dir.y) / 0.2), clamp(0.3 - 0.6 * (PerturbedThickness / max(1e-6, Density) - 1.0), 0.0, 0.3))), SampleColor.w);

                        SampleColor = vec4<f32>(SampleColor.xyz * (1.0 + 1.2 * max(0.0, max(0.0, min(1.0, 3.0 - 2.0 * Thin)) * min(0.5, 1.0 - 5.0 * Hopper))), SampleColor.w);

                        SampleColor = vec4<f32>(SampleColor.xyz * (Brightmut * (1.0 + InnerBrightenFac * InnerBrightenRatio)), SampleColor.w);
                        SampleColor.a   *= Darkmut * (1.0 + (1.0 + InnerBrightenFac) * InnerBrightenRatio);

                        if (E_emit < 0.0)
                        {
                            var cMax: f32 = max(max(SampleColor.r, SampleColor.g), SampleColor.b);
                            var cMin: f32 = min(min(SampleColor.r, SampleColor.g), SampleColor.b);
                            SampleColor = vec4<f32>(vec3<f32>(cMax + cMin) - SampleColor.rgb, SampleColor.w);
                            SampleColor = vec4<f32>(0.0);
                        }

                        var StepColor: vec4<f32> = SampleColor * StepSize;

                        var aR: f32 = 1.0 + Reddening * (1.0 - 1.0);
                        var aG: f32 = 1.0 + Reddening * (3.0 - 1.0);
                        var aB: f32 = 1.0 + Reddening * (6.0 - 1.0);

                        var Sum_rgb: f32 = (StepColor.r + StepColor.g + StepColor.b) * pow(1.0 - CurrentResult.a, aG);
                        var Denominator: f32 = StepColor.r * pow(1.0 - CurrentResult.a, aR) + StepColor.g * pow(1.0 - CurrentResult.a, aG) + StepColor.b * pow(1.0 - CurrentResult.a, aB);

                        var r001: f32 = 0.0; var g001: f32 = 0.0; var b001: f32 = 0.0;
                        if (Denominator > 0.000001)
                        {
                            r001 = Sum_rgb * StepColor.r * pow(1.0 - CurrentResult.a, aR) / Denominator;
                            g001 = Sum_rgb * StepColor.g * pow(1.0 - CurrentResult.a, aG) / Denominator;
                            b001 = Sum_rgb * StepColor.b * pow(1.0 - CurrentResult.a, aB) / Denominator;

                            // Saturation updates channels sequentially in NPGS.
                            r001 *= pow(3.0 * r001 / (r001 + g001 + b001), Saturation);
                            g001 *= pow(3.0 * g001 / (r001 + g001 + b001), Saturation);
                            b001 *= pow(3.0 * b001 / (r001 + g001 + b001), Saturation);
                        }

                        CurrentResult.r += r001;
                        CurrentResult.g += g001;
                        CurrentResult.b += b001;
                        CurrentResult.a += StepColor.a * (1.0 - CurrentResult.a);
                    }
                }
            }
        }
    }
    return CurrentResult;
}

fn JetColor(BaseColor: vec4<f32>, RayPos: vec4<f32>, LastRayPos: vec4<f32>, iP_cov: vec4<f32>, lastiP_cov: vec4<f32>, iE_obs: f32, InterRadius: f32, OuterRadius: f32, JetRedShiftIntensityExponent: f32, JetBrightmut: f32, JetReddening: f32, JetSaturation: f32, AccretionRate: f32, JetShiftMax: f32, PhysicalSpinA: f32, PhysicalQ: f32, isoutgoing: bool, RayMarchPhase: ptr<function, f32>, blackHoleTime: f32, renderTime: f32, settings: RadiationSettings) -> vec4<f32> {
    var CurrentResult: vec4<f32> = BaseColor;
    var StartPos: vec3<f32> = LastRayPos.xyz;
    var EndPos: vec3<f32>   = RayPos.xyz;

    if (!FiniteEmissionPosition(StartPos)) { return BaseColor; }

    var ChordDelta: vec3<f32> = EndPos - StartPos;
    var MidPos: vec3<f32> = 0.5 * (StartPos + EndPos);
    var geo_mid: KerrGeometry;
    geo_mid = ComputeGeometryScalars(MidPos, PhysicalSpinA, PhysicalQ, 1.0, 1.0, isoutgoing);

    var l_dot_dx: f32 = dot(geo_mid.l_down.xyz, ChordDelta);
    var proper_dist: f32 = sqrt(max(1e-9, dot(ChordDelta, ChordDelta) + geo_mid.f * l_dot_dx * l_dot_dx));

    var StartTimeLag: f32 = LastRayPos.w;
    var EndTimeLag: f32   = RayPos.w;

    var TotalDist: f32 = proper_dist;
    var TraveledDist: f32 = 0.0;

    var R_Start: f32 = length(StartPos.xz);
    var R_End: f32   = length(RayPos.xz);
    var MaxR_XZ: f32 = max(R_Start, R_End);
    var MaxY: f32    = max(abs(StartPos.y), abs(RayPos.y));

    if (MaxR_XZ > OuterRadius * 1.5 && MaxY < OuterRadius) { return BaseColor; }

    var SafetyLoopCount: i32 = 0;
    let MaxLoops: i32 = 114514;

    while (TraveledDist < TotalDist && SafetyLoopCount < MaxLoops)
    {
        if (CurrentResult.a > 0.99) { break; }
        SafetyLoopCount++;

        var CurrentPos: vec3<f32> = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        var DistanceToBlackHole: f32 = length(CurrentPos);

        var SmallStepBoundary: f32 = max(OuterRadius, 12.0);
        var StepSize: f32 = 1.0;

        StepSize *= 0.15 + 0.25 * min(max(0.0, 0.5 * (0.5 * DistanceToBlackHole / max(10.0 , SmallStepBoundary) - 1.0)), 1.0);
        if ((DistanceToBlackHole) >= 2.0 * SmallStepBoundary) { StepSize *= DistanceToBlackHole; }
        else if ((DistanceToBlackHole) >= 1.0 * SmallStepBoundary) { StepSize *= ((1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0)) * (2.0 * SmallStepBoundary - DistanceToBlackHole) + DistanceToBlackHole * (DistanceToBlackHole - SmallStepBoundary)) / SmallStepBoundary; }
        else { StepSize *= min(1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0), DistanceToBlackHole); }

        StepSize = max(0.01, StepSize);

        var DistToNextSample: f32 = (*RayMarchPhase) * StepSize;
        var NextTarget: f32 = min(TotalDist, TraveledDist + DistToNextSample);

        var shouldSample: bool = false;
        if (NextTarget < TotalDist)
        {
            shouldSample = true;
            (*RayMarchPhase) = 1.0;
            TraveledDist = NextTarget;
        }
        else
        {
            var DistanceTraveled: f32 = TotalDist - TraveledDist;
            (*RayMarchPhase) -= DistanceTraveled / StepSize;
            if((*RayMarchPhase) < 0.0) { (*RayMarchPhase) = 0.0; }
            TraveledDist = TotalDist;
        }

        if (shouldSample)
        {

            var TimeInterpolant: f32 = min(1.0, TraveledDist / max(1e-9, TotalDist));
            var OrigSamplePos: vec3<f32> = mix(StartPos, EndPos, TimeInterpolant);
            var CurrentRayTimeLag: f32 = mix(StartTimeLag, EndTimeLag, TimeInterpolant);

            var Sample_X: vec4<f32> = vec4<f32>(OrigSamplePos, CurrentRayTimeLag);
            var Sample_P_cov: vec4<f32> = mix(lastiP_cov, iP_cov, TimeInterpolant);

            if (isoutgoing) {
                let transformed = transformKerrSchild_YSpin(State(Sample_X, Sample_P_cov), 1.0, 0.5, PhysicalSpinA, PhysicalQ, true);
                Sample_X = transformed.X; Sample_P_cov = transformed.P;
            }

            var SamplePos: vec3<f32> = Sample_X.xyz;
            var EmissionTime: f32 = blackHoleTime + Sample_X.w;

            var PosR: f32 = KerrSchildRadius(SamplePos, PhysicalSpinA, 1.0);
            var PosY: f32 = SamplePos.y;
            var RhoSq: f32 = dot(SamplePos.xz, SamplePos.xz);
            var Rho: f32 = sqrt(RhoSq);

            var AccumColor: vec4<f32> = vec4<f32>(0.0);
            var InJet: bool = false;

            var Wid: f32 = abs(PosY);
            if (Rho < 1.3 * InterRadius + 0.25 * Wid && Rho > 0.7 * InterRadius + 0.15 * Wid && PosR < 30.0 * InterRadius)
            {
                InJet = true;
                var InnerTheta: f32 = 2.0 * GetKeplerianAngularVelocity(InterRadius, 1.0, PhysicalSpinA, PhysicalQ) * (EmissionTime - 1.0 / 0.8 * abs(PosY));
                var ShapeVal: f32 = 1.0 / max(1e-9, (InterRadius + 0.2 * Wid));

                var Twist: f32 = 0.2 * (1.1 - exp(-0.1 * 0.1 * PosY * PosY)) * (PerlinNoise1D(0.35 * (EmissionTime - 1.0 / 0.8 * abs(PosY)) / (1.0 / 0.8)) - 0.5);
                var TwistedPos: vec2<f32> = SamplePos.xz + Twist * vec2<f32>(cos(0.666666 * InnerTheta), -sin(0.666666 * InnerTheta));

                var Col: vec4<f32> = vec4<f32>(1.0, 1.0, 1.0, 0.5) * max(0.0, 1.0 - 2.0 * abs(1.0 - pow(length(TwistedPos) * ShapeVal, 2.0))) * ShapeVal;
                Col *= 1.0 - exp(-PosY / max(1e-6, InterRadius) * PosY / max(1e-6, InterRadius));
                Col *= exp(-0.005 * PosY / max(1e-6, InterRadius) * PosY / max(1e-6, InterRadius));
                Col *= 0.5;

                AccumColor += Col * StepSize;
            }

            if (InJet)
            {

                var geo_sample: KerrGeometry;

                geo_sample = ComputeGeometryScalars(SamplePos, PhysicalSpinA, PhysicalQ, 1.0, 1.0, false);

                var v_jet: f32 = 0.8;
                var Gamma: f32 = 1.6666667;
                var U_spatial: vec3<f32> = vec3<f32>(0.0, sign(PosY) * Gamma * v_jet, 0.0);

                var l_dot_u_sp: f32 = dot(geo_sample.l_down.xyz, U_spatial);
                var U_sp_sq: f32 = dot(U_spatial, U_spatial);

                var A: f32 = -1.0 + geo_sample.f;
                var B: f32 = 2.0 * geo_sample.f * l_dot_u_sp;
                var C: f32 = U_sp_sq + geo_sample.f * l_dot_u_sp * l_dot_u_sp + 1.0;

                var Det: f32 = B * B - 4.0 * A * C;

                if (Det < 0.0) {
                    if (A < 0.0) {
                        U_spatial *= 0.5;
                    } else {
                        U_spatial = -1.5 * geo_sample.grad_r;
                    }
                    l_dot_u_sp = dot(geo_sample.l_down.xyz, U_spatial);
                    U_sp_sq = dot(U_spatial, U_spatial);
                    C = U_sp_sq + geo_sample.f * l_dot_u_sp * l_dot_u_sp + 1.0;
                    B = 2.0 * geo_sample.f * l_dot_u_sp;
                    Det = max(0.0, B * B - 4.0 * A * C);
                }

                var sqrtDet: f32 = sqrt(Det);
                var Ut: f32;
                if (abs(A) < 1e-7) {
                    Ut = -C / max(1e-19, B);
                } else {
                    if (B < 0.0) {
                        Ut = 2.0 * C / (-B + sqrtDet);
                    } else {
                        Ut = (-B - sqrtDet) / (2.0 * A);
                    }
                }

                var U_jet: vec4<f32> = vec4<f32>(U_spatial, Ut);

                var E_emit: f32 = -dot(Sample_P_cov, U_jet);
                var FreqRatio: f32 = 1.0 / max(1e-6, E_emit);

                var JetTemperature: f32 = min(100000.0 * FreqRatio,100000.0);
                AccumColor = vec4<f32>(AccumColor.xyz * (KelvinToRgb(JetTemperature)), AccumColor.w);
                AccumColor = vec4<f32>(AccumColor.xyz * (min(pow(FreqRatio, JetRedShiftIntensityExponent), JetShiftMax)), AccumColor.w);
                AccumColor *= JetBrightmut * (0.5 + 0.5 * tanh(log(max(1e-6, AccretionRate)) + 1.0));
                AccumColor.a *= 0.0; // Native jet emits without adding opacity.

                var IsPositiveEnergy: bool = E_emit > 0.0;
                if (!IsPositiveEnergy)
                {
                    var cMax: f32 = max(max(AccumColor.r, AccumColor.g), AccumColor.b);
                    var cMin: f32 = min(min(AccumColor.r, AccumColor.g), AccumColor.b);
                    AccumColor = vec4<f32>(vec3<f32>(cMax + cMin) - AccumColor.rgb, AccumColor.w);
                }

                var aR: f32 = 1.0 + JetReddening * (1.0 - 1.0);
                var aG: f32 = 1.0 + JetReddening * (3.0 - 1.0);
                var aB: f32 = 1.0 + JetReddening * (6.0 - 1.0);
                var Sum_rgb: f32 = (AccumColor.r + AccumColor.g + AccumColor.b) * pow(1.0 - CurrentResult.a, aG);

                var Denominator: f32 = AccumColor.r * pow(1.0 - CurrentResult.a, aR) + AccumColor.g * pow(1.0 - CurrentResult.a, aG) + AccumColor.b * pow(1.0 - CurrentResult.a, aB);
                var r001: f32 = 0.0; var g001: f32 = 0.0; var b001: f32 = 0.0;
                if (Denominator > 0.000001)
                {
                    r001 = Sum_rgb * AccumColor.r * pow(1.0 - CurrentResult.a, aR) / Denominator;
                    g001 = Sum_rgb * AccumColor.g * pow(1.0 - CurrentResult.a, aG) / Denominator;
                    b001 = Sum_rgb * AccumColor.b * pow(1.0 - CurrentResult.a, aB) / Denominator;

                    r001 *= pow(3.0 * r001 / (r001 + g001 + b001), JetSaturation);
                    g001 *= pow(3.0 * g001 / (r001 + g001 + b001), JetSaturation);
                    b001 *= pow(3.0 * b001 / (r001 + g001 + b001), JetSaturation);
                }

                CurrentResult.r += r001;
                CurrentResult.g += g001;
                CurrentResult.b += b001;
                CurrentResult.a += AccumColor.a * (1.0 - CurrentResult.a);
            }
        }
    }
    return CurrentResult;
}

// Native per-segment order: disk -> jet -> optional surface -> spatial grid.
fn AccumulateRadiation(base: vec4<f32>, current: State, previous: State,
energy: f32, a: f32, Q: f32, outgoing: bool, theta: f32,
phase: ptr<function,f32>, thermodynamics: vec2<f32>,
blackHoleTime: f32, renderTime: f32, settings: RadiationSettings) -> vec4<f32> {
    var result = base;
    let g = settings.geometry; let m = settings.material; let c = settings.color;
    if (HasDisk(settings)) {
        result = DiskColor(result,current.X,previous.X,current.P,previous.P,energy,
        g.x,g.y,g.z,g.w,m.z,m.w,c.x,c.y,thermodynamics.x,c.z,c.w,
        settings.effects.x,thermodynamics.y,1.0,a,Q,outgoing,theta,phase,
        blackHoleTime,renderTime,settings);
    }
    if (HasJet(settings)) {
        result = JetColor(result,current.X,previous.X,current.P,previous.P,energy,
        g.x,g.y,settings.jet.x,settings.jet.y,c.x,settings.jet.z,m.y,
        settings.jet.w,a,Q,outgoing,phase,blackHoleTime,renderTime,settings);
    }
    return result;
}
