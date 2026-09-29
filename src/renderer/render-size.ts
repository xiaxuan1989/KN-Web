// Window size (or an explicit fixed size), without Retina/DPR multiplication.
export function renderSize(width: number, height: number, limit: number) {
  const scale = Math.min(1, limit / Math.max(width, height));
  const full: [number, number] = [Math.max(1, Math.floor(width * scale)), Math.max(1, Math.floor(height * scale))];
  const half: [number, number] = full.map(value => Math.max(1, Math.floor(value / 2))) as [number, number];
  return { full, half };
}
