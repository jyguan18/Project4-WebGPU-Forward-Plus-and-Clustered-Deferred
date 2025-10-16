// TODO-3: implement the Clustered Deferred fullscreen vertex shader

// This shader should be very simple as it does not need all of the information passed by the the naive vertex shader.

@vertex
fn main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4f {
    var pos: vec2f;
    if (vertex_index == 0u) { pos = vec2f(-1.0, -1.0); }
    else if (vertex_index == 1u) { pos = vec2f(3.0, -1.0); }
    else { pos = vec2f(-1.0, 3.0); }

    return vec4f(pos, 0.0, 1.0);
}