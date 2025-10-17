// TODO-2: implement the Forward+ fragment shader
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;
@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights
struct FragmentInput
{
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}
// ------------------------------------
// Shading process:
// ------------------------------------
@fragment
fn main(
    @builtin(position) fragCoord: vec4f, 
    in: FragmentInput
) -> @location(0) vec4f {
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }

    // -----------------------------------------------------
    // Determine which cluster contains the current fragment.
    // -----------------------------------------------------

    let fragPosView = camera.viewMat * vec4f(in.pos, 1.0); // frag pos in view space
    let clusterDim = vec3u(16u, 9u,24u);

    // x, y => ss to cluster indices
    let clusterX = u32(fragCoord.x / (camera.screenSize.x / f32(clusterDim.x)));
    //let clusterY = u32(fragCoord.y / (camera.screenSize.y / f32(clusterDim.y)));
    let clusterY = u32(fragCoord.y / (camera.screenSize.y / f32(clusterDim.y)));

    // z => depth in view space to cluster indices
    let depthView = -fragPosView.z; // view space looks down = negative
    let zNear = camera.near;

    let zFar = camera.far;

    let clusterZ = u32(log(depthView / zNear) / log(zFar / zNear) * f32(clusterDim.z));

    let clusterIdxX = clamp(clusterX, 0u, clusterDim.x - 1u);
    let clusterIdxY = clamp(clusterY, 0u, clusterDim.y - 1u);
    let clusterIdxZ = clamp(clusterZ, 0u, clusterDim.z - 1u);

    let clusterIdx = clusterIdxZ * (clusterDim.x * clusterDim.y) +
            clusterIdxY * (clusterDim.x) + clusterIdxX;

    // -----------------------------------------------------
    // Retrieve the number of lights that affect the current fragment from the cluster’s data.
    // -----------------------------------------------------

    let cluster = clusterSet.clusters[clusterIdx];
    let numLights = cluster.numLights;

    // Initialize a variable to accumulate the total light contribution for the fragment.
    var totalLightContrib = vec3f(0.0, 0.0, 0.0);

    // For each light in the cluster:
    //     Access the light's properties using its index.
    //     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
    //     Add the calculated contribution to the total light accumulation.
    for (var i = 0u; i < numLights; i = i + 1u){
        let lightIdx = cluster.lightIndices[i];
        let light = lightSet.lights[lightIdx];
        let lightContrib = calculateLightContrib(light, in.pos, normalize(in.nor));

        totalLightContrib += lightContrib;
    }

    // -----------------------------------------------------
    // Multiply the fragment’s diffuse color by the accumulated light contribution.
    // Return the final color, ensuring that the alpha component is set appropriately (typically to 1).
    // -----------------------------------------------------
    var finalColor = diffuseColor.rgb * totalLightContrib;
    return vec4f(finalColor, 1.0);
        
}