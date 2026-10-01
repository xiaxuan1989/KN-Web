import { createCubeFace } from './cubemap-data.ts';
import { loadUniverseFaces, SKYBOX_NAMES } from './cubemap-loader.ts';
import mipShader from '../shaders/cubemap-mip.wgsl?raw';

export type BackgroundKind = 'sky' | 'grid';

export class Background {
  readonly layout: GPUBindGroupLayout;
  private readonly textures: GPUTexture[] = [];
  private readonly groups = new Map<BackgroundKind, GPUBindGroup>();
  private readonly device: GPUDevice;

  private constructor(device: GPUDevice) {
    this.device = device;
    this.layout = device.createBindGroupLayout({ entries: [
      { binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: { viewDimension: 'cube' } },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
      ...[2,3,4,5,6].map(binding => ({ binding, visibility: GPUShaderStage.FRAGMENT, texture: { viewDimension: 'cube' as const } })),
    ] });
  }

  static async create(device: GPUDevice, signal: AbortSignal, onProgress: (count: number) => void): Promise<Background> {
    const faces = await loadUniverseFaces(`${import.meta.env.BASE_URL}cubemaps/`,
      device.limits.maxTextureDimension2D,signal,onProgress);
    let background: Background | undefined;
    try {
      background = new Background(device);
      signal.throwIfAborted();
      device.pushErrorScope('validation');
      try {
        // NPGS uses R8G8B8A8Unorm and flipVertically=false, not an sRGB view.
        const skies = SKYBOX_NAMES.map((name,index) => {
          const sky = background!.allocate(name,faces[index*6].width);
          faces.slice(index*6,index*6+6).forEach((source,face) => device.queue.copyExternalImageToTexture(
            { source, flipY: false },{ texture: sky,origin: [0,0,face],premultipliedAlpha: false },
            [source.width,source.height,1],
          ));
          return sky;
        });
        const grid = background.allocate('grid', 256);
        background.createGroup('sky',skies);
        background.createGroup('grid',Array(6).fill(grid));
        for (let face = 0; face < 6; face++) {
          device.queue.writeTexture({ texture: grid, origin: [0, 0, face] }, createCubeFace(face, 256),
            { bytesPerRow: 1024, rowsPerImage: 256 }, [256, 256, 1]);
        }
        await background.generateMips(signal);
      } finally {
        const error = await device.popErrorScope();
        if (error) throw new Error(`星空 GPU 上传失败：${error.message}`);
      }
      signal.throwIfAborted();
      return background;
    } catch (error) {
      background?.dispose();
      throw error;
    } finally {
      faces.forEach((face) => face.close());
    }
  }

  private allocate(kind: string, size: number): GPUTexture {
    const texture = this.device.createTexture({ label: `${kind} cubemap`, size: [size, size, 6],
      mipLevelCount: 2, format: 'rgba8unorm',
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT });
    this.textures.push(texture);
    return texture;
  }

  private createGroup(kind: BackgroundKind, skies: GPUTexture[]): void {
    const bindings = [0,2,3,4,5,6];
    this.groups.set(kind,this.device.createBindGroup({ layout:this.layout,entries: [
      ...skies.map((texture,index) => ({binding:bindings[index],resource:texture.createView({dimension:'cube'})})),
      {binding:1,resource:this.device.createSampler({minFilter:'linear',magFilter:'linear',mipmapFilter:'linear',lodMinClamp:0,lodMaxClamp:1})},
    ] }));
  }

  private async generateMips(signal: AbortSignal): Promise<void> {
    const module = this.device.createShaderModule({ label: 'Cubemap mip 1', code: mipShader });
    const pipeline = await this.device.createRenderPipelineAsync({ layout: 'auto',
      vertex: { module, entryPoint: 'vs_main' },
      fragment: { module, entryPoint: 'fs_main', targets: [{ format: 'rgba8unorm' }] },
    });
    signal.throwIfAborted();
    const encoder = this.device.createCommandEncoder({ label: 'Cubemap downsample' });
    for (const texture of this.textures) for (let face = 0; face < 6; face++) {
      const view = { dimension: '2d' as const, baseArrayLayer: face, arrayLayerCount: 1, mipLevelCount: 1 };
      const group = this.device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [
        { binding: 0, resource: texture.createView({ ...view, baseMipLevel: 0 }) },
      ] });
      const pass = encoder.beginRenderPass({ colorAttachments: [{
        view: texture.createView({ ...view, baseMipLevel: 1 }), loadOp: 'clear', storeOp: 'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      }] });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, group);
      pass.draw(3);
      pass.end();
    }
    this.device.queue.submit([encoder.finish()]);
    await this.device.queue.onSubmittedWorkDone();
  }

  bindGroup(kind: BackgroundKind): GPUBindGroup { return this.groups.get(kind)!; }
  dispose(): void { this.textures.forEach((texture) => texture.destroy()); }
}
