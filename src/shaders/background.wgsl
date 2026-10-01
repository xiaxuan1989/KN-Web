// Original six NPGS cubemaps. Bindings 0/1 preserve Universe0 / sampler ABI.
@group(1) @binding(2) var antiverse0: texture_cube<f32>;
@group(1) @binding(3) var universe1: texture_cube<f32>;
@group(1) @binding(4) var antiverse1: texture_cube<f32>;
@group(1) @binding(5) var universe2: texture_cube<f32>;
@group(1) @binding(6) var antiverse2: texture_cube<f32>;
fn CurrentBackgroundStatus() -> f32 {
    let sign = blackHole.extension.y*select(1.0,-1.0,blackHole.massSolar < 0.0);
    return select(1.0,select(2.0,1.0,sign > 0.0),MaximalExtensionEnabled());
}
fn BackgroundSelection(status: f32, universe: i32, negativeMass: bool) -> vec2<i32> {
    let rounded = round(status);
    var offset = 0;
    if (rounded > 3.0) { offset = i32(round((rounded-1.0)/3.0)); }
    let index = (universe+3-offset)%3;
    let anti = (i32(rounded)%3 == 2) != negativeMass;
    return vec2<i32>(index,i32(anti));
}
fn SampleSceneBackground(direction: vec3<f32>, status: f32) -> vec4<f32> {
    // Sample in reconverged control flow: each ray may select a different sheet.
    // Implicit cube derivatives preserve NPGS LOD; the sampler clamps to [0,1].
    let positive0 = textureSample(background,backgroundSampler,direction);
    if (!MaximalExtensionEnabled()) { return positive0; }
    let negative0 = textureSample(antiverse0,backgroundSampler,direction);
    let positive1 = textureSample(universe1,backgroundSampler,direction);
    let negative1 = textureSample(antiverse1,backgroundSampler,direction);
    let positive2 = textureSample(universe2,backgroundSampler,direction);
    let negative2 = textureSample(antiverse2,backgroundSampler,direction);
    let selection = BackgroundSelection(status,i32(blackHole.extension.z),blackHole.massSolar < 0.0);
    if (selection.x == 1) { return select(positive1,negative1,selection.y == 1); }
    if (selection.x == 2) { return select(positive2,negative2,selection.y == 1); }
    return select(positive0,negative0,selection.y == 1);
}
