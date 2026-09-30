// Original DebugInitialMomentum; modes -1 and 3 deliberately retain its static fallback.
fn DebugInitialMomentum(P_cov: vec4<f32>, X: vec4<f32>, ObserverMode: i32, universesign: f32, PhysicalSpinA: f32, PhysicalQ: f32, GravityFade: f32, isOutgoing: bool, CameraVelocity: vec3<f32>) -> vec3<f32> {
    if (all(P_cov == vec4<f32>(114514.0))) { return vec3<f32>(0.0); }
    var geo: KerrGeometry;
    geo = ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ, GravityFade, universesign, isOutgoing);
    var P_up: vec4<f32> = RaiseIndex(P_cov, geo);
    var norm_sq: f32 = dot(P_cov, P_up);
    var U_up: vec4<f32>;
    var g_tt: f32 = -1.0 + geo.f;
    var time_comp: f32 = 1.0 / sqrt(max(1e-9, -g_tt));
    U_up = vec4<f32>(0.0, 0.0, 0.0, time_comp);
    if (ObserverMode == 1) {
        var r: f32 = geo.r; var r2: f32 = geo.r2; var a: f32 = PhysicalSpinA; var a2: f32 = geo.a2;
        var y_phys: f32 = X.y; 
        var rho2: f32 = r2 + a2 * (y_phys * y_phys) / (r2 + 1e-9);
        var Q2: f32 = PhysicalQ * PhysicalQ;
        var MassChargeTerm: f32 = 2.0 * CONST_M * r - Q2;
        var Xi: f32 = sqrt(max(0.0, MassChargeTerm * (r2 + a2)));
        var DenomPhi: f32 = rho2 * (MassChargeTerm + Xi);
        var U_phi_KS: f32 = select(0.0, -MassChargeTerm * a / DenomPhi, abs(DenomPhi) > 1e-9);
        var U_r_KS: f32 = -Xi / max(1e-9, rho2);
        var inv_r2_a2: f32 = 1.0 / (r2 + a2);
        var Ux_rad: f32 = (r * X.x - a * X.z) * inv_r2_a2 * U_r_KS;
        var Uz_rad: f32 = (r * X.z + a * X.x) * inv_r2_a2 * U_r_KS;
        var Uy_rad: f32 = (X.y / r) * U_r_KS;
        var Ux_tan: f32 =  X.z * U_phi_KS;
        var Uz_tan: f32 = -X.x * U_phi_KS;
        var U_spatial: vec3<f32> = vec3<f32>(Ux_rad + Ux_tan, Uy_rad, Uz_rad + Uz_tan);
        var l_dot_u_spatial: f32 = dot(geo.l_down.xyz, U_spatial);
        var U_spatial_sq: f32 = dot(U_spatial, U_spatial);
        var A: f32 = -1.0 + geo.f;
        var B: f32 = 2.0 * geo.f * l_dot_u_spatial;
        var C: f32 = U_spatial_sq + geo.f * (l_dot_u_spatial * l_dot_u_spatial) + 1.0; 
        var Det: f32 = max(0.0, B*B - 4.0 * A * C);
        var Ut: f32 = select(select((-B - sqrt(Det)) / (2.0 * A),2.0 * C / (-B + sqrt(Det)),B < 0.0),-C / max(1e-19, B),abs(A) < 1e-7);
        U_up = mix(vec4<f32>(0.0, 0.0, 0.0, time_comp), vec4<f32>(U_spatial, Ut), GravityFade);
    } else if (ObserverMode == 2) {
        var v_in: vec3<f32> = CameraVelocity;
        if (any((bitcast<vec3<u32>>(v_in) & vec3<u32>(0x7f800000u)) == vec3<u32>(0x7f800000u))) { v_in = vec3<f32>(0.0); }
        var V_up: vec4<f32> = vec4<f32>(v_in, 1.0);
        var V_down: vec4<f32> = LowerIndex(V_up, geo);
        var V_sq: f32 = dot(V_up, V_down);
        if (V_sq < 0.0) { U_up = V_up * inverseSqrt(-V_sq); }
    }
    var U_down: vec4<f32> = LowerIndex(U_up, geo);
    var m_r: vec3<f32> = -normalize(X.xyz);
    var WorldUp: vec3<f32> = vec3<f32>(0.0, 1.0, 0.0);
    if (abs(dot(m_r, WorldUp)) > 0.999) { WorldUp = vec3<f32>(1.0, 0.0, 0.0); }
    var m_phi: vec3<f32> = normalize(cross(WorldUp, m_r)); 
    var m_theta: vec3<f32> = cross(m_phi, m_r); 
    var e1: vec4<f32> = vec4<f32>(m_r, 0.0); e1 += dot(e1, U_down) * U_up; var e1_d: vec4<f32> = LowerIndex(e1, geo); var n1: f32 = sqrt(max(1e-9, dot(e1, e1_d))); e1 /= n1; e1_d /= n1;
    var e2: vec4<f32> = vec4<f32>(m_theta, 0.0); e2 += dot(e2, U_down) * U_up; e2 -= dot(e2, e1_d) * e1; var e2_d: vec4<f32> = LowerIndex(e2, geo); var n2: f32 = sqrt(max(1e-9, dot(e2, e2_d))); e2 /= n2; e2_d /= n2;
    var e3: vec4<f32> = vec4<f32>(m_phi, 0.0); e3 += dot(e3, U_down) * U_up; e3 -= dot(e3, e1_d) * e1; e3 -= dot(e3, e2_d) * e2; var e3_d: vec4<f32> = LowerIndex(e3, geo); e3 /= sqrt(max(1e-9, dot(e3, e3_d)));
    var p_local: vec3<f32> = vec3<f32>(dot(P_cov, e1), dot(P_cov, e2), dot(P_cov, e3));
    var local_dir: vec3<f32> = normalize(p_local); 
    var is_lightlike: bool = abs(norm_sq) < 1e-4;    
    var E_loc: f32 = -dot(P_cov, U_up);
    var is_energy_pos: bool = true;
    var is_forward: bool = true;
    var valid_r: f32 = select(0.0,1.0,is_lightlike && is_energy_pos && is_forward);
    var g_chan: f32 = local_dir.x * 0.5 + 0.5;
    var b_chan: f32 = local_dir.y * 0.5 + 0.5;
    return vec3<f32>(valid_r, g_chan, b_chan);
}

fn DebugStepColor(count: u32, maxStep: f32) -> vec4<f32> {
    return vec4<f32>(mix(vec3<f32>(0,0,1),vec3<f32>(1,0,0),f32(count)/maxStep),1);
}
fn DebugShiftColor(shift: f32, maximum: f32) -> vec4<f32> {
    // At maximum=1 the native logarithmic range is 0/0. Use its neutral midpoint.
    if (maximum == 1.0) { return vec4<f32>(0.5,0,0.5,1); }
    return vec4<f32>(mix(vec3<f32>(0,0,1),vec3<f32>(1,0,0),0.5*(log(maximum)+log(shift))/log(maximum)),1);
}
fn DebugMagnification(dDdx: vec3<f32>, dDdy: vec3<f32>, dVdx: vec3<f32>, dVdy: vec3<f32>) -> f32 {
    return length(cross(dVdx,dVdy))/max(length(cross(dDdx,dDdy)),1e-12);
}
