@group(1) @binding(0) var<storage, read_write> result: array<vec4<f32>, 20>;

// Read named WGSL fields, not a raw GPU buffer copy. This checks the ABI.
@compute @workgroup_size(1)
fn verify_uniforms() {
    result[0] = vec4<f32>(game.resolution, game.fovRadians, game.time);
    result[1] = vec4<f32>(game.deltaTime, game.quality, f32(game.debugView), game.postEnabled);
    result[2] = vec4<f32>(blackHole.massSolar, blackHole.spin, blackHole.charge, blackHole.observerMode);
    result[3] = vec4<f32>(blackHole.frequencyShift, blackHole.backShiftMax, blackHole.backgroundBrightness, blackHole.fullTrace);
    result[4] = vec4<f32>(blackHole.spatialGrid,blackHole.blackHoleTime,blackHole.nativeDebug,blackHole.reserved1);
    result[5] = camera.position;
    result[6] = camera.forward;
    result[7] = camera.right;
    result[8] = camera.up;
    result[9] = camera.velocity;
    result[10] = camera.observerU;
    result[11] = camera.observerE1;
    result[12] = camera.observerE2;
    result[13] = camera.observerE3;
    result[14] = emission.geometry;
    result[15] = emission.material;
    result[16] = emission.color;
    result[17] = emission.effects;
    result[18] = emission.jet;
    result[19] = emission.control;
}
