// NPGS transformKerrSchild_YSpin, retained for numerical chart switching.
// This does not enable maximal extension or passage to other universes.
fn transformKerrSchild_YSpin(S: State, r_sign: f32, M: f32, a: f32, Q: f32, out_to_in: bool) -> State {
    let eps = 1e-16;
    let x = S.X.x; let y = S.X.y; let z = S.X.z; let t = S.X.w;
    let px = S.P.x; let py = S.P.y; let pz = S.P.z; let pt = S.P.w;
    let a2 = a * a; let M2 = M * M; let Q2 = Q * Q;
    let R2 = x*x + y*y + z*z;
    let u = R2 - a2;
    let v = 4.0 * a2 * y * y;
    var r2: f32;
    if (u >= 0.0) { r2 = 0.5 * (u + sqrt(u*u + v)); }
    else { r2 = 0.5 * v / max(1e-20, sqrt(u*u + v) - u); }
    let r = r_sign * sqrt(max(r2, 0.0));
    let Delta = r*r - 2.0*M*r + a2 + Q2;
    var safe_Delta = sign(Delta) * max(abs(Delta), eps);
    if (safe_Delta == 0.0) { safe_Delta = eps; }
    let r3 = r*r*r;
    let safe_D = max(r3*r + a2*y*y, 1e-12);
    let grad_r = vec3<f32>(r3*x / safe_D, r*(r*r+a2)*y / safe_D, r3*z / safe_D);
    let delta_disc = M2 - a2 - Q2;
    var F_r = 0.0;
    var g_r = 0.0;
    let abs_Delta_safe = max(abs(Delta), eps);
    if (delta_disc > eps) {
        let K = sqrt(delta_disc);
        let r_plus = M + K;
        let r_minus = M - K;
        let frac = abs(r - r_plus) / max(abs(r - r_minus), eps);
        let ln_arg = log(max(frac, eps));
        F_r = 2.0*M*log(abs_Delta_safe) + ((2.0*M2-Q2)/K)*ln_arg;
        g_r = (a/K)*ln_arg;
    } else if (delta_disc < -eps) {
        let K = sqrt(-delta_disc);
        let atan_arg = atan((r-M)/K);
        F_r = 2.0*M*log(abs_Delta_safe) + (2.0*(2.0*M2-Q2)/K)*atan_arg;
        g_r = (2.0*a/K)*atan_arg;
    } else {
        let rM = r-M;
        var safe_rM = sign(rM)*max(abs(rM), eps);
        if (safe_rM == 0.0) { safe_rM = eps; }
        F_r = 4.0*M*log(max(abs(rM), eps)) - 2.0*(2.0*M2-Q2)/safe_rM;
        g_r = -2.0*a/safe_rM;
    }
    g_r += 2.0*atan2(a, r);
    let F_prime = 2.0*(2.0*M*r-Q2)/safe_Delta;
    let g_prime = 2.0*a/safe_Delta - 2.0*a/(r*r+a*a);
    let Ly = z*px - x*pz;
    let K_p = F_prime*pt + g_prime*Ly;
    let dir = select(1.0, -1.0, out_to_in);
    let angle = -dir*g_r;
    let P_tilde = vec3<f32>(px, py, pz) + dir*grad_r*K_p;
    let cos_a = cos(angle); let sin_a = sin(angle);
    return State(
        vec4<f32>(x*cos_a+z*sin_a, y, z*cos_a-x*sin_a, t-dir*F_r),
        vec4<f32>(P_tilde.z*sin_a+P_tilde.x*cos_a, P_tilde.y, -P_tilde.x*sin_a+P_tilde.z*cos_a, pt),
    );
}

// Common/CoordConverter.glsl: Fov is tan(horizontal FOV / 2).
// Caller UV is already bottom-left based; do not apply GLSL's extra Y flip.
fn FragUvToDir(uv: vec2<f32>, Fov: f32, resolution: vec2<f32>) -> vec3<f32> {
    return normalize(vec3<f32>(Fov*(2.0*uv.x-1.0), Fov*(2.0*uv.y-1.0)*resolution.y/resolution.x, -1.0));
}
