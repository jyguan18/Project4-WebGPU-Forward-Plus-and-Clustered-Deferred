// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;

@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;
@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;

@group(${bindGroup_gBuffer}) @binding(0) var gBufferAlbedo: texture_2d<f32>;
@group(${bindGroup_gBuffer}) @binding(1) var gBufferNormal: texture_2d<f32>;
@group(${bindGroup_gBuffer}) @binding(2) var gBufferPosition: texture_2d<f32>;

// ------------------------------------
// Shading process:
// ------------------------------------
@fragment
fn main(
    @builtin(position) fragCoord: vec4f
) -> @location(0) vec4f {

    // -----------------------------------------------------
    // Determine which cluster contains the current fragment.
    // -----------------------------------------------------

    let pixelCoord = vec2<i32>(floor(fragCoord.xy));

    let albedo = textureLoad(gBufferAlbedo, pixelCoord, 0).rgb;
    let normal = textureLoad(gBufferNormal, pixelCoord, 0).xyz;
    let worldPos = textureLoad(gBufferPosition, pixelCoord, 0).xyz;

    let fragPosView = camera.viewMat * vec4f(worldPos, 1.0);

    let clusterDim = vec3u(16u, 9u,24u);

    // x, y => ss to cluster indices
    let clusterX = u32(fragCoord.x / (camera.screenSize.x / f32(clusterDim.x)));
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
        let lightContrib = calculateLightContrib(light, worldPos, normalize(normal));

        totalLightContrib += lightContrib;
    }

    // -----------------------------------------------------
    // Multiply the fragment’s diffuse color by the accumulated light contribution.
    // Return the final color, ensuring that the alpha component is set appropriately (typically to 1).
    // -----------------------------------------------------
    var finalColor = albedo.rgb * totalLightContrib;

    return vec4f(finalColor, 1.0);
}