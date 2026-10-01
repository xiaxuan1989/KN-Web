struct GameArgs {
    resolution: vec2<f32>,       // byte 0
    fovRadians: f32,             // byte 8, horizontal FOV (original NPGS)
    time: f32,                   // byte 12, active render seconds
    deltaTime: f32,              // byte 16
    quality: f32,                // byte 20
    debugView: u32,              // byte 24
    postEnabled: f32,            // byte 28; HDR working space enabled
};

struct BlackHoleArgs {
    massSolar: f32,
    spin: f32,                   // a*
    charge: f32,                 // Q*
    observerMode: f32,
    frequencyShift: f32,
    backShiftMax: f32,
    backgroundBrightness: f32,
    fullTrace: f32,
    spatialGrid: f32,            // native iGrid -1 / 0 / 1 / 2; CPU selects matching pipeline
    blackHoleTime: f32,          // c * GameTime / Rs, or transported KS time
    nativeDebug: f32,            // original iDEBUG 0..6
    reserved1: f32,
    extension: vec4<f32>, // Whitehole enable, native iUniverseSign, iInWhichUniverse, reserved
};

struct CameraArgs {
    position: vec4<f32>,         // Rs, w unused
    forward: vec4<f32>,
    right: vec4<f32>,            // w: TAA jitter x in pixels
    up: vec4<f32>,               // w: TAA jitter y in pixels
    velocity: vec4<f32>,         // xyz velocity/c; w: transported frame uses outgoing chart
    observerU: vec4<f32>,
    observerE1: vec4<f32>,
    observerE2: vec4<f32>,
    observerE3: vec4<f32>,
};

@group(0) @binding(0) var<uniform> game: GameArgs;
@group(0) @binding(1) var<uniform> blackHole: BlackHoleArgs;
@group(0) @binding(2) var<uniform> camera: CameraArgs;

// Phase 1A / 1B / 1C: independent emission buffer preserves existing geometry ABI.
struct EmissionArgs {
    geometry: vec4<f32>,
    material: vec4<f32>,
    color: vec4<f32>,
    effects: vec4<f32>,
    jet: vec4<f32>,
    control: vec4<f32>,
    starSurface: vec4<f32>,
    starControl: vec4<f32>,
};
@group(0) @binding(3) var<uniform> emission: EmissionArgs;

// Production uses 0 when disabled, 1 when enabled. Keep the enabled path
// uniform-driven: folding that branch changed a sensitive whitehole case on
// Metal. -1 is the same dynamic reference path used by validation probes.
override MAXIMAL_EXTENSION_MODE: i32 = -1;
fn MaximalExtensionEnabled() -> bool {
    if (MAXIMAL_EXTENSION_MODE == 0) { return false; }
    return blackHole.extension.x > 0.5;
}
