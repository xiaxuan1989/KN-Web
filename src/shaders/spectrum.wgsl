// BlackHole_common.glsl::WavelengthToRgb, thresholds and normalization preserved.
fn WavelengthToRgb(wavelength: f32) -> vec3<f32> {
    var color = vec3<f32>(0);
    if (wavelength <= 380.0) { color = vec3<f32>(1,0,1); }
    else if (wavelength < 440.0) { color = vec3<f32>(-(wavelength-440.0)/60.0,0,1); }
    else if (wavelength < 490.0) { color = vec3<f32>(0,(wavelength-440.0)/50.0,1); }
    else if (wavelength < 510.0) { color = vec3<f32>(0,1,-(wavelength-510.0)/20.0); }
    else if (wavelength < 580.0) { color = vec3<f32>((wavelength-510.0)/70.0,1,0); }
    else if (wavelength < 645.0) { color = vec3<f32>(1,-(wavelength-645.0)/65.0,0); }
    else { color = vec3<f32>(1,0,0); }
    var factor = 0.3;
    if (wavelength >= 380.0 && wavelength < 420.0) { factor = 0.3+0.7*(wavelength-380.0)/40.0; }
    else if (wavelength >= 420.0 && wavelength < 645.0) { factor = 1.0; }
    else if (wavelength >= 645.0 && wavelength <= 750.0) { factor = 0.3+0.7*(750.0-wavelength)/105.0; }
    return color*factor/pow(color.r*color.r+2.25*color.g*color.g+0.36*color.b*color.b,0.5)
        *(0.1*(color.r+color.g+color.b)+0.9);
}

fn BackgroundFrequencyShift(energy: f32, maximum: f32) -> f32 {
    return clamp(1.0/max(1e-14,abs(energy)),1.0/maximum,maximum);
}

// Color portion of SampleBackground after the cube lookup. The original DEBUG=6
// magnification override is not part of the ordinary background path.
fn ShiftBackground(backcolor: vec4<f32>, shift: f32, brightness: f32) -> vec4<f32> {
    let red = backcolor.r*1.0*WavelengthToRgb(max(453.0,645.0/shift));
    let green = backcolor.g*1.5*WavelengthToRgb(max(416.0,510.0/shift));
    let blue = backcolor.b*0.6*WavelengthToRgb(max(380.0,440.0/shift));
    var color = red+green+blue;
    let originalStrength = 0.3*backcolor.r+0.6*backcolor.g+0.1*backcolor.b;
    let remappedStrength = 0.3*color.r+0.6*color.g+0.1*color.b;
    color *= originalStrength/max(remappedStrength,0.001);
    return brightness*vec4<f32>(color,backcolor.a)*pow(shift,4.0);
}
