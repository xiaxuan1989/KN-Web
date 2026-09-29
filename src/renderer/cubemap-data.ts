// WebGPU cube face order: +X, -X, +Y, -Y, +Z, -Z. V increases downward.
export function cubeDirection(face: number, u: number, v: number): [number, number, number] {
  const directions: [number, number, number][] = [[1,-v,-u],[-1,-v,u],[u,1,v],[u,-1,-v],[u,-v,1],[-u,-v,-1]];
  const direction = directions[face];
  const length = Math.hypot(...direction);
  return direction.map((value) => value / length) as [number, number, number];
}

// Diagnostic longitude/latitude chart. A real six-face cube texture, not a
// claimed astronomical star map. Phase 3 will load the original sky assets.
export function createCubeFace(face: number, size: number): Uint8Array<ArrayBuffer> {
  const data = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const [dx, dy, dz] = cubeDirection(face, 2 * (x + 0.5) / size - 1, 2 * (y + 0.5) / size - 1);
    const longitude = Math.atan2(dz, dx) / (2 * Math.PI) + 0.5;
    const latitude = Math.asin(dy) / Math.PI + 0.5;
    const horizontal = longitude * 24, vertical = latitude * 12;
    const grid = Math.min(horizontal % 1, 1 - horizontal % 1, vertical % 1, 1 - vertical % 1) < 0.035;
    const checker = (Math.floor(horizontal) + Math.floor(vertical)) % 2 === 0 ? 0.78 : 1;
    const tint = [0.25 + 0.65 * (dx * 0.5 + 0.5), 0.25 + 0.65 * (dy * 0.5 + 0.5), 0.25 + 0.65 * (dz * 0.5 + 0.5)];
    const offset = (y * size + x) * 4;
    for (let channel = 0; channel < 3; channel++) data[offset + channel] = Math.round(255 * (grid ? 0.08 : tint[channel] * checker));
    data[offset + 3] = 255;
  }
  return data;
}
