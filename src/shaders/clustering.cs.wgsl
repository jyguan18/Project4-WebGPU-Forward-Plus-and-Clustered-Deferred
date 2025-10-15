// TODO-2: implement the light clustering compute shader
@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;

const CLUSTER_X: u32 = 16u;
const CLUSTER_Y: u32 = 9u;
const CLUSTER_Z: u32 = 24u;

// HELPER FUNCTIONS
fn clipToView(clip: vec4f) -> vec4f {
    var view = camera.inverseProj * clip;
    view = view / view.w;
    return view;
}

fn screen2View(screen: vec4f) -> vec4f {
    let texCoord = screen.xy / camera.screenSize.xy;

    let clip = vec4f(
        texCoord.x * 2.0 - 1.0, 
        (1.0 - texCoord.y) * 2.0 - 1.0, 
        screen.z, 
        screen.w);

    return clipToView(clip);
}

fn lineIntersectionToZPlane(A: vec3f, B: vec3f, zDistance: f32) -> vec3f {
    let normal = vec3f(0.0, 0.0, 1.0);
    let ab = B - A;
    let t = (zDistance - A.z) / ab.z;

    let result = A + t * ab;
    return result;
}

fn sqDistPointAABB(point: vec3f, aabbMin: vec3f, aabbMax: vec3f) -> f32 {
    let closestPoint = clamp(point, aabbMin, aabbMax);
    
    let diff = point - closestPoint;
    return dot(diff, diff);
}

fn testSphereAABB(lightPos: vec3f, lightRadius: f32, aabbMin: vec3f, aabbMax: vec3f) -> bool {
    let center = (camera.viewMat * vec4f(lightPos, 1.0)).xyz;

    let squaredDistance = sqDistPointAABB(center, aabbMin, aabbMax);
    
    return squaredDistance <= (lightRadius * lightRadius);
}

@compute @workgroup_size(1, 1, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ------------------------------------
    // Calculating cluster bounds:
    // ------------------------------------
    // For each cluster (X, Y, Z):
    //     - Calculate the screen-space bounds for this cluster in 2D (XY).
    //     - Calculate the depth bounds for this cluster in Z (near and far planes).
    //     - Convert these screen and depth bounds into view-space coordinates.
    //     - Store the computed bounding box (AABB) for the cluster.

    let eyePos = vec3f(0.0);

    let tile_index = global_id.z * (CLUSTER_X * CLUSTER_Y) + global_id.y * CLUSTER_X + global_id.x;
    let tile_size_px = camera.screenSize / vec2f(f32(CLUSTER_X), f32(CLUSTER_Y)); // size of a single tile in pixels

    let maxPoint_sS = vec4f(vec2f(f32(global_id.x + 1u), f32(global_id.y + 1u)) * tile_size_px, -1.0, 1.0);
    let minPoint_sS = vec4f(vec2f(f32(global_id.x), f32(global_id.y)) * tile_size_px, -1.0, 1.0);

    let maxPoint_vS = screen2View(maxPoint_sS).xyz;
    let minPoint_vS = screen2View(minPoint_sS).xyz;

    let tileNear = -camera.near * pow(camera.far / camera.near, f32(global_id.z) / f32(CLUSTER_Z));
    let tileFar = -camera.near * pow(camera.far / camera.near, f32(global_id.z + 1u) / f32(CLUSTER_Z));

    let minPointNear = lineIntersectionToZPlane(eyePos, minPoint_vS, tileNear);
    let minPointFar = lineIntersectionToZPlane(eyePos, minPoint_vS, tileFar);
    let maxPointNear = lineIntersectionToZPlane(eyePos, maxPoint_vS, tileNear);
    let maxPointFar = lineIntersectionToZPlane(eyePos, maxPoint_vS, tileFar);

    let minPointAABB = min(min(minPointNear, minPointFar), min(maxPointNear, maxPointFar));
    let maxPointAABB = max(max(minPointNear, minPointFar), max(maxPointNear, maxPointFar));

    clusterSet.clusters[tile_index].minPoint = vec4f(minPointAABB, 0.0);
    clusterSet.clusters[tile_index].maxPoint = vec4f(maxPointAABB, 0.0);

    // ------------------------------------
    // Assigning lights to clusters:
    // ------------------------------------
    // For each cluster:
    //     - Initialize a counter for the number of lights in this cluster.

    //     For each light:
    //         - Check if the light intersects with the cluster's bounding box (AABB).
    //         - If it does, add the light to the cluster's light list.
    //         - Stop adding lights if the maximum number of lights is reached.

    //     - Store the number of lights assigned to this cluster.

    var count : u32 = 0;

    for (var i:u32 = 0u; i < lightSet.numLights; i = i + 1u){
        let light = lightSet.lights[i];

        if (testSphereAABB(light.pos, ${lightRadius}, minPointAABB, maxPointAABB)){
            clusterSet.clusters[tile_index].lightIndices[count] = i;
            count = count + 1u;

            if (count >= MAX_LIGHTS_PER_CLUSTER){
                break;
            }
        }
    }

    clusterSet.clusters[tile_index].numLights = count;
}

