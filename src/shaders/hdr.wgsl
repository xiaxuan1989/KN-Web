// BlackHole_common.glsl::ApplyToneMapping: bounded expansion into the bloom HDR
// working space. Zero and >=1 use the analytic limits of the original formula.
fn ApplyToneMapping(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let c = max(color, vec3<f32>(0));
    let total = c.r+c.g+c.b;
    if (total <= 0.0) { return vec3<f32>(0); }
    let bloomMax = max(8.0,shift)+log(max(shift-7.0,1.0));
    let ceiling = bloomMax*3.0*c/total;
    let safe = min(c,vec3<f32>(1.0-1e-7));
    let expanded = min(-4.0*log(vec3<f32>(1)-pow(safe,vec3<f32>(2.2))),ceiling);
    return select(expanded,ceiling,c >= vec3<f32>(1));
}
