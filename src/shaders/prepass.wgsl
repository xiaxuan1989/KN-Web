// NPGS BlackHole_prepass / BlackHole_composite. Native statuses are Sky=1,
// Absorbed/Lost=0, Opaque=3. Observer rejection uses native opaque black.
// Numerical failures retain Web diagnostic -2; exhausted/bound rays use 0.
// Fixed when the pipeline is compiled, so disabled grid branches can be removed.
// -1 preserves the native no-grid/no-near-horizon-pruning mode.
override SPATIAL_GRID_MODE: i32 = 0;
// Keep probes diagnostic-capable by default; production explicitly specializes
// ordinary rendering to false so diagnostic state is absent from the ray loop.
override DIAGNOSTICS_ENABLED: bool = true;
@group(2) @binding(0) var prepassDistortion: texture_2d<f32>;
@group(2) @binding(1) var prepassVolumetric: texture_2d<f32>;
struct PrepassOutput {
    @location(0) distortion: vec4<f32>,
    @location(1) volumetric: vec4<f32>,
};
fn TraceScreen(uv: vec2<f32>) -> TraceResult {
    var direction = ScreenDirection(uv);
    if (blackHole.observerMode == -1.0) {
        direction = FragUvToDir(uv,tan(game.fovRadians*0.5),game.resolution);
    }
    let frame = ObserverTetrad(camera.observerU,camera.observerE1,camera.observerE2,camera.observerE3,camera.velocity.w > 0.5);
    var debug = 0;
    if (DIAGNOSTICS_ENABLED) { debug = select(i32(DiagnosticMode()),3,game.debugView == 4u); }
    let settings = RadiationSettings(emission.geometry,emission.material,emission.color,emission.effects,emission.jet,emission.control);
    let star = DenseStarSettings(emission.starSurface,emission.starControl);
    var ray: TraceResult;
    if (MaximalExtensionEnabled()) {
        ray = TraceExtendedSceneRay(camera.position.xyz,direction,blackHole.spin,blackHole.charge,game.quality,i32(blackHole.observerMode),camera.velocity.xyz,frame,SPATIAL_GRID_MODE,blackHole.blackHoleTime,debug,settings,blackHole.massSolar,uv,game.time,star,blackHole.extension).ray;
    } else {
        ray = TraceSceneRay(camera.position.xyz,direction,blackHole.spin,blackHole.charge,game.quality,i32(blackHole.observerMode),camera.velocity.xyz,frame,SPATIAL_GRID_MODE,blackHole.blackHoleTime,debug,settings,blackHole.massSolar,uv,game.time,star);
    }
    return PackDiagnostic(ray,debug,select(TraceMaxStep(blackHole.spin,blackHole.charge),TraceExtendedMaxStep(blackHole.spin,blackHole.charge),MaximalExtensionEnabled()),blackHole.backShiftMax);
}
fn EncodeTrace(ray: TraceResult) -> PrepassOutput {
    let debug = select(i32(DiagnosticMode()),3,game.debugView == 4u);
    let energyFlag = select(0.0,0.2,ray.energy < 0.0 && (!MaximalExtensionEnabled() || (debug != 3 && !(debug == 4 && ray.status == TRACE_OPAQUE))));
    if (IsSkyStatus(ray.status)) {
        let shift = BackgroundFrequencyShift(ray.energy,blackHole.backShiftMax);
        return PrepassOutput(vec4<f32>(ray.direction*shift,f32(ray.status)+energyFlag),ray.accumulated);
    }
    if (ray.status == TRACE_OPAQUE) {
        // Native DEBUG=4 retains its sky direction / shift before becoming opaque.
        let shift = BackgroundFrequencyShift(ray.energy,blackHole.backShiftMax);
        return PrepassOutput(vec4<f32>(ray.direction*shift,3.0+select(0.0,energyFlag,MaximalExtensionEnabled())),ray.accumulated);
    }
    if (ray.status == TRACE_INVALID) { return PrepassOutput(vec4<f32>(0,0,0,-2),vec4<f32>(0)); }
    return PrepassOutput(vec4<f32>(0,0,0,select(0.0,energyFlag,MaximalExtensionEnabled())),ray.accumulated);
}
@fragment
fn fs_prepass(input: VertexOutput) -> PrepassOutput {
    // Original: gl_FragCoord / iResolution, then TraceRay flips Y.
    // Resolution is full*0.5, not the rounded attachment extent. Interpolated
    // triangle UVs would stretch odd-sized (and 1-pixel) targets incorrectly.
    let uv = input.position.xy/game.resolution;
    return EncodeTrace(TraceScreen(vec2<f32>(uv.x,1.0-uv.y)));
}

// Preserve the executable source predicate, including its reversed relationship
// to the original comment: it only considers two flags in [2.5,3.5].
fn IsSensitiveBoundary(a: f32,b: f32) -> bool {
    if ((a < 2.5 || a > 3.5) || (b < 2.5 || b > 3.5)) { return false; }
    return abs(a-b) > 0.1;
}
fn GeometryEdge(center: vec4<f32>,neighbor: vec4<f32>) -> bool {
    let flag = round(center.w);
    if (flag >= 2.5 && flag <= 3.5) { return false; }
    return dot(normalize(center.xyz+vec3<f32>(1e-6)),normalize(neighbor.xyz+vec3<f32>(1e-6))) < 0.99;
}
// Explicitly clamp all texelFetch equivalents at borders (GLSL out-of-range
// texelFetch is undefined). Float32 direction/status data is never hardware-filtered.
fn PrepassCoord(p: vec2<i32>) -> vec2<i32> {
    return clamp(p,vec2<i32>(0),vec2<i32>(textureDimensions(prepassDistortion))-vec2<i32>(1));
}
fn DistortionAt(p: vec2<i32>) -> vec4<f32> { return textureLoad(prepassDistortion,PrepassCoord(p),0); }
fn VolumeAt(p: vec2<i32>) -> vec4<f32> { return textureLoad(prepassVolumetric,PrepassCoord(p),0); }
fn ManualBilinearSample(uv: vec2<f32>) -> PrepassOutput {
    let pixel = uv*vec2<f32>(textureDimensions(prepassDistortion))-0.5;
    let p = vec2<i32>(floor(pixel));
    let f = fract(pixel);
    let d00 = DistortionAt(p); let d10 = DistortionAt(p+vec2<i32>(1,0));
    let d01 = DistortionAt(p+vec2<i32>(0,1)); let d11 = DistortionAt(p+vec2<i32>(1,1));
    let distortion = mix(mix(d00.xyz,d10.xyz,f.x),mix(d01.xyz,d11.xyz,f.x),f.y);
    let volume = mix(mix(VolumeAt(p),VolumeAt(p+vec2<i32>(1,0)),f.x),
        mix(VolumeAt(p+vec2<i32>(0,1)),VolumeAt(p+vec2<i32>(1,1)),f.x),f.y);
    var flag = d00.w; var weight = (1.0-f.x)*(1.0-f.y);
    if (f.x*(1.0-f.y) > weight) { weight = f.x*(1.0-f.y); flag = d10.w; }
    if ((1.0-f.x)*f.y > weight) { weight = (1.0-f.x)*f.y; flag = d01.w; }
    if (f.x*f.y > weight) { flag = d11.w; }
    return PrepassOutput(vec4<f32>(distortion,flag),volume);
}
fn NeedsRetrace(uv: vec2<f32>) -> bool {
    let p = vec2<i32>(floor(uv*vec2<f32>(textureDimensions(prepassDistortion))));
    let center = DistortionAt(p);
    let neighbors = array<vec4<f32>,4>(DistortionAt(p+vec2<i32>(-1,0)),DistortionAt(p+vec2<i32>(1,0)),
        DistortionAt(p+vec2<i32>(0,-1)),DistortionAt(p+vec2<i32>(0,1)));
    if (center.w < 0.0) { return true; }
    for (var i=0u; i<4u; i++) {
        if (neighbors[i].w < 0.0 || IsSensitiveBoundary(round(center.w),round(neighbors[i].w)) || GeometryEdge(center,neighbors[i])) { return true; }
    }
    return false;
}
@fragment
fn fs_composite(input: VertexOutput) -> @location(0) vec4<f32> {
    // Framebuffer texels are top-left origin; camera UVs remain bottom-left.
    let textureUv = input.position.xy/game.resolution;
    var data: PrepassOutput;
    var direction = vec3<f32>(0);
    var shift = 0.0;
    if (blackHole.fullTrace > 0.5 || NeedsRetrace(textureUv)) {
        let ray = TraceScreen(vec2<f32>(textureUv.x,1.0-textureUv.y));
        data = EncodeTrace(ray);
        if (IsSkyStatus(ray.status) || any(ray.direction != vec3<f32>(0))) {
            direction = ray.direction;
            shift = BackgroundFrequencyShift(ray.energy,blackHole.backShiftMax);
        }
    } else {
        data = ManualBilinearSample(textureUv);
        shift = length(data.distortion.xyz);
        direction = data.distortion.xyz/(shift+1e-9);
    }
    let status = data.distortion.w;
    let isSky = (status > 0.5 && status < 2.5) || status > 3.5;
    let sampleDirection = select(ScreenDirection(input.uv),direction,isSky && shift > 1e-9);
    // Derivatives are evaluated after divergent retracing reconverges.
    var sky = SampleSceneBackground(sampleDirection,status);
    // The override is uniform: diagnostic derivatives still run after tracing
    // reconverges, and the entire block disappears from ordinary rendering.
    if (DIAGNOSTICS_ENABLED) {
        let view = FragUvToDir(textureUv,tan(game.fovRadians*0.5),game.resolution);
        let magnification = DebugMagnification(dpdx(direction),dpdy(direction),dpdx(view),dpdy(view));
        if (DiagnosticMode() == 6.0 && textureUv.y > 0.5) {
            sky = vec4<f32>(sky.rgb*magnification,sky.a);
        }
    }
    if (status < -1.5) { return vec4<f32>(0.38,0.05,0.28,select(1.0,0.0,game.postEnabled > 0.5)); }
    var color = data.volumetric;
    if (color.a < 0.99 && isSky && abs(status-round(status)) < 0.1) {
        let invAlpha = 1.0-color.a;
        color += 0.9999999*MapBackground(sky,shift)*vec4<f32>(pow(invAlpha,1.0),pow(invAlpha,1.6),pow(invAlpha,2.5),1);
    }
    return SceneColor(color,select(1.0,shift,blackHole.frequencyShift > 0.5));
}
