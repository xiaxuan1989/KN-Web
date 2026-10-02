import type { Parameters } from '../physics/parameters.ts';

type GridMode = Parameters['spatialGrid'];
const GRID_MODES: readonly GridMode[] = [-1, 0, 1, 2];

export class ScenePasses {
  readonly prepassLayout: GPUBindGroupLayout;
  private readonly device: GPUDevice;
  private readonly pipelines = new Map<string, GPURenderPipeline[]>();
  private readonly diagnosticPipelines = new Map<string, Partial<Record<string, GPURenderPipeline>>>();
  private textures: GPUTexture[] = [];
  private group?: GPUBindGroup;
  private size = '';

  private constructor(device: GPUDevice) {
    this.device = device;
    this.prepassLayout = device.createBindGroupLayout({ entries: [0,1].map(binding => ({
      binding, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'unfilterable-float' },
    })) });
  }

  static async create(device: GPUDevice, uniforms: GPUBindGroupLayout, background: GPUBindGroupLayout, code: string): Promise<ScenePasses> {
    const scene = new ScenePasses(device);
    const module = device.createShaderModule({ label: 'NPGS prepass / composite / full trace', code });
    const info = await module.getCompilationInfo();
    const errors = info.messages.filter(m => m.type === 'error');
    if (errors.length) throw new Error(errors.map(m => `WGSL ${m.lineNum}:${m.linePos} ${m.message}`).join('\n'));
    const configs = [
      { entry: 'fs_main', layouts: [uniforms,background], formats: ['rgba16float'] },
      { entry: 'fs_prepass', layouts: [uniforms], formats: ['rgba32float','rgba16float'] },
      { entry: 'fs_composite', layouts: [uniforms,background,scene.prepassLayout], formats: ['rgba16float'] },
    ];
    // Cache the dynamic path plus an extension-off variant for ordinary rendering.
    // Keep dynamic diagnostics available wherever specialization is not selected.
    // Every pass switches together, without compiling during interaction.
    const referenceVariants = GRID_MODES.flatMap(mode => [false,true].flatMap(diagnostics =>
      [false,true].flatMap(radiation => (diagnostics ? [true] : [false,true]).flatMap(extension =>
        configs.map(config => ({ mode, diagnostics, radiation, extension, diagnostic: -1, ...config }))))));
    // Full trace stays on the dynamic reference. Diagnostic 6 specializes only
    // its prepass without radiation; keep derivative-based composite colors intact.
    const optimizedVariants = GRID_MODES.flatMap(mode => [false,true].flatMap(radiation =>
      [3,6].flatMap(diagnostic => configs.filter(config =>
        diagnostic === 3 ? config.entry !== 'fs_main' : !radiation && config.entry === 'fs_prepass')
        .map(config => ({ mode, diagnostics: true, radiation, extension: true, diagnostic, ...config })))));
    const variants = [...referenceVariants,...optimizedVariants];
    const results = await Promise.allSettled(variants.map(async config => device.createRenderPipelineAsync({
      label: `${config.entry} / grid ${config.mode} / diagnostics ${config.diagnostics} / radiation ${config.radiation} / extension ${config.extension} / diagnostic ${config.diagnostic}`, layout: device.createPipelineLayout({ bindGroupLayouts: config.layouts }),
      vertex: { module, entryPoint: 'vs_main' },
      fragment: { module, entryPoint: config.entry, constants: {
        SPATIAL_GRID_MODE: config.mode, DIAGNOSTICS_ENABLED: Number(config.diagnostics), RADIATION_ENABLED: Number(config.radiation),
        MAXIMAL_EXTENSION_MODE: Number(config.extension), DIAGNOSTIC_MODE: config.diagnostic,
      },
        targets: config.formats.map(format => ({ format: format as GPUTextureFormat })) },
    })));
    for (const result of results) if (result.status === 'rejected') throw result.reason;
    for (let index = 0; index < referenceVariants.length; index += configs.length) {
      const { mode, diagnostics, radiation, extension } = variants[index];
      scene.pipelines.set(`${mode},${diagnostics},${radiation},${extension}`,
        results.slice(index,index+configs.length).map(result => (result as PromiseFulfilledResult<GPURenderPipeline>).value));
    }
    optimizedVariants.forEach((config,index) => {
      const key = `${config.mode},${config.radiation},${config.diagnostic}`;
      const pipelines = scene.diagnosticPipelines.get(key) ?? {};
      pipelines[config.entry] = (results[referenceVariants.length+index] as PromiseFulfilledResult<GPURenderPipeline>).value;
      scene.diagnosticPipelines.set(key,pipelines);
    });
    return scene;
  }

  resize(width: number,height: number): void {
    const size = `${width},${height}`;
    if (this.size === size) return;
    this.dispose(); this.size = size;
    this.textures = (['rgba32float','rgba16float'] as const).map((format,index) => this.device.createTexture({
      label: index === 0 ? 'Prepass direction × shift / status' : 'Prepass accumulated color',
      size: [width,height], format, usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    }));
    this.group = this.device.createBindGroup({ layout: this.prepassLayout, entries: this.textures.map((texture,binding) => ({ binding, resource: texture.createView() })) });
  }

  encode(encoder: GPUCommandEncoder, target: GPUTextureView, full: GPUBindGroup, half: GPUBindGroup, background: GPUBindGroup, usePrepass: boolean, lensView = false, gridMode: GridMode = 0, diagnostics = false, radiation = false, extension = false, specializeExtension = true, diagnosticMode: Parameters['nativeDebug'] = 0, specializeDiagnostics = true): void {
    // The dynamic variant also provides a like-for-like comparison while off.
    const dynamicExtension = extension || diagnostics || !specializeExtension;
    const pipelines = this.pipelines.get(`${gridMode},${diagnostics},${radiation},${dynamicExtension}`)!;
    const optimized = specializeDiagnostics && diagnostics && usePrepass && !extension
      ? this.diagnosticPipelines.get(`${gridMode},${radiation},${diagnosticMode}`) : undefined;
    if (usePrepass) {
      const pass = encoder.beginRenderPass({ label: 'Half resolution KN prepass', colorAttachments: this.textures.map(texture => ({
        view: texture.createView(), clearValue: { r: 0,g: 0,b: 0,a: 0 }, loadOp: 'clear', storeOp: 'store',
      })) });
      pass.setPipeline(optimized?.fs_prepass ?? pipelines[1]); pass.setBindGroup(0,half); pass.draw(3); pass.end();
    }
    const pass = encoder.beginRenderPass({ label: usePrepass ? 'Full resolution KN composite' : 'Full resolution trace / diagnostic',
      colorAttachments: [{ view: target, clearValue: { r: 0,g: 0,b: 0,a: 1 }, loadOp: 'clear', storeOp: 'store' }],
    });
    pass.setPipeline((usePrepass || lensView ? optimized?.fs_composite : undefined) ?? pipelines[usePrepass || lensView ? 2 : 0]); pass.setBindGroup(0,full); pass.setBindGroup(1,background);
    if (usePrepass || lensView) pass.setBindGroup(2,this.group!);
    pass.draw(3); pass.end();
  }

  dispose(): void { this.textures.forEach(texture => texture.destroy()); this.textures = []; this.group = undefined; this.size = ''; }
}
