// Exterior/static/no-disk slice of NPGS TraceRay. See docs/phase2-port.md
// for host safety limits and deliberately deferred features.
const TRACE_BOUNDARY: f32 = 501.0;
const MAX_TRACE_STEPS: u32 = 1024u;
const TRACE_CAPTURED: u32 = 0u;
const TRACE_ESCAPED: u32 = 1u;
const TRACE_UNRESOLVED: u32 = 2u;
const TRACE_INVALID: u32 = 3u;

struct TraceResult {
    direction: vec3<f32>, status: u32,
    steps: u32, nullError: f32,
    energy: f32, // -P_cov.w, normalized observer photon energy is 1
};

fn GravityFadeAt(position: vec3<f32>) -> f32 {
    let x = clamp(1.0 - (length(position)-100.0)/(TRACE_BOUNDARY-100.0), 0.0, 1.0);
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

fn TraceRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32) -> TraceResult {
    var result = TraceResult(vec3<f32>(0.0), TRACE_UNRESOLVED, 0u, 0.0, 1.0);
    let a = spin*CONST_M;
    let Q = charge*CONST_M;
    let discriminant = 0.25-a*a-Q*Q;
    // Phase 2 intentionally exposes only the positive-r exterior of a BH.
    if (discriminant < 0.0) { result.status = TRACE_INVALID; return result; }
    let outer = 0.5+sqrt(discriminant);
    let inner = 0.5-sqrt(discriminant);
    var state = State(vec4<f32>(origin, 0.0), vec4<f32>(0.0));
    if (length(origin) > TRACE_BOUNDARY) {
        let b = dot(origin, direction);
        let c = dot(origin, origin)-(TRACE_BOUNDARY-1.0)*(TRACE_BOUNDARY-1.0);
        let delta = b*b-c;
        if (delta < 0.0) { return TraceResult(direction, TRACE_ESCAPED, 0u, 0.0, 1.0); }
        let tEnter = -b-sqrt(delta);
        if (tEnter > 0.0) { state.X = vec4<f32>(origin+direction*tEnter, -tEnter); }
        else if (-b+sqrt(delta) <= 0.0) { return TraceResult(direction, TRACE_ESCAPED, 0u, 0.0, 1.0); }
    }
    var fade = GravityFadeAt(state.X.xyz);
    var outgoing = false;
    var geo = ComputeGeometryScalars(state.X.xyz, a, Q, fade, 1.0, outgoing);
    let cameraR = geo.r;
    // Static U must be timelike. No clamping an invalid observer into existence.
    if (cameraR <= outer || geo.f >= 1.0 || cameraR < 1e-6) {
        result.status = TRACE_INVALID; return result;
    }
    state.P = GetInitialMomentum(direction, state.X, a, Q, fade, 1.0, outgoing);
    let E = -state.P.w;
    result.energy = E;
    let shellLimit = ProgradePhotonRadius(spin, Q)-0.001;
    let pruningCeiling = min(min(cameraR-0.001, outer+0.2), shellLimit);
    let extremality = 1.0-spin*spin-charge*charge;
    let maxStep = 150.0 + 300.0/(1.0+1000.0*extremality*extremality);
    let originalLimit = u32(maxStep*quality*(1.0+0.3*quality));
    var lastDr = 0.0;
    var turningCount = 0u;

    for (var count = 0u; count < MAX_TRACE_STEPS; count++) {
        result.steps = count;
        let distance = length(state.X.xyz);
        if (distance > TRACE_BOUNDARY) {
            var ingoingState = state;
            if (outgoing) { ingoingState = transformKerrSchild_YSpin(state, 1.0, CONST_M, a, Q, true); }
            // Original far-boundary escape direction is -P_cov in ingoing chart.
            result.direction = normalize(-ingoingState.P.xyz);
            result.status = TRACE_ESCAPED;
            return result;
        }
        if (geo.r < outer) { result.status = TRACE_CAPTURED; return result; }
        if (count > originalLimit) { return result; }

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
        if (turningCount > 2u) { return result; }
        if (geo.r < pruningCeiling && currentDr > 1e-4) {
            result.status = TRACE_CAPTURED; return result;
        }

        let rho = length(state.X.xz);
        let ringOffset = rho-abs(a);
        let distRing = sqrt(state.X.y*state.X.y+ringOffset*ringOffset);
        let potential = Q*Q/(geo.r2+0.01);
        let qDamping = 1.0/(1.0+potential);
        // At exact extremality inner=0.5: positive exterior limit is 1.
        var aDamping = 1.0;
        if (inner < 0.5) {
            aDamping = mix(max(abs(spin), 0.1), 1.0, clamp((geo.r-inner)/(0.5-inner), 0.0, 1.0));
        }
        let tolerance = 0.5*aDamping*qDamping;
        let stepGeo = distRing/(length(k1.X)+1e-9);
        let stepForce = length(state.P)/(length(k1.P)+1e-15);
        let dLambda = max(tolerance*min(stepGeo, stepForce), 1e-7);
        // Preserve the original ordering: k1 uses previous fade, remaining RK
        // stages receive refreshed fade; derivatives do not differentiate fade.
        fade = GravityFadeAt(state.X.xyz);
        if (spin != 0.0) {
            let factor = 0.5/spin;
            let dangerous = 10000.0*max(1.0, factor*factor*factor);
            if (RaiseIndex(state.P, geo).w > dangerous*quality) {
                result.status = TRACE_CAPTURED; return result;
            }
        }
        let previous = state;
        state = StepGeodesicRK4_Optimized(state, E, -dLambda/quality, a, Q, fade, 1.0, outgoing, k1);
        // Float32 guard: test exponent bits rather than relying on NaN math.
        if (any((bitcast<vec4<u32>>(state.X) & vec4<u32>(0x7f800000u)) == vec4<u32>(0x7f800000u)) ||
            any((bitcast<vec4<u32>>(state.P) & vec4<u32>(0x7f800000u)) == vec4<u32>(0x7f800000u))) {
            result.status = TRACE_INVALID; return result;
        }
        if (GetIntermediateSign(previous.X, state.X, 1.0, a) < 0.0) {
            result.status = TRACE_CAPTURED; return result;
        }
        geo = ComputeGeometryScalars(state.X.xyz, a, Q, fade, 1.0, outgoing);
        result.nullError = abs(dot(state.P, RaiseIndex(state.P, geo)))/(dot(state.P, state.P)+1e-20);
        if (geo.r < outer) { result.status = TRACE_CAPTURED; return result; }
    }
    result.steps = MAX_TRACE_STEPS;
    return result;
}
