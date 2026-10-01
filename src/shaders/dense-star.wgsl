// BlackHole_common.glsl Fbm_Standalone / DensestarColor, including signed sheets.
struct DenseStarSettings {
    surface: vec4<f32>, // signed Rs, blackbody intensity, redshift color, redshift intensity
    control: vec4<f32>, // brightness, enabled, runtime Whitehole, reserved
};
fn DenseStarRadius(settings: DenseStarSettings) -> f32 {
    return select(0.0, settings.surface.x, settings.control.y > 0.5);
}
fn FbmStandalone(point: vec3<f32>) -> f32 {
    var x = point;
    var sum = vec2<f32>(0);
    var amplitude = 1.0;
    for (var i = 0u; i < 3u; i++) {
        sum += vec2<f32>(amplitude*PerlinNoise(x));
        x += 1.4*sum.xyx*vec3<f32>(0.7,0.6,1.3);
        amplitude *= 0.74;
        x *= 4.0;
    }
    return sum.x;
}
fn DenseStarHermite(t: f32, previous: vec4<f32>, tangent0: vec4<f32>, current: vec4<f32>, tangent1: vec4<f32>) -> vec4<f32> {
    let t2 = t*t;
    let t3 = t2*t;
    return (2.0*t3-3.0*t2+1.0)*previous+(t3-2.0*t2+t)*tangent0+
        (-2.0*t3+3.0*t2)*current+(t3-t2)*tangent1;
}
fn DenseStarColor(base: vec4<f32>, current: State, previous: State, a: f32, Q: f32,
    outgoing: bool, sign: f32, dlambda: f32, blackHoleTime: f32, debug: i32, settings: DenseStarSettings) -> vec4<f32> {
    var result = base;
    let signedR = DenseStarRadius(settings);
    if (signedR == 0.0) { return result; }
    let lastGeo = ComputeGeometryScalars(previous.X.xyz,a,Q,1.0,sign,outgoing);
    let currentGeo = ComputeGeometryScalars(current.X.xyz,a,Q,1.0,sign,outgoing);
    let tangent0 = RaiseIndex(previous.P,lastGeo)*dlambda;
    let tangent1 = RaiseIndex(current.P,currentGeo)*dlambda;
    let radius = abs(signedR);
    let roots = IntersectKerrEllipsoid(previous.X.xyz,current.X.xyz-previous.X.xyz,radius,a);
    let hits = array<f32,2>(min(roots.x,roots.y),max(roots.x,roots.y));
    for (var j = 0u; j < 2u; j++) {
        var t = hits[j];
        if (t < 0.0 || t > 1.0 || sign*signedR < 0.0) { continue; }
        for (var iteration = 0u; iteration < 2u; iteration++) {
            let pos = DenseStarHermite(t,previous.X,tangent0,current.X,tangent1).xyz;
            let r = KerrSchildRadius(pos,a,sign);
            let nextPos = DenseStarHermite(t+0.001,previous.X,tangent0,current.X,tangent1).xyz;
            let nextR = KerrSchildRadius(nextPos,a,sign);
            let drdt = (nextR-r)/0.001;
            t -= (r-signedR)/(drdt+1e-12);
        }
        if (t < 0.0 || t > 1.0) { continue; }
        let hit = DenseStarHermite(t,previous.X,tangent0,current.X,tangent1);
        let hitPos = hit.xyz;
        if (abs(KerrSchildRadius(hitPos,a,sign)-signedR) > 0.1*radius+0.1) { continue; }
        let hitP = mix(previous.P,current.P,t);
        var pattern = hit;
        if (outgoing) {
            pattern = transformKerrSchild_YSpin(State(hit,vec4<f32>(0)),sign,CONST_M,a,Q,true).X;
        }
        let omega = a/(signedR*signedR+a*a);
        let emissionTime = blackHoleTime+pattern.w;
        var texturePos = normalize(pattern.xyz);
        let c = cos(omega*emissionTime);
        let s = sin(omega*emissionTime);
        let rotated = mat2x2<f32>(vec2<f32>(c,s),vec2<f32>(-s,c))*texturePos.xz;
        texturePos = vec3<f32>(rotated.x,texturePos.y,rotated.y)*4.0;
        let animation = emissionTime*0.01;
        let noisePos = texturePos+vec3<f32>(sin(animation)*2.0,cos(animation)*2.0,0);
        let baseTemp = 6000.0*clamp(FbmStandalone(noisePos)*0.2+0.8,0.5,1.5);
        let velocity = vec4<f32>(omega*vec3<f32>(hitPos.z,0,-hitPos.x),1);
        let hitGeo = ComputeGeometryScalars(hitPos,a,Q,1.0,sign,outgoing);
        let normSq = dot(velocity,LowerIndex(velocity,hitGeo));
        let U = velocity/sqrt(max(1e-9,abs(normSq)));
        let emissionEnergy = -dot(hitP,U);
        let shift = 1.0/max(1e-9,abs(emissionEnergy));
        var color = KelvinToRgb(baseTemp*pow(shift,settings.surface.z));
        let redshiftIntensity = pow(shift,settings.surface.w);
        var intensity = pow(baseTemp/6000.0,settings.surface.y)*redshiftIntensity;
        if (debug == 5) {
            let unitPos = normalize(texturePos);
            color = step(vec3<f32>(0),unitPos)*0.8+0.2;
            let safeX = select(unitPos.x,1e-9,abs(unitPos.x)<1e-9 && abs(unitPos.z)<1e-9);
            let phi = atan2(unitPos.z,safeX);
            let theta = asin(clamp(unitPos.y,-1.0,1.0));
            let checkerSum = floor(phi*6.0)+floor(theta*6.0);
            // GLSL mod is floor-based, including negative longitude / latitude.
            let checker = checkerSum-2.0*floor(checkerSum/2.0);
            intensity = clamp(checker*0.7+0.3,0.0,1.0)*redshiftIntensity;
        }
        var star = vec4<f32>(settings.control.x*color*intensity,1);
        // NPGS first inverts negative-energy color, then suppresses it when
        // The runtime Whitehole flag retains native negative-energy emission.
        if (emissionEnergy < 0.0) {
            let cMax = max(max(star.r,star.g),star.b);
            let cMin = min(min(star.r,star.g),star.b);
            star = vec4<f32>(vec3<f32>(cMax+cMin)-star.rgb,star.a);
            if (settings.control.z < 0.5) { star = vec4<f32>(0); }
        }
        result = vec4<f32>(result.rgb+star.rgb*star.a*(1.0-result.a),result.a+star.a*(1.0-result.a));
        if (result.a > 0.99) { break; }
    }
    return result;
}
