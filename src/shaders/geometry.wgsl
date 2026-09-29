// Port of BlackHole_common.glsl, sections 4–5.
// Coordinates (x,y,z,t), signature (+++-), spin axis Y, distances in Rs.
const CONST_M: f32 = 0.5;

struct KerrGeometry {
    r: f32, r2: f32, a2: f32, f: f32,
    grad_r: vec3<f32>, grad_f: vec3<f32>,
    l_up: vec4<f32>, l_down: vec4<f32>,
    inv_r2_a2: f32, inv_den_f: f32, num_f: f32,
};
struct State { X: vec4<f32>, P: vec4<f32> };

fn KerrSchildRadius(p: vec3<f32>, PhysicalSpinA: f32, r_sign: f32) -> f32 {
    if (PhysicalSpinA == 0.0) { return r_sign * length(p); }
    let a2 = PhysicalSpinA * PhysicalSpinA;
    let rho2 = dot(p.xz, p.xz);
    let y2 = p.y * p.y;
    let b = rho2 + y2 - a2;
    let det = sqrt(b * b + 4.0 * a2 * y2);
    var r2: f32;
    if (b >= 0.0) { r2 = 0.5 * (b + det); }
    else { r2 = (2.0 * a2 * y2) / max(1e-20, det - b); }
    return r_sign * sqrt(r2);
}

fn ComputeGeometryScalars(X: vec3<f32>, a: f32, Q: f32, fade: f32, r_sign: f32, outgoing: bool) -> KerrGeometry {
    var geo: KerrGeometry;
    geo.a2 = a * a;
    let dirSign = select(1.0, -1.0, outgoing);
    if (a == 0.0) {
        geo.r = r_sign * length(X);
        geo.r2 = geo.r * geo.r;
        let inv_r = 1.0 / geo.r;
        let inv_r2 = inv_r * inv_r;
        geo.l_up = vec4<f32>(dirSign * X * inv_r, -1.0);
        geo.l_down = vec4<f32>(dirSign * X * inv_r, 1.0);
        geo.num_f = 2.0 * CONST_M * geo.r - Q * Q;
        geo.f = (2.0 * CONST_M * inv_r - Q * Q * inv_r2) * fade;
        geo.inv_r2_a2 = inv_r2;
        geo.inv_den_f = inv_r2 * inv_r2;
        return geo;
    }
    geo.r = KerrSchildRadius(X, a, r_sign);
    geo.r2 = geo.r * geo.r;
    let r3 = geo.r2 * geo.r;
    let z2 = X.y * X.y;
    geo.inv_r2_a2 = 1.0 / (geo.r2 + geo.a2);
    let lx = (dirSign * geo.r * X.x - a * X.z) * geo.inv_r2_a2;
    let ly = dirSign * X.y / geo.r;
    let lz = (dirSign * geo.r * X.z + a * X.x) * geo.inv_r2_a2;
    geo.l_up = vec4<f32>(lx, ly, lz, -1.0);
    geo.l_down = vec4<f32>(lx, ly, lz, 1.0);
    geo.num_f = 2.0 * CONST_M * r3 - Q * Q * geo.r2;
    let den_f = geo.r2 * geo.r2 + geo.a2 * z2;
    geo.inv_den_f = 1.0 / max(1e-20, den_f);
    geo.f = geo.num_f * geo.inv_den_f * fade;
    return geo;
}

fn ComputeGeometryGradients(X: vec3<f32>, a: f32, Q: f32, fade: f32, inputGeo: KerrGeometry) -> KerrGeometry {
    var geo = inputGeo;
    let inv_r = 1.0 / geo.r;
    if (a == 0.0) {
        let inv_r2 = inv_r * inv_r;
        geo.grad_r = X * inv_r;
        let df_dr = (-2.0 * CONST_M + 2.0 * Q * Q * inv_r) * inv_r2 * fade;
        geo.grad_f = df_dr * geo.grad_r;
        return geo;
    }
    let inv_denom_grad = geo.r * geo.inv_den_f;
    geo.grad_r = vec3<f32>(X.x * geo.r2, X.y * (geo.r2 + geo.a2), X.z * geo.r2) * inv_denom_grad;
    let z2 = X.y * X.y;
    let term_M = -2.0 * CONST_M * geo.r2 * geo.r2 * geo.r;
    let term_Q = 2.0 * Q * Q * geo.r2 * geo.r2;
    let term_Ma = 6.0 * CONST_M * geo.a2 * geo.r * z2;
    let term_Qa = -2.0 * Q * Q * geo.a2 * z2;
    let df_dr_num_reduced = term_M + term_Q + term_Ma + term_Qa;
    let df_dr = (geo.r * df_dr_num_reduced) * (geo.inv_den_f * geo.inv_den_f);
    let df_dy = -(geo.num_f * 2.0 * geo.a2 * X.y) * (geo.inv_den_f * geo.inv_den_f);
    geo.grad_f = df_dr * geo.grad_r;
    geo.grad_f.y += df_dy;
    geo.grad_f *= fade;
    return geo;
}

fn RaiseIndex(P: vec4<f32>, geo: KerrGeometry) -> vec4<f32> {
    return vec4<f32>(P.xyz, -P.w) - geo.f * dot(geo.l_up, P) * geo.l_up;
}
fn LowerIndex(P: vec4<f32>, geo: KerrGeometry) -> vec4<f32> {
    return vec4<f32>(P.xyz, -P.w) + geo.f * dot(geo.l_down, P) * geo.l_down;
}

// Original observer modes: 0 static, 1 infalling, 2 coordinate velocity,
// 3 reversed coordinate velocity. A non-timelike velocity returns the native sentinel.
fn GetObserverMomentum(RayDir: vec3<f32>, X: vec4<f32>, a: f32, Q: f32, fade: f32, r_sign: f32, outgoing: bool, mode: i32, velocity: vec3<f32>) -> vec4<f32> {
    let geo = ComputeGeometryScalars(X.xyz, a, Q, fade, r_sign, outgoing);
    let g_tt = -1.0 + geo.f;
    let time_comp = 1.0 / sqrt(max(1e-9, -g_tt));
    var U_up = vec4<f32>(0.0, 0.0, 0.0, time_comp);
    if (mode == 1) {
        let r = geo.r; let r2 = geo.r2; let a2 = geo.a2;
        let rho2 = r2+a2*X.y*X.y/(r2+1e-9);
        let massCharge = 2.0*CONST_M*r-Q*Q;
        let xi = sqrt(max(0.0,massCharge*(r2+a2)));
        let denomPhi = rho2*(massCharge+xi);
        var uPhi = 0.0;
        if (abs(denomPhi) > 1e-9) { uPhi = -massCharge*a/denomPhi; }
        let uR = -xi/max(1e-9,rho2);
        let invR2A2 = 1.0/(r2+a2);
        let spatial = vec3<f32>((r*X.x-a*X.z)*invR2A2*uR+X.z*uPhi,
            (X.y/r)*uR,(r*X.z+a*X.x)*invR2A2*uR-X.x*uPhi);
        let lDot = dot(geo.l_down.xyz,spatial);
        let A = -1.0+geo.f; let B = 2.0*geo.f*lDot;
        let C = dot(spatial,spatial)+geo.f*lDot*lDot+1.0;
        let sqrtDet = sqrt(max(0.0,B*B-4.0*A*C));
        var ut: f32;
        if (abs(A) < 1e-7) { ut = -C/max(1e-19,B); }
        else if (B < 0.0) { ut = 2.0*C/(-B+sqrtDet); }
        else { ut = (-B-sqrtDet)/(2.0*A); }
        U_up = mix(U_up,vec4<f32>(spatial,ut),fade);
    } else if (mode == 2 || mode == 3) {
        var v = select(velocity,-velocity,mode == 3);
        if (any((bitcast<vec3<u32>>(v) & vec3<u32>(0x7f800000u)) == vec3<u32>(0x7f800000u))) { v = vec3<f32>(0); }
        let V_up = vec4<f32>(v,1);
        let V_sq = dot(V_up,LowerIndex(V_up,geo));
        if (V_sq < 0.0) { U_up = V_up*inverseSqrt(-V_sq); }
        else { return vec4<f32>(114514.0); }
    }
    let U_down = LowerIndex(U_up, geo);
    let m_r = -normalize(X.xyz);
    var WorldUp = vec3<f32>(0.0, 1.0, 0.0);
    if (abs(dot(m_r, WorldUp)) > 0.999) { WorldUp = vec3<f32>(1.0, 0.0, 0.0); }
    let m_phi = normalize(cross(WorldUp, m_r));
    let m_theta = cross(m_phi, m_r);
    let k_r = dot(RayDir, m_r);
    let k_theta = dot(RayDir, m_theta);
    let k_phi = dot(RayDir, m_phi);
    var e1 = vec4<f32>(m_r, 0.0);
    e1 += dot(e1, U_down) * U_up;
    var e1_d = LowerIndex(e1, geo);
    let n1 = sqrt(max(1e-9, dot(e1, e1_d)));
    e1 /= n1; e1_d /= n1;
    var e2 = vec4<f32>(m_theta, 0.0);
    e2 += dot(e2, U_down) * U_up;
    e2 -= dot(e2, e1_d) * e1;
    var e2_d = LowerIndex(e2, geo);
    let n2 = sqrt(max(1e-9, dot(e2, e2_d)));
    e2 /= n2; e2_d /= n2;
    var e3 = vec4<f32>(m_phi, 0.0);
    e3 += dot(e3, U_down) * U_up;
    e3 -= dot(e3, e1_d) * e1;
    e3 -= dot(e3, e2_d) * e2;
    let e3_d = LowerIndex(e3, geo);
    let n3 = sqrt(max(1e-9, dot(e3, e3_d)));
    e3 /= n3;
    let P_up = U_up - (k_r * e1 + k_theta * e2 + k_phi * e3);
    return LowerIndex(P_up, geo);
}

fn GetInitialMomentum(RayDir: vec3<f32>, X: vec4<f32>, a: f32, Q: f32, fade: f32, r_sign: f32, outgoing: bool) -> vec4<f32> {
    return GetObserverMomentum(RayDir,X,a,Q,fade,r_sign,outgoing,0,vec3<f32>(0));
}
// Native mode -1 consumes an externally transported tetrad in its own chart.
// This kernel does not invent a tetrad or advance the observer's worldline.
fn GetTetradMomentum(RayDir: vec3<f32>, X: vec4<f32>, a: f32, Q: f32, fade: f32, r_sign: f32,
    outgoing: bool, cameraOutgoing: bool, U: vec4<f32>, e1: vec4<f32>, e2: vec4<f32>, e3: vec4<f32>) -> vec4<f32> {
    let v = normalize(RayDir);
    let up = U+v.x*e1+v.y*e2+v.z*e3;
    let geo = ComputeGeometryScalars(X.xyz,a,Q,fade,r_sign,cameraOutgoing);
    var cov = LowerIndex(up,geo);
    if (outgoing != cameraOutgoing) {
        cov = transformKerrSchild_YSpin(State(X,cov),r_sign,CONST_M,a,Q,outgoing).P;
    }
    return cov;
}

fn GetDerivativesAnalytic(S: State, a: f32, Q: f32, fade: f32, outgoing: bool, inputGeo: KerrGeometry) -> State {
    let geo = ComputeGeometryGradients(S.X.xyz, a, Q, fade, inputGeo);
    let l_dot_P = dot(geo.l_up.xyz, S.P.xyz) + geo.l_up.w * S.P.w;
    let dX = vec4<f32>(S.P.xyz, -S.P.w) - geo.f * l_dot_P * geo.l_up;
    let grad_A = (-2.0 * geo.r * geo.inv_r2_a2) * geo.inv_r2_a2 * geo.grad_r;
    let dirSign = select(1.0, -1.0, outgoing);
    let rx_az = dirSign * geo.r * S.X.x - a * S.X.z;
    let rz_ax = dirSign * geo.r * S.X.z + a * S.X.x;
    var d_num_lx = dirSign * S.X.x * geo.grad_r;
    d_num_lx.x += dirSign * geo.r;
    d_num_lx.z -= a;
    let grad_lx = geo.inv_r2_a2 * d_num_lx + rx_az * grad_A;
    let grad_ly = dirSign * (geo.r * geo.inv_den_f) * vec3<f32>(-S.X.x * S.X.y, geo.r2 - S.X.y * S.X.y, -S.X.z * S.X.y);
    var d_num_lz = dirSign * S.X.z * geo.grad_r;
    d_num_lz.z += dirSign * geo.r;
    d_num_lz.x += a;
    let grad_lz = geo.inv_r2_a2 * d_num_lz + rz_ax * grad_A;
    let P_dot_grad_l = S.P.x * grad_lx + S.P.y * grad_ly + S.P.z * grad_lz;
    let force = 0.5 * ((l_dot_P * l_dot_P) * geo.grad_f + (2.0 * geo.f * l_dot_P) * P_dot_grad_l);
    return State(dX, vec4<f32>(force, 0.0));
}

fn ApplyHamiltonianCorrection(inputP: vec4<f32>, X: vec4<f32>, E: f32, a: f32, Q: f32, fade: f32, r_sign: f32, outgoing: bool) -> vec4<f32> {
    var P = vec4<f32>(inputP.xyz, -E);
    let geo = ComputeGeometryScalars(X.xyz, a, Q, fade, r_sign, outgoing);
    let L_dot_p_s = dot(geo.l_up.xyz, P.xyz);
    let Pt = P.w;
    let Coeff_A = dot(P.xyz, P.xyz) - geo.f * L_dot_p_s * L_dot_p_s;
    let Coeff_B = 2.0 * geo.f * L_dot_p_s * Pt;
    let Coeff_C = -Pt * Pt * (1.0 + geo.f);
    let disc = Coeff_B * Coeff_B - 4.0 * Coeff_A * Coeff_C;
    if (disc >= 0.0) {
        let sqrtDisc = sqrt(disc);
        let denom = 2.0 * Coeff_A;
        if (abs(denom) > 1e-9) {
            let k1 = (-Coeff_B + sqrtDisc) / denom;
            let k2 = (-Coeff_B - sqrtDisc) / denom;
            let k = select(k2, k1, abs(k1 - 1.0) < abs(k2 - 1.0));
            P = vec4<f32>(P.xyz * mix(k, 1.0, clamp(abs(k - 1.0) / 0.1 - 1.0, 0.0, 1.0)), P.w);
        }
    }
    return P;
}

fn GetIntermediateSign(StartX: vec4<f32>, CurrentX: vec4<f32>, CurrentSign: f32, a: f32) -> f32 {
    if (StartX.y * CurrentX.y < 0.0) {
        let t = StartX.y / (StartX.y - CurrentX.y);
        if (length(mix(StartX.xz, CurrentX.xz, t)) < abs(a)) { return -CurrentSign; }
    }
    return CurrentSign;
}

fn StepGeodesicRK4_Optimized(s0: State, E: f32, dt: f32, a: f32, Q: f32, fade: f32, r_sign: f32, outgoing: bool, k1: State) -> State {
    let s1 = State(s0.X + 0.5 * dt * k1.X, s0.P + 0.5 * dt * k1.P);
    let sign1 = GetIntermediateSign(s0.X, s1.X, r_sign, a);
    let geo1 = ComputeGeometryScalars(s1.X.xyz, a, Q, fade, sign1, outgoing);
    let k2 = GetDerivativesAnalytic(s1, a, Q, fade, outgoing, geo1);
    let s2 = State(s0.X + 0.5 * dt * k2.X, s0.P + 0.5 * dt * k2.P);
    let sign2 = GetIntermediateSign(s0.X, s2.X, r_sign, a);
    let geo2 = ComputeGeometryScalars(s2.X.xyz, a, Q, fade, sign2, outgoing);
    let k3 = GetDerivativesAnalytic(s2, a, Q, fade, outgoing, geo2);
    let s3 = State(s0.X + dt * k3.X, s0.P + dt * k3.P);
    let sign3 = GetIntermediateSign(s0.X, s3.X, r_sign, a);
    let geo3 = ComputeGeometryScalars(s3.X.xyz, a, Q, fade, sign3, outgoing);
    let k4 = GetDerivativesAnalytic(s3, a, Q, fade, outgoing, geo3);
    let finalX = s0.X + (dt / 6.0) * (k1.X + 2.0 * k2.X + 2.0 * k3.X + k4.X);
    var finalP = s0.P + (dt / 6.0) * (k1.P + 2.0 * k2.P + 2.0 * k3.P + k4.P);
    let finalSign = GetIntermediateSign(s0.X, finalX, r_sign, a);
    if (finalSign > 0.0) { finalP = ApplyHamiltonianCorrection(finalP, finalX, E, a, Q, fade, finalSign, outgoing); }
    return State(finalX, finalP);
}
