import commonShader from '../shaders/common.wgsl?raw';
import verificationShader from '../shaders/verify-uniforms.wgsl?raw';
import { UniformData, UNIFORM_SIZES } from './uniform-layout.ts';

export class UniformBuffers {
  readonly data = new UniformData();
  readonly layout: GPUBindGroupLayout;
  readonly bindGroup: GPUBindGroup;
  private readonly buffers: GPUBuffer[];
  private readonly device: GPUDevice;

  constructor(device: GPUDevice) {
    this.device = device;
    this.buffers = UNIFORM_SIZES.map((size, binding) => device.createBuffer({
      label: ['GameArgs', 'BlackHoleArgs', 'CameraArgs'][binding],
      size, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    }));
    this.layout = device.createBindGroupLayout({
      label: 'Frame / black hole / camera uniforms',
      entries: UNIFORM_SIZES.map((minBindingSize, binding) => ({
        binding, visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.COMPUTE,
        buffer: { type: 'uniform', minBindingSize },
      })),
    });
    this.bindGroup = device.createBindGroup({
      layout: this.layout,
      entries: this.buffers.map((buffer, binding) => ({ binding, resource: { buffer } })),
    });
  }

  upload(): void {
    [this.data.game, this.data.blackHole, this.data.camera].forEach((values, index) => {
      this.device.queue.writeBuffer(this.buffers[index], 0, values);
    });
  }

  async verify(): Promise<number> {
    const device = this.device;
    const outputLayout = device.createBindGroupLayout({ entries: [{
      binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage', minBindingSize: 224 },
    }] });
    const pipeline = await device.createComputePipelineAsync({
      layout: device.createPipelineLayout({ bindGroupLayouts: [this.layout, outputLayout] }),
      compute: {
        module: device.createShaderModule({ label: 'Uniform ABI verification', code: commonShader + verificationShader }),
        entryPoint: 'verify_uniforms',
      },
    });
    const output = device.createBuffer({ size: 224, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC });
    const readback = device.createBuffer({ size: 224, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
    try {
      // Capture immediately before submission, without await: later frames cannot
      // overwrite this snapshot before the verification dispatch enters the queue.
      const expected = this.data.expectedReadback();
      this.upload();
      const encoder = device.createCommandEncoder();
      const pass = encoder.beginComputePass();
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, this.bindGroup);
      pass.setBindGroup(1, device.createBindGroup({ layout: outputLayout, entries: [{ binding: 0, resource: { buffer: output } }] }));
      pass.dispatchWorkgroups(1);
      pass.end();
      encoder.copyBufferToBuffer(output, 0, readback, 0, 224);
      device.queue.submit([encoder.finish()]);
      await readback.mapAsync(GPUMapMode.READ);
      const actual = new Float32Array(readback.getMappedRange());
      for (let index = 0; index < expected.length; index++) {
        if (!Number.isFinite(actual[index]) || Math.abs(actual[index] - expected[index]) > 1e-6 * Math.max(1, Math.abs(expected[index]))) {
          throw new Error(`Uniform 回读不一致：word ${index}，CPU=${expected[index]}，GPU=${actual[index]}`);
        }
      }
      return expected.length;
    } finally {
      readback.destroy();
      output.destroy();
    }
  }

  dispose(): void {
    this.buffers.forEach((buffer) => buffer.destroy());
  }
}
