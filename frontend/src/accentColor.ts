export const DEFAULT_ACCENT = '#007aff';
export type RGB = [number, number, number];

export function validAccent(value: unknown): value is string {
  return typeof value === 'string' && (value === '' || /^#[0-9a-f]{6}$/i.test(value));
}

export function accentRGB(color: string): RGB {
  const hex = color || DEFAULT_ACCENT;
  return [1, 3, 5].map((offset) => parseInt(hex.slice(offset, offset + 2), 16)) as RGB;
}

export function accentHex(channels: RGB): string {
  return '#' + channels.map((value) => value.toString(16).padStart(2, '0')).join('');
}

function mix(color: RGB, target: RGB, amount: number): RGB {
  return color.map((value, index) => Math.round(value + (target[index] - value) * amount)) as RGB;
}

function luminance(color: RGB): number {
  const linear = color.map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}

// 深色按钮使用白色文字；较浅的输入色自动生成可读的深色阶。
function contrastTone(color: RGB, contrast: number, exact = false): RGB {
  const original = 1.05 / (luminance(color) + 0.05);
  if (!exact && original >= contrast) return color;
  const lighten = original > contrast;
  const target: RGB = lighten ? [255, 255, 255] : [0, 0, 0];
  let low = 0, high = 1;
  for (let step = 0; step < 16; step++) {
    const middle = (low + high) / 2;
    const ratio = 1.05 / (luminance(mix(color, target, middle)) + 0.05);
    if (lighten ? ratio > contrast : ratio < contrast) low = middle;
    else high = middle;
  }
  return mix(color, target, high);
}

const shades = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950];

export function applyAccent(color: string): void {
  const style = document.documentElement.style;
  document.documentElement.toggleAttribute('data-pata-custom-accent', !!color && validAccent(color));
  if (!color || !validAccent(color)) {
    shades.forEach((shade) => style.removeProperty(`--pata-interaction-${shade}`));
    style.removeProperty('--pata-custom-accent');
    style.removeProperty('--pata-custom-accent-hover');
    return;
  }
  const rgb = accentRGB(color);
  const dark = contrastTone(rgb, 5.5);
  const palette = [
    mix(rgb, [255, 255, 255], .96), mix(rgb, [255, 255, 255], .9),
    mix(rgb, [255, 255, 255], .8), mix(rgb, [255, 255, 255], .65),
    // 中间色阶也要兼顾深色界面的状态图标，纯黑输入仍需生成可见颜色。
    mix(rgb, [255, 255, 255], .55), contrastTone(rgb, 3, true), contrastTone(rgb, 4.5, true), dark,
    mix(dark, [0, 0, 0], .2), mix(dark, [0, 0, 0], .5), mix(dark, [0, 0, 0], .7),
  ];
  shades.forEach((shade, index) => style.setProperty(`--pata-interaction-${shade}`, accentHex(palette[index])));
  style.setProperty('--pata-custom-accent', accentHex(palette[7]));
  style.setProperty('--pata-custom-accent-hover', accentHex(palette[8]));
}
