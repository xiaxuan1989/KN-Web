import type { Parameters } from '../physics/parameters.ts';

type PassName = 'taa' | 'bloom_atlas' | 'blur_h' | 'blur_v' | 'present';

export class PostProcessing {
  private readonly device: GPUDevice;
  private readonly layout: GPUBindGroupLayout;
  private readonly sampler: GPUSampler;
  private readonly uniform: GPUBuffer;
  private readonly pipelines = new Map<PassName, GPURenderPipeline>();
  private readonly groups = new Map<string, GPUBindGroup>();
  private readonly passBuffers = new Map<string, GPUBuffer>();
  private textures: GPUTexture[] = [];
  private history: GPUTexture[] = [];
  private bloomTargets: GPUTexture[] = [];
  private index = 0;
  private width = 0;
  private height = 0;
  scene!: GPUTexture;

  private constructor(device: GPUDevice) {
    this.device = device;
    this.uniform = device.createBuffer({ label: 'PostArgs', size: 32, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
    this.sampler = device.createSampler({ minFilter: 'linear', magFilter: 'linear', addressModeU: 'repeat', addressModeV: 'repeat' });
    this.layout = device.createBindGroupLayout({ entries: [
      { binding: 0, visibility: GPUShaderStage.FRAGMENT, buffer: { type: 'uniform', minBindingSize: 32 } },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: {} },
      { binding: 2, visibility: GPUShaderStage.FRAGMENT, texture: {} },
      { binding: 3, visibility: GPUShaderStage.FRAGMENT, sampler: {} },
      { binding: 4, visibility: GPUShaderStage.FRAGMENT, buffer: { type: 'uniform', minBindingSize: 16 } },
    ] });
  }

  static async create(device: GPUDevice, format: GPUTextureFormat, code: string): Promise<PostProcessing> {
    const post = new PostProcessing(device);
    try {
      const module = device.createShaderModule({ label: 'TAA / Bloom / NPGS display mapping', code });
      const info = await module.getCompilationInfo();
      const errors = info.messages.filter(message => message.type === 'error');
      if (errors.length) throw new Error(errors.map(m => `Post WGSL ${m.lineNum}:${m.linePos} ${m.message}`).join('\n'));
      const layout = device.createPipelineLayout({ bindGroupLayouts: [post.layout] });
      const entries: PassName[] = ['taa', 'bloom_atlas', 'blur_h', 'blur_v', 'present'];
      // Finish all pending pipeline builds even if one fails before releasing resources.
      const results = await Promise.allSettled(entries.map(async entry => {
        const pipeline = await device.createRenderPipelineAsync({ label: entry, layout,
          vertex: { module, entryPoint: 'vs_main' },
          fragment: { module, entryPoint: entry, targets: [{ format: entry === 'present' ? format : 'rgba16float' }] },
        });
        post.pipelines.set(entry, pipeline);
      }));
      for (const result of results) if (result.status === 'rejected') throw result.reason;
      return post;
    } catch (error) { post.dispose(); throw error; }
  }

  resize(width: number, height: number): boolean {
    if (width === this.width && height === this.height) return false;
    this.releaseTargets();
    this.width = width; this.height = height; this.index = 0;
    const allocate = (label: string, w: number, h: number): GPUTexture => {
      const texture = this.device.createTexture({ label, size: [w, h], format: 'rgba16float',
        usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING });
      this.textures.push(texture);
      return texture;
    };
    this.scene = allocate('HDR current', width, height);
    this.history = [allocate('HDR history A', width, height), allocate('HDR history B', width, height)];
    this.bloomTargets = [allocate('Bloom atlas',width,height), allocate('Bloom horizontal',width,height)];
    return true;
  }

  encode(encoder: GPUCommandEncoder, target: GPUTextureView, p: Parameters, weight: number, active: boolean): void {
    const bloom = active && p.bloom && p.bloomStrength > 0;
    this.device.queue.writeBuffer(this.uniform, 0, new Float32Array([
      p.exposure, p.gamma, p.bloomStrength, 0, weight, 0, Number(bloom), Number(active),
    ]));
    let resolved = this.scene;
    if (active && p.taa) {
      resolved = this.history[this.index];
      this.draw(encoder,'taa',this.scene,this.history[1-this.index],resolved.createView());
      this.index = 1-this.index;
    }
    let glow = resolved;
    if (bloom) {
      const [atlas,horizontal] = this.bloomTargets;
      this.draw(encoder,'bloom_atlas',resolved,resolved,atlas.createView());
      this.draw(encoder,'blur_h',atlas,atlas,horizontal.createView());
      this.draw(encoder,'blur_v',horizontal,horizontal,atlas.createView());
      glow = atlas;
    }
    this.draw(encoder,'present',resolved,glow,target);
  }

  private draw(encoder: GPUCommandEncoder, name: PassName, source: GPUTexture, auxiliary: GPUTexture,
    target: GPUTextureView, x = 0, y = 0): void {
    const infoKey = `${x},${y}`;
    let info = this.passBuffers.get(infoKey);
    if (!info) {
      info = this.device.createBuffer({ label: `Post pass ${infoKey}`, size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
      this.device.queue.writeBuffer(info,0,new Float32Array([x,y,0,0]));
      this.passBuffers.set(infoKey,info);
    }
    const key = `${source.label}|${auxiliary.label}|${infoKey}`;
    let group = this.groups.get(key);
    if (!group) {
      group = this.device.createBindGroup({ layout: this.layout, entries: [
        { binding: 0, resource: { buffer: this.uniform } }, { binding: 1, resource: source.createView() },
        { binding: 2, resource: auxiliary.createView() }, { binding: 3, resource: this.sampler },
        { binding: 4, resource: { buffer: info } },
      ] });
      this.groups.set(key,group);
    }
    const pass = encoder.beginRenderPass({ label: name, colorAttachments: [{ view: target,
      clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: 'clear', storeOp: 'store' }] });
    pass.setPipeline(this.pipelines.get(name)!);
    pass.setBindGroup(0,group);
    pass.draw(3);
    pass.end();
  }

  private releaseTargets(): void {
    this.textures.forEach(t => t.destroy()); this.textures = [];
    this.passBuffers.forEach(b => b.destroy()); this.passBuffers.clear(); this.groups.clear();
    this.history = []; this.bloomTargets = [];
  }
  dispose(): void { this.releaseTargets(); this.uniform.destroy(); }
}
