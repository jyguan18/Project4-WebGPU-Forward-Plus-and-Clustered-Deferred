import * as renderer from "../renderer";
import * as shaders from "../shaders/shaders";
import { Stage } from "../stage/stage";

export class ClusteredDeferredRenderer extends renderer.Renderer {
  // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
  // you may need extra uniforms such as the camera view matrix and the canvas resolution

  sceneUniformsBindGroupLayout: GPUBindGroupLayout;
  sceneUniformsBindGroup: GPUBindGroup;

  depthTexture: GPUTexture;
  depthTextureView: GPUTextureView;

  pipeline: GPURenderPipeline;

  gBufferBindGroupLayout: GPUBindGroupLayout;
  gBufferBindGroup: GPUBindGroup;

  gBuffer: {
    albedo: GPUTexture;
    normal: GPUTexture;
    position: GPUTexture;
  };

  gBufferView: {
    albedoView: GPUTextureView;
    normalView: GPUTextureView;
    positionView: GPUTextureView;
  };

  gBufferPipeline: GPURenderPipeline;
  fullScreenPipeline: GPURenderPipeline;

  constructor(stage: Stage) {
    super(stage);

    // TODO-3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
    // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass

    this.sceneUniformsBindGroupLayout = renderer.device.createBindGroupLayout({
      label: "scene uniforms bind group layout",
      entries: [
        {
          // camera
          binding: 0,
          visibility:
            GPUShaderStage.VERTEX |
            GPUShaderStage.COMPUTE |
            GPUShaderStage.FRAGMENT,
          buffer: { type: "uniform" },
        },
        {
          // lightSet
          binding: 1,
          visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.COMPUTE,
          buffer: { type: "read-only-storage" },
        },
        {
          // clusterSet
          binding: 2,
          visibility: GPUShaderStage.FRAGMENT,
          buffer: { type: "storage" },
        },
      ],
    });

    this.sceneUniformsBindGroup = renderer.device.createBindGroup({
      label: "scene uniforms bind group",
      layout: this.sceneUniformsBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: this.camera.uniformsBuffer },
        },
        {
          binding: 1,
          resource: { buffer: this.lights.lightSetStorageBuffer },
        },
        {
          binding: 2,
          resource: { buffer: this.lights.clusterStorageBuffer },
        },
      ],
    });

    this.depthTexture = renderer.device.createTexture({
      size: [renderer.canvas.width, renderer.canvas.height],
      format: "depth24plus",
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
    });
    this.depthTextureView = this.depthTexture.createView();

    this.gBuffer = {
      albedo: renderer.device.createTexture({
        size: [renderer.canvas.width, renderer.canvas.height],
        format: "rgba16float",
        usage:
          GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
      }),
      normal: renderer.device.createTexture({
        size: [renderer.canvas.width, renderer.canvas.height],
        format: "rgba16float",
        usage:
          GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
      }),
      position: renderer.device.createTexture({
        size: [renderer.canvas.width, renderer.canvas.height],
        format: "rgba16float",
        usage:
          GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
      }),
    };

    this.gBufferView = {
      albedoView: this.gBuffer.albedo.createView(),

      normalView: this.gBuffer.normal.createView(),

      positionView: this.gBuffer.position.createView(),
    };

    this.gBufferBindGroupLayout = renderer.device.createBindGroupLayout({
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.FRAGMENT,
          texture: { sampleType: "float" },
        },
        {
          binding: 1,
          visibility: GPUShaderStage.FRAGMENT,
          texture: { sampleType: "float" },
        },
        {
          binding: 2,
          visibility: GPUShaderStage.FRAGMENT,
          texture: { sampleType: "float" },
        },
      ],
    });

    this.gBufferBindGroup = renderer.device.createBindGroup({
      label: "gbuffer bind group",
      layout: this.gBufferBindGroupLayout,
      entries: [
        { binding: 0, resource: this.gBufferView.albedoView },
        { binding: 1, resource: this.gBufferView.normalView },
        { binding: 2, resource: this.gBufferView.positionView },
      ],
    });

    this.gBufferPipeline = renderer.device.createRenderPipeline({
      layout: renderer.device.createPipelineLayout({
        label: "gbuffer pipeline layout",
        bindGroupLayouts: [
          this.sceneUniformsBindGroupLayout,
          renderer.modelBindGroupLayout,
          renderer.materialBindGroupLayout,
        ],
      }),
      depthStencil: {
        depthWriteEnabled: true,
        depthCompare: "less",
        format: "depth24plus",
      },
      vertex: {
        module: renderer.device.createShaderModule({
          label: "deferred vert shader",
          code: shaders.naiveVertSrc,
        }),
        buffers: [renderer.vertexBufferLayout],
      },
      fragment: {
        module: renderer.device.createShaderModule({
          label: "deferred frag shader",
          code: shaders.clusteredDeferredFragSrc,
        }),
        targets: [
          { format: "rgba16float" }, // albedo
          { format: "rgba16float" }, // normal
          { format: "rgba16float" }, // position
        ],
      },
    });

    this.fullScreenPipeline = renderer.device.createRenderPipeline({
      layout: renderer.device.createPipelineLayout({
        label: "fullscreen pipeline layout",
        bindGroupLayouts: [
          this.sceneUniformsBindGroupLayout,
          this.gBufferBindGroupLayout,
        ],
      }),
      vertex: {
        module: renderer.device.createShaderModule({
          label: "deferred vert shader",
          code: shaders.clusteredDeferredFullscreenVertSrc,
        }),
      },
      fragment: {
        module: renderer.device.createShaderModule({
          label: "full screen frag shader",
          code: shaders.clusteredDeferredFullscreenFragSrc,
        }),
        targets: [
          {
            format: renderer.canvasFormat,
          },
        ],
      },
    });
  }

  override draw() {
    // TODO-3: run the Forward+ rendering pass:
    // - run the clustering compute shader
    // - run the G-buffer pass, outputting position, albedo, and normals
    // - run the fullscreen pass, which reads from the G-buffer and performs lighting calculations
    const encoder = renderer.device.createCommandEncoder();

    this.lights.doLightClustering(encoder);

    const gBufferPass = encoder.beginRenderPass({
      label: "gbuffer render pass",
      colorAttachments: [
        {
          view: this.gBufferView.albedoView,
          clearValue: [0, 0, 0, 0],
          loadOp: "clear",
          storeOp: "store",
        },
        {
          view: this.gBufferView.normalView,
          clearValue: [0, 0, 0, 0],
          loadOp: "clear",
          storeOp: "store",
        },
        {
          view: this.gBufferView.positionView,
          clearValue: [0, 0, 0, 0],
          loadOp: "clear",
          storeOp: "store",
        },
      ],
      depthStencilAttachment: {
        view: this.depthTextureView,
        depthClearValue: 1.0,
        depthLoadOp: "clear",
        depthStoreOp: "store",
      },
    });

    gBufferPass.setPipeline(this.gBufferPipeline);

    gBufferPass.setBindGroup(
      shaders.constants.bindGroup_scene,
      this.sceneUniformsBindGroup
    );

    this.scene.iterate(
      (node) => {
        gBufferPass.setBindGroup(
          shaders.constants.bindGroup_model,
          node.modelBindGroup
        );
      },
      (material) => {
        gBufferPass.setBindGroup(
          shaders.constants.bindGroup_material,
          material.materialBindGroup
        );
      },
      (primitive) => {
        gBufferPass.setVertexBuffer(0, primitive.vertexBuffer);
        gBufferPass.setIndexBuffer(primitive.indexBuffer, "uint32");
        gBufferPass.drawIndexed(primitive.numIndices);
      }
    );

    gBufferPass.end();

    const canvasTextureView = renderer.context.getCurrentTexture().createView();
    const fullScreenPass = encoder.beginRenderPass({
      label: "fullscreen pass",
      colorAttachments: [
        {
          view: canvasTextureView,
          clearValue: [0, 0, 0, 0],
          loadOp: "clear",
          storeOp: "store",
        },
      ],
    });

    fullScreenPass.setPipeline(this.fullScreenPipeline);
    fullScreenPass.setBindGroup(
      shaders.constants.bindGroup_scene,
      this.sceneUniformsBindGroup
    );
    fullScreenPass.setBindGroup(
      shaders.constants.bindGroup_gBuffer,
      this.gBufferBindGroup
    );
    fullScreenPass.draw(3);
    fullScreenPass.end();
    renderer.device.queue.submit([encoder.finish()]);
  }
}
