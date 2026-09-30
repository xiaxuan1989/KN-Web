struct PostArgs {
    display: vec4<f32>, // exposure EV, gamma, bloom strength, reserved
    temporal: vec4<f32>, // current weight, reserved, bloom enabled, post enabled
};
@group(0) @binding(0) var<uniform> post: PostArgs;
@group(0) @binding(1) var source: texture_2d<f32>;
@group(0) @binding(2) var auxiliary: texture_2d<f32>;
@group(0) @binding(3) var linearSampler: sampler;
@group(0) @binding(4) var<uniform> passInfo: vec4<f32>;
@group(1) @binding(0) var outputTexture: texture_storage_2d<rgba16float,write>;

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
    return vec4<f32>(post.temporal.x*current.rgb+(1.0-post.temporal.x)*previous.rgb,current.a);
}
// NPGS Bloom.comp.glsl. All atlas passes use the full output dimensions.
fn ColorFetch(uv: vec2<f32>) -> vec3<f32> {
    if (uv.x < 0.00001 || uv.x > 0.99999 || uv.y < 0.00001 || uv.y > 0.99999) { return vec3<f32>(0); }
    let color = textureSampleLevel(source,linearSampler,uv,0.0);
    return color.rgb;
}
fn CalcOffset(octave: f32, resolution: vec2<f32>) -> vec2<f32> {
    let padding = vec2<f32>(10)/resolution;
    let column = min(1.0,floor(octave/3.0));
    return vec2<f32>(-column*(0.25+padding.x),-(1.0-1.0/exp2(octave))-padding.y*octave+column*0.35);
}
fn Grab1(uv: vec2<f32>, octave: f32, offset: vec2<f32>) -> vec3<f32> {
    let coord = (uv+offset)*exp2(octave);
    if (any(coord < vec2<f32>(0)) || any(coord > vec2<f32>(1))) { return vec3<f32>(0); }
    return ColorFetch(coord);
}
fn GrabSample(coord: vec2<f32>, resolution: vec2<f32>, scale: f32, samples: i32, i: i32, j: i32) -> vec3<f32> {
    let delta = (vec2<f32>(f32(i),f32(j))/resolution+vec2<f32>(-f32(samples)*0.5)/resolution)*scale/f32(samples);
    return ColorFetch(coord+delta);
}
fn GrabN(uv: vec2<f32>, octave: f32, offset: vec2<f32>, samples: i32) -> vec3<f32> {
    let scale = exp2(octave);
    let coord = (uv+offset)*scale;
    if (any(coord < vec2<f32>(0)) || any(coord > vec2<f32>(1))) { return vec3<f32>(0); }
    let resolution = vec2<f32>(textureDimensions(source));
    var color = vec3<f32>(0); var weights = 0.0;
    // BloomAtlas only requests 4, 8 or 16 samples per axis. Unroll the inner
    // loop to expose independent texture fetches, retaining i/j addition order.
    for (var i=0; i<samples; i++) {
        color += GrabSample(coord,resolution,scale,samples,i,0); weights += 1.0;
        color += GrabSample(coord,resolution,scale,samples,i,1); weights += 1.0;
        color += GrabSample(coord,resolution,scale,samples,i,2); weights += 1.0;
        color += GrabSample(coord,resolution,scale,samples,i,3); weights += 1.0;
        if (samples > 4) {
            color += GrabSample(coord,resolution,scale,samples,i,4); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,5); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,6); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,7); weights += 1.0;
        }
        if (samples > 8) {
            color += GrabSample(coord,resolution,scale,samples,i,8); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,9); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,10); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,11); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,12); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,13); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,14); weights += 1.0;
            color += GrabSample(coord,resolution,scale,samples,i,15); weights += 1.0;
        }
    }
    return color/weights;
}
fn BloomAtlas(uv: vec2<f32>) -> vec4<f32> {
    let resolution = vec2<f32>(textureDimensions(source));
    var color = Grab1(uv,1.0,vec2<f32>(0));
    color += GrabN(uv,2.0,CalcOffset(1.0,resolution),4);
    color += GrabN(uv,3.0,CalcOffset(2.0,resolution),8);
    color += GrabN(uv,4.0,CalcOffset(3.0,resolution),16);
    color += GrabN(uv,5.0,CalcOffset(4.0,resolution),16);
    color += GrabN(uv,6.0,CalcOffset(5.0,resolution),16);
    color += GrabN(uv,7.0,CalcOffset(6.0,resolution),16);
    color += GrabN(uv,8.0,CalcOffset(7.0,resolution),16);
    return vec4<f32>(color,1);
}
fn blur(uv: vec2<f32>,axis: vec2<f32>) -> vec4<f32> {
    let weights = array<f32,5>(0.19638062,0.29675293,0.09442139,0.01037598,0.00025940);
    let offsets = array<f32,5>(0.0,1.41176471,3.29411765,5.17647059,7.05882353);
    if (uv.x >= 0.52) { return vec4<f32>(0,0,0,1); }
    var color = ColorFetch(uv)*weights[0];
    var total = weights[0];
    let resolution = vec2<f32>(textureDimensions(source));
    for (var i=1; i<5; i++) {
        let offset = vec2<f32>(offsets[i])/resolution;
        color += ColorFetch(uv+offset*axis)*weights[i];
        color += ColorFetch(uv-offset*axis)*weights[i];
        total += weights[i]*2.0;
    }
    return vec4<f32>(color/total,1);
}
// NPGS ColorBlend.frag.glsl; retain its shifted cubic weights verbatim.
fn Cubic(x: f32) -> vec4<f32> {
    let x2=x*x; let x3=x2*x;
    return vec4<f32>(-x3+3.0*x2-3.0*x+1.0,3.0*x3-6.0*x2+4.0,-3.0*x3+3.0*x2+3.0*x+1.0,x3)/6.0;
}
fn BicubicTexture(uv: vec2<f32>) -> vec3<f32> {
    let resolution = vec2<f32>(textureDimensions(auxiliary));
    let pixel = uv*resolution;
    let fraction = fract(pixel);
    let base = pixel-fraction;
    let cx = Cubic(fraction.x-0.5); let cy = Cubic(fraction.y-0.5);
    let coord = vec4<f32>(base.x-0.5,base.x+1.5,base.y-0.5,base.y+1.5);
    let weights = vec4<f32>(cx.x+cx.y,cx.z+cx.w,cy.x+cy.y,cy.z+cy.w);
    let offset = coord+vec4<f32>(cx.y,cx.w,cy.y,cy.w)/weights;
    let s0 = textureSampleLevel(auxiliary,linearSampler,offset.xz/resolution,0.0).rgb;
    let s1 = textureSampleLevel(auxiliary,linearSampler,offset.yz/resolution,0.0).rgb;
    let s2 = textureSampleLevel(auxiliary,linearSampler,offset.xw/resolution,0.0).rgb;
    let s3 = textureSampleLevel(auxiliary,linearSampler,offset.yw/resolution,0.0).rgb;
    return mix(mix(s3,s2,weights.x/(weights.x+weights.y)),mix(s1,s0,weights.x/(weights.x+weights.y)),weights.z/(weights.z+weights.w));
}
fn GetBloom(uv: vec2<f32>) -> vec3<f32> {
    let resolution = vec2<f32>(textureDimensions(auxiliary));
    var color = vec3<f32>(0);
    color += BicubicTexture(uv/exp2(1.0)-CalcOffset(0.0,resolution))*1.0;
    color += BicubicTexture(uv/exp2(2.0)-CalcOffset(1.0,resolution))*1.5;
    color += BicubicTexture(uv/exp2(3.0)-CalcOffset(2.0,resolution))*1.0;
    color += BicubicTexture(uv/exp2(4.0)-CalcOffset(3.0,resolution))*1.5;
    color += BicubicTexture(uv/exp2(5.0)-CalcOffset(4.0,resolution))*1.8;
    color += BicubicTexture(uv/exp2(6.0)-CalcOffset(5.0,resolution))*1.0;
    color += BicubicTexture(uv/exp2(7.0)-CalcOffset(6.0,resolution))*1.0;
    color += BicubicTexture(uv/exp2(8.0)-CalcOffset(7.0,resolution))*1.0;
    return color;
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
    var glow = vec3<f32>(0);
    if (post.temporal.z > 0.5) { glow = GetBloom(input.position.xy/vec2<f32>(textureDimensions(source))); }
    let hdr = color.rgb+glow*post.display.z*post.temporal.z;
    return vec4<f32>(DisplayMap(hdr,post.display.x,post.display.y),1);
}
// Same pixel centers, full-size intermediates and f16 stage boundaries as NPGS.
// Only scheduling differs: small atlas groups, larger groups for the short blur.
@compute @workgroup_size(4,4) fn bloom_atlas(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size=textureDimensions(outputTexture);
    if (any(gid.xy>=size)) { return; }
    let uv=(vec2<f32>(gid.xy)+vec2<f32>(0.5))/vec2<f32>(size);
    textureStore(outputTexture,vec2<i32>(gid.xy),BloomAtlas(uv));
}
@compute @workgroup_size(16,16) fn blur_h(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size=textureDimensions(outputTexture);
    if (any(gid.xy>=size)) { return; }
    let uv=(vec2<f32>(gid.xy)+vec2<f32>(0.5))/vec2<f32>(size);
    textureStore(outputTexture,vec2<i32>(gid.xy),blur(uv,vec2<f32>(0.5,0)));
}
@compute @workgroup_size(16,16) fn blur_v(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size=textureDimensions(outputTexture);
    if (any(gid.xy>=size)) { return; }
    let uv=(vec2<f32>(gid.xy)+vec2<f32>(0.5))/vec2<f32>(size);
    textureStore(outputTexture,vec2<i32>(gid.xy),blur(uv,vec2<f32>(0,0.5)));
}
