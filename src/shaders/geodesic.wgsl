// Positive-r, disk / jet / dense-star NPGS TraceRay slice, observer modes -1/0/1/2/3 and spatial grids.
// Signed-sheet crossings remain outside this scene.
const TRACE_BOUNDARY: f32 = 501.0;
// Native 0 = Absorbed/Lost: includes horizon stops, exhausted budget and bound rays.
const TRACE_STOPPED: u32 = 0u;
const TRACE_ESCAPED: u32 = 1u;
const TRACE_OPAQUE: u32 = 3u;
const TRACE_INVALID: u32 = 255u;

struct TraceResult {
    direction: vec3<f32>, status: u32,
    steps: u32, nullError: f32,
    accumulated: vec4<f32>, // premultiplied radiation / grid emission and opacity
    energy: f32, // -P_cov.w, normalized observer photon energy is 1
};

fn GravityFadeAt(position: vec3<f32>, boundary: f32) -> f32 {
    let x = clamp(1.0 - (length(position)-100.0)/(boundary-100.0), 0.0, 1.0);
    return 3.0*x*x - 2.0*x*x*x;
}

fn ProgradePhotonRadius(spin: f32, Q: f32) -> f32 {
    let absA = abs(CONST_M*spin);
    let Q2 = Q*Q;
    var r = 2.0*CONST_M*(1.0+cos(0.66666667*acos(clamp(-abs(spin), -1.0, 1.0))));
    for (var k = 0u; k < 3u; k++) {
        let sqrt_term = sqrt(max(0.0001, CONST_M*r-Q2));
        let f = r*r - 3.0*CONST_M*r + 2.0*Q2 + 2.0*absA*sqrt_term;
        let df = 2.0*r - 3.0*CONST_M + absA*CONST_M/sqrt_term;
        if (abs(df) < 0.00001) { break; }
        r -= f/df;
    }
    return r;
}

// BlackHole_common.glsl:4847-4903. Whitehole=0, including naked MaxStep=450.
fn TraceMaxStep(spin: f32, charge: f32) -> f32 {
    if (0.25-(spin*CONST_M)*(spin*CONST_M)-(charge*CONST_M)*(charge*CONST_M) < 0.0) { return 450.0; }
    let extremality = 1.0-spin*spin-charge*charge;
    return 150.0 + 300.0/(1.0+1000.0*extremality*extremality);
}
fn TraceStepBudget(spin: f32, charge: f32, quality: f32) -> u32 {
    return u32(TraceMaxStep(spin,charge)*quality*(1.0+0.3*quality));
}

struct ObserverTetrad { U: vec4<f32>, e1: vec4<f32>, e2: vec4<f32>, e3: vec4<f32>, outgoing: bool };

fn TraceSceneRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32, mode: i32, velocity: vec3<f32>, frame: ObserverTetrad, gridMode: i32, gridTime: f32, debug: i32, settings: RadiationSettings, massSolar: f32, rayUv: vec2<f32>, renderTime: f32, star: DenseStarSettings) -> TraceResult {
    var result = TraceResult(vec3<f32>(0.0), TRACE_STOPPED, 0u, 0.0, vec4<f32>(0), 1.0);
    let starR = select(0.0,DenseStarRadius(star),RADIATION_ENABLED);
    let emitting = RADIATION_ENABLED && (HasDisk(settings) || HasJet(settings));
    var boundary = max(TRACE_BOUNDARY,spin*2.0);
    if (emitting || starR != 0.0) { boundary = max(boundary,settings.geometry.y+1.0); }
    let a = spin*CONST_M;
    let Q = charge*CONST_M;
    let discriminant = 0.25-a*a-Q*Q;
    let naked = discriminant < 0.0;
    let outer = 0.5+sqrt(max(0.0,discriminant));
    let inner = 0.5-sqrt(max(0.0,discriminant));
    let hasSurface = starR != 0.0 && (naked || starR > outer);
    var state = State(vec4<f32>(origin, 0.0), vec4<f32>(0.0));
    if (length(origin) > boundary) {
        let b = dot(origin, direction);
        let c = dot(origin, origin)-(boundary-1.0)*(boundary-1.0);
        let delta = b*b-c;
        if (delta < 0.0) { return TraceResult(direction, TRACE_ESCAPED, 0u, 0.0, vec4<f32>(0), 1.0); }
        let tEnter = -b-sqrt(delta);
        if (tEnter > 0.0) { state.X = vec4<f32>(origin+direction*tEnter, -tEnter); }
        else if (-b+sqrt(delta) <= 0.0) { return TraceResult(direction, TRACE_ESCAPED, 0u, 0.0, vec4<f32>(0), 1.0); }
    }
    var fade = GravityFadeAt(state.X.xyz,boundary);
    var outgoing = mode == -1 && frame.outgoing;
    var geo = ComputeGeometryScalars(state.X.xyz, a, Q, fade, 1.0, outgoing);
    let cameraR = geo.r;
    if (cameraR < 1e-6) { result.status = TRACE_INVALID; return result; }
    if (mode == -1) {
        state.P = GetTetradMomentum(direction,state.X,a,Q,fade,1.0,outgoing,frame.outgoing,frame.U,frame.e1,frame.e2,frame.e3);
    } else { state.P = GetObserverMomentum(direction,state.X,a,Q,fade,1.0,outgoing,mode,velocity); }
    if (all(state.P == vec4<f32>(114514.0))) { result.status = TRACE_OPAQUE; result.accumulated.a = 1.0; return result; }
    if (debug == 2) {
        result.status = TRACE_OPAQUE;
        result.accumulated = vec4<f32>(DebugInitialMomentum(state.P,state.X,mode,1.0,a,Q,fade,outgoing,velocity),1);
        return result;
    }
    // Native static-limit test: only mode 0 is excluded from the ergoregion.
    if (mode == 0) {
        let cosThetaSq = state.X.y*state.X.y/(cameraR*cameraR+1e-20);
        let sl = 0.25-Q*Q-a*a*cosThetaSq;
        if (sl >= 0.0 && cameraR < 0.5+sqrt(sl) && cameraR > 0.5-sqrt(sl)) {
            result.status = TRACE_OPAQUE; result.accumulated.a = 1.0; return result;
        }
    }
    var termination = -1.0;
    if (!naked) {
        if (cameraR > outer) { termination = outer; }
        else if (cameraR > inner) { termination = inner; }
    }
    let E = -state.P.w;
    result.energy = E;
    let shellLimit = ProgradePhotonRadius(spin, Q)-0.001;
    let originalLimit = TraceStepBudget(spin,charge,quality);
    var rayMarchPhase = 0.0;
    var thermodynamics = vec2<f32>(0);
    var thetaInShell = 0.0;
    var ingoingState = state;
    if (emitting) {
        rayMarchPhase = RandomStep(rayUv,renderTime);
        thermodynamics = DiskThermodynamics(massSolar,spin,settings.material.x,settings.material.y);
        if (outgoing) { ingoingState = transformKerrSchild_YSpin(state,1.0,CONST_M,a,Q,true); }
    }
    var lastDr = 0.0;
    var lastR = cameraR;
    var crossedInnerOutward = false;
    var crossedOuterOutward = false;
    var turningCount = 0u;

    // Keep the original strict Count > budget check below, after escape/horizon.
    // Thus budget+1 RK steps are allowed; there is no additional Web step cap.
    for (var count = 0u; ; count++) {
        result.steps = count;
        let distance = length(state.X.xyz);
        if (distance > boundary) {
            var ingoingState = state;
            if (outgoing) { ingoingState = transformKerrSchild_YSpin(state, 1.0, CONST_M, a, Q, true); }
            // Original far-boundary escape direction is -P_cov in ingoing chart.
            result.direction = normalize(-ingoingState.P.xyz);
            result.status = TRACE_ESCAPED;
            return result;
        }
        if (!naked && termination != -1.0 && geo.r < termination) {
            if (debug == 1) { result.accumulated += vec4<f32>(0,0.3,0.3,0); }
            return result;
        }
        if (count > originalLimit) {
            if (debug == 1) { result.accumulated += vec4<f32>(0,0.3,0,0); }
            if (naked && turningCount <= 2u) {
                var ingoing = state;
                if (outgoing) { ingoing = transformKerrSchild_YSpin(state,1.0,CONST_M,a,Q,true); }
                let skyGeo = ComputeGeometryScalars(ingoing.X.xyz,a,Q,fade,1.0,false);
                result.direction = normalize(-RaiseIndex(ingoing.P,skyGeo).xyz);
                result.status = TRACE_ESCAPED;
            }
            return result;
        }

        var k1 = GetDerivativesAnalytic(state, a, Q, fade, outgoing, geo);
        geo = ComputeGeometryGradients(state.X.xyz, a, Q, fade, geo);
        var currentDr = dot(geo.grad_r, k1.X.xyz);
        if (count > 0u && currentDr*lastDr < 0.0) { turningCount++; }

        let P_contra = RaiseIndex(state.P, geo);
        let currentSum = dot(abs(P_contra), vec4<f32>(1.0));
        let trial = transformKerrSchild_YSpin(state, 1.0, CONST_M, a, Q, outgoing);
        let trialGeo = ComputeGeometryScalars(trial.X.xyz, a, Q, fade, 1.0, !outgoing);
        let trialSum = dot(abs(RaiseIndex(trial.P, trialGeo)), vec4<f32>(1.0));
        if (currentSum > 2.0*trialSum) {
            state = trial;
            outgoing = !outgoing;
            geo = ComputeGeometryGradients(state.X.xyz, a, Q, fade, trialGeo);
            k1 = GetDerivativesAnalytic(state, a, Q, fade, outgoing, geo);
            currentDr = dot(geo.grad_r, k1.X.xyz);
        }
        lastDr = currentDr;
        if (turningCount > 2u) {
            if (debug == 1) { result.accumulated += vec4<f32>(0.3,0,0.3,1); result.status = TRACE_OPAQUE; }
            return result;
        }
        if (geo.r > inner && lastR < inner) { crossedInnerOutward = true; }
        if (geo.r > outer && lastR < outer) { crossedOuterOutward = true; }
        var preCeiling = min(cameraR-0.001, termination+0.2);
        if (crossedInnerOutward) { preCeiling = inner+0.2; }
        if (crossedOuterOutward) { preCeiling = outer+0.2; }
        var pruningCeiling = min(preCeiling,shellLimit);
        if (emitting || starR != 0.0) { pruningCeiling = min(pruningCeiling,settings.geometry.x); }
        if (starR != 0.0) { pruningCeiling = min(pruningCeiling,starR); }
        // Native iGrid disables near-horizon pruning so grid segments can emit.
        if (gridMode == 0 && !naked && geo.r < pruningCeiling && currentDr > 1e-4) {
            if (debug == 1) { result.accumulated += vec4<f32>(0,0,0.3,0); }
            result.status = TRACE_STOPPED; return result;
        }

        let rho = length(state.X.xz);
        let ringOffset = rho-abs(a);
        let distRing = sqrt(state.X.y*state.X.y+ringOffset*ringOffset);
        let potential = Q*Q/(geo.r2+0.01);
        let qDamping = 1.0/(1.0+potential);
        // At exact extremality inner=0.5: positive exterior limit is 1.
        var aDamping = 1.0;
        if (!naked && inner < 0.5) {
            aDamping = mix(max(abs(spin), 0.1), 1.0, clamp((geo.r-inner)/(0.5-inner), 0.0, 1.0));
        }
        let tolerance = 0.5*aDamping*qDamping;
        let stepGeo = distRing/(length(k1.X)+1e-9);
        let stepForce = length(state.P)/(length(k1.P)+1e-15);
        let dLambda = max(tolerance*min(stepGeo, stepForce), 1e-7);
        // Preserve the original ordering: k1 uses previous fade, remaining RK
        // stages receive refreshed fade; derivatives do not differentiate fade.
        fade = GravityFadeAt(state.X.xyz,boundary);
        if (!naked && spin != 0.0) {
            let factor = 0.5/spin;
            let dangerous = 10000.0*max(1.0, factor*factor*factor);
            if (RaiseIndex(state.P, geo).w > dangerous*quality) {
                if (debug == 1) { result.accumulated += vec4<f32>(0.3,0.3,0.2,0); }
                result.status = TRACE_STOPPED; return result;
            }
        }
        let previous = state;
        // Native ring boost uses the pre-step geometry, then updates lastR.
        let shellDeltaR = geo.r-lastR;
        let shellMeanR = 0.5*lastR+0.5*geo.r;
        let shellR = geo.r;
        lastR = geo.r;
        state = StepGeodesicRK4_Optimized(state, E, -dLambda/quality, a, Q, fade, 1.0, outgoing, k1);
        result.steps = count+1u;
        // Float32 guard: test exponent bits rather than relying on NaN math.
        if (any((bitcast<vec4<u32>>(state.X) & vec4<u32>(0x7f800000u)) == vec4<u32>(0x7f800000u)) ||
            any((bitcast<vec4<u32>>(state.P) & vec4<u32>(0x7f800000u)) == vec4<u32>(0x7f800000u))) {
            result.status = TRACE_INVALID; return result;
        }
        if (GetIntermediateSign(previous.X, state.X, 1.0, a) < 0.0) {
            result.status = TRACE_STOPPED; return result;
        }
        geo = ComputeGeometryScalars(state.X.xyz, a, Q, fade, 1.0, outgoing);
        result.nullError = abs(dot(state.P, RaiseIndex(state.P, geo)))/(dot(state.P, state.P)+1e-20);
        if (emitting) {
            let lastIngoing = ingoingState;
            ingoingState = state;
            if (outgoing) { ingoingState = transformKerrSchild_YSpin(state,1.0,CONST_M,a,Q,true); }
            let stepVector = ingoingState.X.xyz-lastIngoing.X.xyz;
            let stepLength = length(stepVector);
            let drdl = shellDeltaR/max(stepLength,1e-9);
            let rotfact = clamp(1.0+settings.effects.w*dot(-stepVector,
                vec3<f32>(ingoingState.X.z,0,-ingoingState.X.x))/stepLength/
                length(ingoingState.X.xz)*clamp(spin,-1.0,1.0),0.0,2.0);
            if (shellR < 1.6+pow(abs(spin),0.666666)) {
                thetaInShell += stepLength/shellMeanR/(1.0+1000.0*drdl*drdl)*rotfact*
                    clamp(11.0-10.0*(spin*spin+charge*charge),0.0,1.0);
            }
            result.accumulated = AccumulateRadiation(result.accumulated,state,previous,E,a,Q,
                outgoing,thetaInShell,&rayMarchPhase,thermodynamics,gridTime,renderTime,settings);
        }
        if (hasSurface) {
            result.accumulated = DenseStarColor(result.accumulated,state,previous,a,Q,outgoing,
                1.0,-dLambda/quality,gridTime,debug,star);
        }
        // Original post-step horizon checks also stop inward motion between
        // horizons and rays returning after escaping an inner starting region.
        let horizonStop = !naked && ((lastR > outer && geo.r < outer) || (lastR > inner && geo.r < inner) ||
            (lastR < outer && lastR > inner && geo.r < outer && geo.r > inner && geo.r < lastR));
        // Native still shades this final segment after marking the horizon stop.
        if (gridMode == 1) {
            result.accumulated = GridColor(result.accumulated,state.X,previous.X,state.P,E,a,Q,outgoing,1.0,gridTime);
        } else if (gridMode == 2) {
            result.accumulated = GridColorSimple(result.accumulated,state.X,previous.X,state.P,previous.P,a,Q,outgoing,1.0,-dLambda/quality,!horizonStop,gridTime);
        }
        if (result.accumulated.a > 0.99) { result.steps = count; result.status = TRACE_OPAQUE; return result; }
        if (horizonStop) { return result; }
        if (!naked && termination != -1.0 && geo.r < termination) { return result; }
    }
    return result;
}

fn TraceEmissionRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32, mode: i32, velocity: vec3<f32>, frame: ObserverTetrad, gridMode: i32, gridTime: f32, debug: i32, settings: RadiationSettings, massSolar: f32, rayUv: vec2<f32>, renderTime: f32) -> TraceResult {
    return TraceSceneRay(origin,direction,spin,charge,quality,mode,velocity,frame,gridMode,gridTime,debug,
        settings,massSolar,rayUv,renderTime,DenseStarSettings());
}

fn TraceDiagnosticRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32, mode: i32, velocity: vec3<f32>, frame: ObserverTetrad, gridMode: i32, gridTime: f32, debug: i32) -> TraceResult {
    return TraceEmissionRay(origin,direction,spin,charge,quality,mode,velocity,frame,
        gridMode,gridTime,debug,RadiationSettings(),14900000.0,vec2<f32>(0),0.0);
}

// Preserve the static helper used by existing physical probes.
fn TraceRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32) -> TraceResult {
    return TraceObserverRay(origin,direction,spin,charge,quality,0,vec3<f32>(0));
}

fn TraceObserverRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32, mode: i32, velocity: vec3<f32>) -> TraceResult {
    return TraceTetradRay(origin,direction,spin,charge,quality,mode,velocity,ObserverTetrad());
}

// Grid-off entry preserved for existing physics callers.
fn TraceTetradRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32, mode: i32, velocity: vec3<f32>, frame: ObserverTetrad) -> TraceResult {
    return TraceGridRay(origin,direction,spin,charge,quality,mode,velocity,frame,0,0.0);
}

fn TraceGridRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32, mode: i32, velocity: vec3<f32>, frame: ObserverTetrad, gridMode: i32, gridTime: f32) -> TraceResult {
    return TraceDiagnosticRay(origin,direction,spin,charge,quality,mode,velocity,frame,gridMode,gridTime,0);
}
fn PackDiagnostic(ray: TraceResult, debug: i32, maxStep: f32, maximumShift: f32) -> TraceResult {
    var result = ray;
    if (ray.status == TRACE_INVALID) { return result; }
    if (debug == 3) { result.accumulated = DebugStepColor(ray.steps,maxStep); result.direction = vec3<f32>(0); result.status = TRACE_OPAQUE; }
    if (debug == 4 && ray.status == TRACE_ESCAPED) {
        let shift = clamp(1.0/max(1e-14,abs(ray.energy)),1.0/maximumShift,maximumShift);
        result.accumulated = DebugShiftColor(shift,maximumShift); result.status = TRACE_OPAQUE;
    }
    return result;
}
