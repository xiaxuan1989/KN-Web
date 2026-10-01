// Native Whitehole=1 maximum extension. The default TraceSceneRay is kept
// separately so switching extension off restores the existing positive-r path.
struct ExtendedTraceResult { ray: TraceResult, sign: f32, universeOffset: i32 };
fn IsSkyStatus(status: u32) -> bool { return status == 1u || status == 2u || status == 4u || status == 5u; }
fn TraceExtendedMaxStep(spin: f32, charge: f32) -> f32 {
    let a = spin*CONST_M;
    let Q = charge*CONST_M;
    return select(1145.0,450.0,0.25-a*a-Q*Q < 0.0);
}
fn FinalizeExtended(input: TraceResult, sign: f32, offset: i32, naked: bool) -> ExtendedTraceResult {
    var ray = input;
    if (ray.status == TRACE_ESCAPED) {
        ray.status = select(2u,1u,sign > 0.0);
        if (!naked && offset > 0) { ray.status += 3u*u32(offset); }
    }
    return ExtendedTraceResult(ray,sign,offset);
}
fn TraceExtendedSceneRay(origin: vec3<f32>, direction: vec3<f32>, spin: f32, charge: f32, quality: f32, mode: i32, velocity: vec3<f32>, frame: ObserverTetrad, gridMode: i32, gridTime: f32, debug: i32, settingsInput: RadiationSettings, massSolar: f32, rayUv: vec2<f32>, renderTime: f32, starInput: DenseStarSettings, extension: vec4<f32>) -> ExtendedTraceResult {
    var settings = settingsInput;
    settings.control.z = 1.0;
    var star = starInput;
    star.control.z = 1.0;
    let initialSign = extension.y;
    var currentSign = initialSign*select(1.0,-1.0,massSolar < 0.0);
    var universeOffset = 0;
    var result = TraceResult(vec3<f32>(0.0), TRACE_STOPPED, 0u, 0.0, vec4<f32>(0), 1.0);
    let starR = select(0.0,DenseStarRadius(star),RADIATION_ENABLED);
    let emitting = RADIATION_ENABLED && (HasDisk(settings) || HasJet(settings));
    var boundary = max(TRACE_BOUNDARY,spin*2.0);
    boundary = max(boundary,settings.geometry.y+1.0);
    let a = spin*CONST_M;
    let Q = charge*CONST_M;
    let discriminant = 0.25-a*a-Q*Q;
    let naked = discriminant < 0.0;
    let outer = 0.5+sqrt(max(0.0,discriminant));
    let inner = 0.5-sqrt(max(0.0,discriminant));
    let hasSurface = starR != 0.0 && (naked || starR > outer);
    if (!naked && KerrSchildRadius(origin,a,currentSign) < inner) { universeOffset = 1; }
    var state = State(vec4<f32>(origin, 0.0), vec4<f32>(0.0));
    if (length(origin) > boundary) {
        let b = dot(origin, direction);
        let c = dot(origin, origin)-(boundary-1.0)*(boundary-1.0);
        let delta = b*b-c;
        if (delta < 0.0) { return FinalizeExtended(TraceResult(direction,TRACE_ESCAPED,0u,0.0,vec4<f32>(0),1.0),currentSign,universeOffset,naked); }
        let tEnter = -b-sqrt(delta);
        if (tEnter > 0.0) { state.X = vec4<f32>(origin+direction*tEnter, -tEnter); }
        else if (-b+sqrt(delta) <= 0.0) { return FinalizeExtended(TraceResult(direction,TRACE_ESCAPED,0u,0.0,vec4<f32>(0),1.0),currentSign,universeOffset,naked); }
    }
    var fade = GravityFadeAt(state.X.xyz,boundary);
    var outgoing = mode == -1 && frame.outgoing;
    var geo = ComputeGeometryScalars(state.X.xyz, a, Q, fade, currentSign, outgoing);
    let cameraR = geo.r;
    if (!naked && cameraR < inner) { universeOffset = 1; }
    if (abs(cameraR) < 1e-6) { result.status = TRACE_INVALID; return FinalizeExtended(result,currentSign,universeOffset,naked); }
    if (mode == -1) {
        state.P = GetTetradMomentum(direction,state.X,a,Q,fade,initialSign,outgoing,frame.outgoing,frame.U,frame.e1,frame.e2,frame.e3);
    } else { state.P = GetObserverMomentum(direction,state.X,a,Q,fade,initialSign,outgoing,mode,velocity); }
    if (all(state.P == vec4<f32>(114514.0))) {
        outgoing = true;
        if (mode == -1) {
            state.P = GetTetradMomentum(direction,state.X,a,Q,fade,initialSign,true,frame.outgoing,frame.U,frame.e1,frame.e2,frame.e3);
        } else { state.P = GetObserverMomentum(direction,state.X,a,Q,fade,initialSign,true,mode,velocity); }
        geo = ComputeGeometryScalars(state.X.xyz,a,Q,fade,currentSign,true);
    }
    result.energy = -state.P.w;
    if (all(state.P == vec4<f32>(114514.0))) { result.status = TRACE_OPAQUE; result.accumulated.a = 1.0; return FinalizeExtended(result,currentSign,universeOffset,naked); }
    if (debug == 2) {
        result.status = TRACE_OPAQUE;
        // Native diagnostic returns before conservation energy is packaged.
        result.energy = 1.0;
        result.accumulated = vec4<f32>(DebugInitialMomentum(state.P,state.X,mode,initialSign,a,Q,fade,outgoing,velocity),1);
        return FinalizeExtended(result,currentSign,universeOffset,naked);
    }
    // Native static-limit test: only mode 0 is excluded from the ergoregion.
    if (mode == 0 && currentSign > 0.0) {
        let cosThetaSq = state.X.y*state.X.y/(cameraR*cameraR+1e-20);
        let sl = 0.25-Q*Q-a*a*cosThetaSq;
        if (sl >= 0.0 && cameraR < 0.5+sqrt(sl) && cameraR > 0.5-sqrt(sl)) {
            result.status = TRACE_OPAQUE; result.accumulated.a = 1.0; return FinalizeExtended(result,currentSign,universeOffset,naked);
        }
    }
    let E = -state.P.w;
    result.energy = E;
    let shellLimit = ProgradePhotonRadius(spin, Q)-0.001;
    let originalLimit = u32(TraceExtendedMaxStep(spin,charge)*quality*(1.0+0.3*quality));
    var rayMarchPhase = 0.0;
    var thermodynamics = vec2<f32>(0);
    var thetaInShell = 0.0;
    var ingoingState = state;
    if (emitting) {
        rayMarchPhase = RandomStep(rayUv,renderTime);
        thermodynamics = DiskThermodynamics(massSolar,spin,settings.material.x,settings.material.y);
        if (outgoing) { ingoingState = transformKerrSchild_YSpin(state,currentSign,CONST_M,a,Q,true); }
    }
    var lastDr = 0.0;
    var lastR = cameraR;
    var turningCount = 0u;

    // Keep the original strict Count > budget check below, after escape/horizon.
    // Thus budget+1 RK steps are allowed; there is no additional Web step cap.
    for (var count = 0u; ; count++) {
        result.steps = count;
        let distance = length(state.X.xyz);
        if (distance > boundary) {
            var ingoingState = state;
            if (outgoing) { ingoingState = transformKerrSchild_YSpin(state, currentSign, CONST_M, a, Q, true); }
            // Original far-boundary escape direction is -P_cov in ingoing chart.
            result.direction = normalize(-ingoingState.P.xyz);
            result.status = TRACE_ESCAPED;
            return FinalizeExtended(result,currentSign,universeOffset,naked);
        }
        if (count > originalLimit) {
            if (debug == 1) { result.accumulated += vec4<f32>(0,0.3,0,0); }
            if (naked && turningCount <= 2u) {
                var ingoing = state;
                if (outgoing) { ingoing = transformKerrSchild_YSpin(state,currentSign,CONST_M,a,Q,true); }
                let skyGeo = ComputeGeometryScalars(ingoing.X.xyz,a,Q,fade,currentSign,false);
                result.direction = normalize(-RaiseIndex(ingoing.P,skyGeo).xyz);
                result.status = TRACE_ESCAPED;
            }
            return FinalizeExtended(result,currentSign,universeOffset,naked);
        }

        var k1 = GetDerivativesAnalytic(state, a, Q, fade, outgoing, geo);
        geo = ComputeGeometryGradients(state.X.xyz, a, Q, fade, geo);
        var currentDr = dot(geo.grad_r, k1.X.xyz);
        if (count > 0u && currentDr*lastDr < 0.0) { turningCount++; }

        let P_contra = RaiseIndex(state.P, geo);
        let currentSum = dot(abs(P_contra), vec4<f32>(1.0));
        let trial = transformKerrSchild_YSpin(state, currentSign, CONST_M, a, Q, outgoing);
        let trialGeo = ComputeGeometryScalars(trial.X.xyz, a, Q, fade, currentSign, !outgoing);
        let trialSum = dot(abs(RaiseIndex(trial.P, trialGeo)), vec4<f32>(1.0));
        if (currentSum > 2.0*trialSum) {
            state = trial;
            outgoing = !outgoing;
            geo = ComputeGeometryGradients(state.X.xyz, a, Q, fade, trialGeo);
            k1 = GetDerivativesAnalytic(state, a, Q, fade, outgoing, geo);
            currentDr = dot(geo.grad_r, k1.X.xyz);
        }
        lastDr = currentDr;
        if (!naked && geo.r < inner && lastR > inner) { universeOffset++; }
        if ((naked && turningCount > 4u) || (!naked && (universeOffset > 1 || turningCount > 8u))) {
            if (debug == 1) { result.accumulated += vec4<f32>(0.3,0,0.3,1); result.status = TRACE_OPAQUE; }
            return FinalizeExtended(result,currentSign,universeOffset,naked);
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
        if (!naked && currentSign > 0.0 && spin != 0.0) {
            let factor = 0.5/spin;
            let dangerous = 10000.0*max(1.0, factor*factor*factor);
            if (RaiseIndex(state.P, geo).w > dangerous*quality) {
                if (debug == 1) { result.accumulated += vec4<f32>(0.3,0.3,0.2,0); }
                result.status = TRACE_STOPPED; return FinalizeExtended(result,currentSign,universeOffset,naked);
            }
        }
        let previous = state;
        // Native ring boost uses the pre-step geometry, then updates lastR.
        let shellDeltaR = geo.r-lastR;
        let shellMeanR = 0.5*lastR+0.5*geo.r;
        let shellR = geo.r;
        lastR = geo.r;
        state = StepGeodesicRK4_Optimized(state, E, -dLambda/quality, a, Q, fade, currentSign, outgoing, k1);
        result.steps = count+1u;
        // Float32 guard: test exponent bits rather than relying on NaN math.
        if (any((bitcast<vec4<u32>>(state.X) & vec4<u32>(0x7f800000u)) == vec4<u32>(0x7f800000u)) ||
            any((bitcast<vec4<u32>>(state.P) & vec4<u32>(0x7f800000u)) == vec4<u32>(0x7f800000u))) {
            result.status = TRACE_INVALID; return FinalizeExtended(result,currentSign,universeOffset,naked);
        }
        currentSign = GetIntermediateSign(previous.X,state.X,currentSign,a);
        geo = ComputeGeometryScalars(state.X.xyz, a, Q, fade, currentSign, outgoing);
        result.nullError = abs(dot(state.P, RaiseIndex(state.P, geo)))/(dot(state.P, state.P)+1e-20);
        if (emitting) {
            let lastIngoing = ingoingState;
            ingoingState = state;
            if (outgoing) { ingoingState = transformKerrSchild_YSpin(state,GetIntermediateSign(previous.X,state.X,currentSign,a),CONST_M,a,Q,true); }
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
            if (currentSign > 0.0 && massSolar > 0.0 && (33+i32(extension.z)-universeOffset)%3 == 0) {
            result.accumulated = AccumulateRadiation(result.accumulated,state,previous,E,a,Q,
                outgoing,thetaInShell,&rayMarchPhase,thermodynamics,gridTime,renderTime,settings);
            }
        }
        if (hasSurface && (33+i32(extension.z)-universeOffset)%3 == 0) {
            result.accumulated = DenseStarColor(result.accumulated,state,previous,a,Q,outgoing,
                currentSign,-dLambda/quality,gridTime,debug,star);
        }
        if (gridMode == 1) {
            result.accumulated = GridColorExtended(result.accumulated,state.X,previous.X,state.P,E,a,Q,outgoing,currentSign,gridTime,true);
        } else if (gridMode == 2) {
            result.accumulated = GridColorSimpleExtended(result.accumulated,state.X,previous.X,state.P,previous.P,a,Q,outgoing,currentSign,-dLambda/quality,true,gridTime,true);
        }
        if (result.accumulated.a > 0.99) { result.steps = count; result.status = TRACE_OPAQUE; return FinalizeExtended(result,currentSign,universeOffset,naked); }
    }
    return FinalizeExtended(result,currentSign,universeOffset,naked);
}
