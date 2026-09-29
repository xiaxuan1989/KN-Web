// Original background sampling caps LOD at 1: only the first downsample is needed.
@group(0) @binding(0) var source: texture_2d<f32>;

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    let positions = array<vec2<f32>, 3>(vec2<f32>(-1,-1), vec2<f32>(3,-1), vec2<f32>(-1,3));
    return vec4<f32>(positions[index], 0, 1);
}

@fragment
fn fs_main(@builtin(position) position: vec4<f32>) -> @location(0) vec4<f32> {
    let p = vec2<i32>(position.xy)*2;
    return 0.25*(textureLoad(source, p, 0) + textureLoad(source, p+vec2<i32>(1,0), 0)
        + textureLoad(source, p+vec2<i32>(0,1), 0) + textureLoad(source, p+vec2<i32>(1,1), 0));
}
