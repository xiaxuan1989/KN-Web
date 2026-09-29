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
    padding: f32,
    frequencyShift: f32,
    backShiftMax: f32,
    backgroundBrightness: f32,
    padding2: f32,
};

struct CameraArgs {
    position: vec4<f32>,         // Rs, w unused
    forward: vec4<f32>,
    right: vec4<f32>,            // w: TAA jitter x in pixels
    up: vec4<f32>,               // w: TAA jitter y in pixels
};

@group(0) @binding(0) var<uniform> game: GameArgs;
@group(0) @binding(1) var<uniform> blackHole: BlackHoleArgs;
@group(0) @binding(2) var<uniform> camera: CameraArgs;
