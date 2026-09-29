// FTextureCube::LoadImage in NPGS Texture.cpp: Vulkan/WebGPU cube layer order.
export const CUBE_FILES = ['PosX.jpg', 'NegX.jpg', 'PosY.jpg', 'NegY.jpg', 'PosZ.jpg', 'NegZ.jpg'] as const;

export async function loadCubeFaces(
  baseUrl: string,
  maxDimension: number,
  signal: AbortSignal,
  onProgress: (completed: number) => void = () => {},
): Promise<ImageBitmap[]> {
  let completed = 0;
  // Settle every decode before cleanup: a slower face must not leak after another fails.
  const results = await Promise.allSettled(CUBE_FILES.map(async (name) => {
    signal.throwIfAborted();
    const response = await fetch(`${baseUrl}${name}`, { signal });
    if (!response.ok) throw new Error(`星空 ${name} 加载失败：HTTP ${response.status}`);
    const bitmap = await createImageBitmap(await response.blob(), {
      imageOrientation: 'none', premultiplyAlpha: 'none', colorSpaceConversion: 'none',
    });
    try {
      signal.throwIfAborted();
      onProgress(++completed);
      return bitmap;
    } catch (error) {
      bitmap.close();
      throw error;
    }
  }));
  const faces = results.flatMap((r) => r.status === 'fulfilled' ? [r.value] : []);
  try {
    signal.throwIfAborted();
    const failure = results.find((r) => r.status === 'rejected');
    if (failure?.status === 'rejected') throw failure.reason;
    const size = faces[0].width;
    if (size < 2 || size > maxDimension || faces.some((face) => face.width !== size || face.height !== size)) {
      throw new Error(`星空六面必须为相同尺寸的正方形，边长 2–${maxDimension} px。`);
    }
    return faces;
  } catch (error) {
    faces.forEach((face) => face.close());
    throw error;
  }
}
