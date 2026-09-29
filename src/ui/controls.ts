import { PARAMETER_LIMITS, setParameter, type NumericParameter, type Parameters } from '../physics/parameters.ts';

export function bindControls(parameters: Parameters): { sync: () => void; dispose: () => void } {
  const controller = new AbortController();
  const controls = (Object.keys(PARAMETER_LIMITS) as NumericParameter[]).map((key) => {
    const input = document.querySelector<HTMLInputElement>(`[data-parameter="${key}"]`)!;
    const [min, max] = PARAMETER_LIMITS[key];
    input.min = String(min);
    input.max = String(max);
    input.value = String(parameters[key]);
    input.addEventListener('input', () => {
      setParameter(parameters, key, input.valueAsNumber);
    }, { signal: controller.signal });
    input.addEventListener('blur', () => { input.value = String(parameters[key]); }, { signal: controller.signal });
    return { input, key };
  });
  const syncSizeControls = (): void => {
    for (const { input, key } of controls) {
      if (key === 'renderWidth' || key === 'renderHeight') input.disabled = parameters.fitWindow;
    }
  };
  syncSizeControls();
  for (const key of ['fitWindow', 'prepass', 'frequencyShift', 'postProcessing', 'taa', 'bloom'] as const) {
    const input = document.querySelector<HTMLInputElement>(`[data-toggle="${key}"]`)!;
    input.checked = parameters[key];
    input.addEventListener('change', () => {
      parameters[key] = input.checked;
      if (key === 'fitWindow') syncSizeControls();
    }, { signal: controller.signal });
  }
  const view = document.querySelector<HTMLSelectElement>('#debug-view')!;
  const background = document.querySelector<HTMLSelectElement>('#background')!;
  background.value = parameters.background;
  background.addEventListener('change', () => {
    if (background.value === 'sky' || background.value === 'grid') parameters.background = background.value;
  }, { signal: controller.signal });
  const presets = document.querySelector<HTMLSelectElement>('#preset')!;
  const combinations: Record<string, readonly [number, number]> = {
    schwarzschild: [0, 0], kerr: [0.95, 0], kn: [0.8, 0.4],
  };
  const syncPreset = (): void => {
    presets.value = Object.entries(combinations).find(([, [spin, charge]]) =>
      parameters.spin === spin && parameters.charge === charge)?.[0] ?? 'custom';
  };
  presets.addEventListener('change', () => {
    const combination = combinations[presets.value];
    if (!combination) return;
    [parameters.spin, parameters.charge] = combination;
    for (const { input, key } of controls) input.value = String(parameters[key]);
  }, { signal: controller.signal });
  syncPreset();
  view.value = String(parameters.debugView);
  view.addEventListener('change', () => {
    const value = Number(view.value);
    if (value === 0 || value === 1 || value === 2 || value === 3 || value === 4 || value === 5) parameters.debugView = value;
  }, { signal: controller.signal });
  return {
    sync: () => {
      syncPreset();
      for (const { input, key } of controls) {
        if (document.activeElement !== input) input.value = String(Math.round(parameters[key] * 1000) / 1000);
      }
    },
    dispose: () => controller.abort(),
  };
}
