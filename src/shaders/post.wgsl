struct PostArgs {
    display: vec4<f32>, // exposure EV, gamma, bloom strength, threshold
    temporal: vec4<f32>, // current weight, reserved, bloom enabled, post enabled
};
@group(0) @binding(0) var<uniform> post: PostArgs;
@group(0) @binding(1) var source: texture_2d<f32>;
@group(0) @binding(2) var auxiliary: texture_2d<f32>;
@group(0) @binding(3) var linearSampler: sampler;
@group(0) @binding(4) var<uniform> passInfo: vec4<f32>;

struct PostVertex { @builtin(position) position: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> PostVertex {
    let p = array<vec2<f32>,3>(vec2<f32>(-1,-1),vec2<f32>(3,-1),vec2<f32>(-1,3))[index];
    return PostVertex(vec4<f32>(p,0,1),vec2<f32>(p.x*0.5+0.5,0.5-p.y*0.5));
}
@fragment
fn taa(input: PostVertex) -> @location(0) vec4<f32> {
    let pixel = vec2<i32>(input.position.xy);
    let current = textureLoad(source,pixel,0);
    if (post.temporal.x >= 1.0 || current.a < 0.5) { return current; }
    let previous = textureLoad(auxiliary,pixel,0);
    if (previous.a < 0.5) { return current; }
    return vec4<f32>(mix(previous.rgb,current.rgb,post.temporal.x),current.a);
}
fn bright(color: vec4<f32>) -> vec3<f32> {
    if (color.a < 0.5) { return vec3<f32>(0); }
    let peak = max(color.r,max(color.g,color.b));
    return color.rgb * max(peak-post.display.w,0.0)/max(peak,1e-6);
}
@fragment
fn downsample(input: PostVertex) -> @location(0) vec4<f32> {
    let step = 0.5/vec2<f32>(textureDimensions(source));
    var color = vec3<f32>(0);
    for (var y=0; y<2; y++) { for (var x=0; x<2; x++) {
        let offset = vec2<f32>(f32(x*2-1),f32(y*2-1))*step;
        let sampleColor = textureSampleLevel(source,linearSampler,input.uv+offset,0.0);
        color += select(sampleColor.rgb,bright(sampleColor),passInfo.x > 0.5);
    }}
    return vec4<f32>(color*0.25,1);
}
fn blur(uv: vec2<f32>,axis: vec2<f32>) -> vec4<f32> {
    // NPGS Bloom.frag.glsl::GaussBlur coefficients and paired linear taps.
    let weights = array<f32,5>(0.19638062,0.29675293,0.09442139,0.01037598,0.00025940);
    let offsets = array<f32,5>(0.0,1.41176471,3.29411765,5.17647059,7.05882353);
    var color = textureSampleLevel(source,linearSampler,uv,0.0).rgb*weights[0];
    var total = weights[0];
    let step = axis/vec2<f32>(textureDimensions(source));
    for (var i=1; i<5; i++) {
        color += (textureSampleLevel(source,linearSampler,uv+step*offsets[i],0.0).rgb
            +textureSampleLevel(source,linearSampler,uv-step*offsets[i],0.0).rgb)*weights[i];
        total += 2.0*weights[i];
    }
    return vec4<f32>(color/total,1);
}
@fragment fn blur_h(input: PostVertex) -> @location(0) vec4<f32> { return blur(input.uv,vec2<f32>(0.5,0)); }
@fragment fn blur_v(input: PostVertex) -> @location(0) vec4<f32> { return blur(input.uv,vec2<f32>(0,0.5)); }
@fragment
fn upsample(input: PostVertex) -> @location(0) vec4<f32> {
    let fine = textureSampleLevel(source,linearSampler,input.uv,0.0).rgb*passInfo.x;
    let coarse = textureSampleLevel(auxiliary,linearSampler,input.uv,0.0).rgb*passInfo.y;
    return vec4<f32>(fine+coarse,1);
}
fn DisplayMap(hdr: vec3<f32>,exposure: f32,gamma: f32) -> vec3<f32> {
    // ColorBlend.frag.glsl grading, with exposure EV and adjustable final gamma.
    var color = pow(max(hdr*exp2(exposure),vec3<f32>(0)),vec3<f32>(1.5));
    color = pow(color/(vec3<f32>(1)+color),vec3<f32>(1.0/1.5));
    color = color*color*(vec3<f32>(3)-2.0*color);
    color = pow(color,vec3<f32>(1.3,1.20,1.0));
    color = clamp(color*1.01,vec3<f32>(0),vec3<f32>(1));
    return pow(color,vec3<f32>(0.7/gamma));
}
@fragment
fn present(input: PostVertex) -> @location(0) vec4<f32> {
    let color = textureSampleLevel(source,linearSampler,input.uv,0.0);
    if (post.temporal.w < 0.5 || color.a < 0.5) { return vec4<f32>(color.rgb,1); }
    let glow = textureSampleLevel(auxiliary,linearSampler,input.uv,0.0).rgb;
    let hdr = color.rgb+glow*post.display.z*post.temporal.z;
    return vec4<f32>(DisplayMap(hdr,post.display.x,post.display.y),1);
}
