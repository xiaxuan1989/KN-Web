struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@group(1) @binding(0) var background: texture_cube<f32>;
@group(1) @binding(1) var backgroundSampler: sampler;

// One oversized triangle covers the viewport without a vertex buffer.
@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> VertexOutput {
    let positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 3.0, -1.0),
        vec2<f32>(-1.0,  3.0),
    );
    let position = positions[index];
    var output: VertexOutput;
    output.position = vec4<f32>(position, 0.0, 1.0);
    // Bottom-left: (0, 0); top-right: (1, 1).
    output.uv = position * 0.5 + vec2<f32>(0.5);
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // UV diagnostic remains available for Phase 0 regression checks.
    if (game.debugView == 0u) {
        return vec4<f32>(input.uv, 0.25, 1.0);
    }
    if (game.debugView == 2u) {
        // Diagnostic colors only: no physical interpretation or lensing yet.
        let tint = vec3<f32>(
            clamp((log2(blackHole.massSolar) / log2(10.0) + 1.0) / 11.0, 0.0, 1.0),
            (blackHole.spin + 1.5) / 3.0,
            (blackHole.charge + 1.5) / 3.0,
        );
        let band = 0.75 + 0.25 * sin(input.uv.x * game.quality * 30.0 + game.time);
        return vec4<f32>(tint * band, 1.0);
    }

    let direction = ScreenDirection(input.uv);
    var traced = TraceResult(direction, TRACE_ESCAPED, 0u, 0.0, 1.0);
    if (game.debugView == 3u || game.debugView == 4u) {
        traced = TraceRay(camera.position.xyz, direction, blackHole.spin, blackHole.charge, game.quality);
    }
    // Sample after ray-dependent branches reconverge, before any per-ray return.
    // This keeps implicit derivatives in uniform control flow. The sampler clamps
    // LOD to [0,1], matching min(1, textureQueryLod(...).x) in SampleBackground.
    // Captured/invalid rays may have a zero direction; never sample a zero cube vector.
    let sampleDirection = select(direction, traced.direction, traced.status == TRACE_ESCAPED);
    let skyColor = textureSample(background, backgroundSampler, sampleDirection);
    if (game.debugView == 3u || game.debugView == 4u) {
        if (traced.status == TRACE_INVALID) { return vec4<f32>(0.38, 0.05, 0.28, select(1.0,0.0,game.postEnabled > 0.5)); }
        if (game.debugView == 4u) {
            if (traced.status == TRACE_CAPTURED) { return vec4<f32>(0.0, 0.0, 0.0, 1.0); }
            if (traced.status == TRACE_UNRESOLVED) { return vec4<f32>(1.0, 0.4, 0.05, 1.0); }
            let heat = clamp(f32(traced.steps)/300.0, 0.0, 1.0);
            return vec4<f32>(heat, 0.25, 1.0-heat, 1.0);
        }
        if (traced.status == TRACE_CAPTURED) { return vec4<f32>(0.0, 0.0, 0.0, 1.0); }
        // Budget exhaustion is visible and is never labelled as a horizon hit.
        if (traced.status == TRACE_UNRESOLVED) { return vec4<f32>(0.55, 0.19, 0.015, select(1.0,0.0,game.postEnabled > 0.5)); }
        return BackgroundColor(skyColor, traced.energy);
    }
    if (game.debugView == 5u) { return BackgroundColor(skyColor, 1.0); }
    var color = vec3<f32>(0.5) + 0.5 * direction;

    // A flat reference grid at y = -2 Rs makes translation visible.
    // This is an input diagnostic, not a black-hole rendering approximation.
    if (abs(direction.y) > 0.0001) {
        let distance = (-2.0 - camera.position.y) / direction.y;
        if (distance > 0.0 && distance < 200.0) {
            let point = camera.position.xyz + distance * direction;
            let cell = abs(fract(point.xz) - vec2<f32>(0.5));
            let footprint = max(distance / game.resolution.y, 0.015);
            let line = smoothstep(0.5 - min(footprint, 0.15), 0.5, max(cell.x, cell.y));
            let gridColor = mix(vec3<f32>(0.035, 0.055, 0.09), vec3<f32>(0.4, 0.65, 0.85), line);
            color = mix(color, gridColor, exp(-distance * 0.025));
        }
    }
    return vec4<f32>(color, 1.0);
}

fn ScreenDirection(uv: vec2<f32>) -> vec3<f32> {
    let rayUv = uv+vec2<f32>(camera.right.w,camera.up.w)/game.resolution;
    let local = FragUvToDir(rayUv,tan(game.fovRadians*0.5),game.resolution);
    return normalize(local.x*camera.right.xyz+local.y*camera.up.xyz-local.z*camera.forward.xyz);
}
fn MapBackground(sampled: vec4<f32>,shift: f32) -> vec4<f32> {
    if (blackHole.frequencyShift > 0.5) { return ShiftBackground(sampled,shift,blackHole.backgroundBrightness); }
    return sampled;
}
fn BackgroundColor(sampled: vec4<f32>,energy: f32) -> vec4<f32> {
    let shift = select(1.0,BackgroundFrequencyShift(energy,blackHole.backShiftMax),blackHole.frequencyShift > 0.5);
    return SceneColor(MapBackground(sampled,shift),shift);
}
fn SceneColor(color: vec4<f32>,shift: f32) -> vec4<f32> {
    if (game.postEnabled > 0.5) { return vec4<f32>(ApplyToneMapping(color.rgb,shift),1); }
    // Clip the SDR bypass before f16 storage to prevent half-float overflow.
    return vec4<f32>(clamp(color.rgb,vec3<f32>(0),vec3<f32>(1)),1);
}
