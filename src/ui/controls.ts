import { PARAMETER_LIMITS, applyEmissionPreset, setParameter, type NumericParameter, type Parameters } from '../physics/parameters.ts';

export function bindControls(parameters: Parameters, actions: { boost?: (direction: 'look' | 'velocity') => boolean } = {}): { sync: () => void; dispose: () => void } {
  const controller = new AbortController();
  const diagnostic = document.querySelector<HTMLSelectElement>('#native-debug')!;
  diagnostic.value = String(parameters.nativeDebug);
  diagnostic.addEventListener('change', () => {
    const value = Number(diagnostic.value);
    if (value === 0 || value === 1 || value === 2 || value === 3 || value === 4 || value === 5 || value === 6) {
      parameters.nativeDebug = value;
      parameters.debugView = 3;
      document.querySelector<HTMLSelectElement>('#debug-view')!.value = '3';
    }
  }, { signal: controller.signal });
  const grid = document.querySelector<HTMLSelectElement>('#spatial-grid')!;
  grid.value = String(parameters.spatialGrid);
  grid.addEventListener('change', () => {
    const mode = Number(grid.value);
    if (mode === -1 || mode === 0 || mode === 1 || mode === 2) parameters.spatialGrid = mode;
  }, { signal: controller.signal });
  const observer = document.querySelector<HTMLSelectElement>('#observer-mode')!;
  const syncObserver = (): void => {
    observer.value = String(parameters.observerMode);
    for (const button of document.querySelectorAll<HTMLButtonElement>('[data-boost]')) button.disabled = parameters.observerMode !== -1;
  };
  syncObserver();
  for (const key of ['observerThrust','boostRapidity'] as const) {
    const input = document.querySelector<HTMLInputElement>(`[data-parameter="${key}"]`)!;
    input.value = String(parameters[key]);
    input.addEventListener('input', () => {
      const value = Math.fround(input.valueAsNumber);
      if (Number.isFinite(value) && (key !== 'observerThrust' || value >= 0)) parameters[key] = value;
    }, { signal: controller.signal });
    input.addEventListener('blur', () => { input.value = String(parameters[key]); }, { signal: controller.signal });
  }
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-boost]')) button.addEventListener('click', () => {
    const direction = button.dataset.boost === 'look' ? 'look' : 'velocity';
    const ok = actions.boost?.(direction) ?? false;
    document.querySelector<HTMLElement>('#boost-status')!.textContent = ok ? '已施加瞬时加速。' : '未施加：请启用四维模式并使用可计算的快度。';
  }, { signal: controller.signal });
  observer.addEventListener('change', () => {
    const mode = Number(observer.value);
    if (mode === -1 || mode === 0 || mode === 1 || mode === 2 || mode === 3) parameters.observerMode = mode;
    syncObserver();
  }, { signal: controller.signal });
  for (const key of ['universeSign','universeIndex'] as const) {
    const input = document.querySelector<HTMLSelectElement>(`[data-extension="${key}"]`)!;
    input.value = String(parameters[key]);
    input.addEventListener('change', () => {
      const value = Number(input.value);
      if (key === 'universeSign' && (value === -1 || value === 1)) parameters.universeSign = value;
      if (key === 'universeIndex' && (value === 0 || value === 1 || value === 2)) parameters.universeIndex = value;
    }, { signal: controller.signal });
  }
  const controls = (Object.keys(PARAMETER_LIMITS) as NumericParameter[]).map((key) => {
    const input = document.querySelector<HTMLInputElement>(`[data-parameter="${key}"]`)!;
    const [min, max] = PARAMETER_LIMITS[key];
    if (Number.isFinite(min)) input.min = String(min); else input.removeAttribute('min');
    if (Number.isFinite(max)) input.max = String(max); else input.removeAttribute('max');
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
  for (const key of ['maximalExtension', 'specializeExtension', 'denseStarEnabled', 'diskEnabled', 'jetEnabled', 'manualVelocity', 'fitWindow', 'prepass', 'frequencyShift', 'postProcessing', 'taa', 'bloom'] as const) {
    const input = document.querySelector<HTMLInputElement>(`[data-toggle="${key}"]`)!;
    input.checked = parameters[key];
    input.addEventListener('change', () => {
      parameters[key] = input.checked;
      if (key === 'fitWindow') syncSizeControls();
    }, { signal: controller.signal });
  }
  document.querySelector<HTMLButtonElement>('#emission-preset')!.addEventListener('click', () => {
    applyEmissionPreset(parameters);
    for (const { input, key } of controls) input.value = String(parameters[key]);
    for (const key of ['diskEnabled','jetEnabled'] as const) {
      document.querySelector<HTMLInputElement>(`[data-toggle="${key}"]`)!.checked = parameters[key];
    }
  }, { signal: controller.signal });
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
    if (value === 4) { parameters.nativeDebug = 3; diagnostic.value = '3'; }
  }, { signal: controller.signal });
  return {
    sync: () => {
      syncPreset();
      syncObserver();
      for (const key of ['universeSign','universeIndex'] as const) {
        const input = document.querySelector<HTMLSelectElement>(`[data-extension="${key}"]`)!;
        if (document.activeElement !== input) input.value = String(parameters[key]);
      }
      grid.value = String(parameters.spatialGrid);
      diagnostic.value = String(parameters.nativeDebug);
      for (const key of ['observerThrust','boostRapidity'] as const) {
        const input = document.querySelector<HTMLInputElement>(`[data-parameter="${key}"]`)!;
        if (document.activeElement !== input) input.value = String(parameters[key]);
      }
      for (const { input, key } of controls) {
        if (document.activeElement !== input) input.value = String(parameters[key]);
      }
    },
    dispose: () => controller.abort(),
  };
}
