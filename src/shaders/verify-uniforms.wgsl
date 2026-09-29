@group(1) @binding(0) var<storage, read_write> result: array<vec4<f32>, 8>;

// Read named WGSL fields, not a raw GPU buffer copy. This checks the ABI.
@compute @workgroup_size(1)
fn verify_uniforms() {
    result[0] = vec4<f32>(game.resolution, game.fovRadians, game.time);
    result[1] = vec4<f32>(game.deltaTime, game.quality, f32(game.debugView), game.postEnabled);
    result[2] = vec4<f32>(blackHole.massSolar, blackHole.spin, blackHole.charge, blackHole.padding);
    result[3] = vec4<f32>(blackHole.frequencyShift, blackHole.backShiftMax, blackHole.backgroundBrightness, blackHole.padding2);
    result[4] = camera.position;
    result[5] = camera.forward;
    result[6] = camera.right;
    result[7] = camera.up;
}
