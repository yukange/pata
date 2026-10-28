export const DEFAULT_ACCENT = '#007aff';
export type RGB = [number, number, number];

export interface AccentRoles {
  source: string;
  solid: string;
  onSolid: string;
  hover: string;
  text: string;
  subtle: string;
  focus: string;
}

const WHITE: RGB = [255, 255, 255];
const BLACK: RGB = [0, 0, 0];
const LIGHT_SURFACE: RGB = [255, 255, 255];
const DARK_SURFACE: RGB = [28, 25, 23];

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

export function accentContrast(first: RGB, second: RGB): number {
  const a = luminance(first);
  const b = luminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

// Only change a color when the target surface or foreground would make it unreadable.
function ensureContrast(color: RGB, background: RGB, minimum: number, toward: RGB): RGB {
  if (accentContrast(color, background) >= minimum) return color;
  let low = 0;
  let high = 1;
  for (let step = 0; step < 16; step++) {
    const middle = (low + high) / 2;
    if (accentContrast(mix(color, toward, middle), background) >= minimum) high = middle;
    else low = middle;
  }
  return mix(color, toward, high);
}

// Radix-inspired semantic roles rather than a single white-contrast-adjusted palette.
// The source stays untouched; functional colors adapt independently to each appearance.
export function deriveAccentRoles(color: string, dark: boolean): AccentRoles {
  const rgb = accentRGB(color);
  const surface = dark ? DARK_SURFACE : LIGHT_SURFACE;
  const againstSurface = dark ? WHITE : BLACK;
  let solid = ensureContrast(rgb, surface, 3, againstSurface);

  // A slightly darker system-blue-like solid keeps white labels. Bright yellows
  // and greens instead keep their character and use dark labels.
  if (!dark && accentContrast(solid, WHITE) < 4.5 && accentContrast(solid, WHITE) >= 3.6) {
    const candidate = ensureContrast(solid, WHITE, 4.5, BLACK);
    const adjustment = Math.max(...solid.map((channel, index) => Math.abs(channel - candidate[index])));
    if (adjustment <= 32) solid = candidate;
  }
  const onSolid = accentContrast(solid, WHITE) >= 4.5 ? WHITE : BLACK;
  const text = ensureContrast(rgb, surface, 4.5, againstSurface);
  const focus = ensureContrast(rgb, surface, 3, againstSurface);
  const subtle = mix(surface, rgb, dark ? 0.16 : 0.10);
  const hoverCandidate = mix(solid, onSolid, 0.08);
  const hover = accentContrast(hoverCandidate, surface) >= 3 && accentContrast(hoverCandidate, onSolid) >= 4.5
    ? hoverCandidate : solid;

  return {
    source: accentHex(rgb),
    solid: accentHex(solid),
    onSolid: accentHex(onSolid),
    hover: accentHex(hover),
    text: accentHex(text),
    subtle: accentHex(subtle),
    focus: accentHex(focus),
  };
}

const roleNames: (keyof AccentRoles)[] = ['source', 'solid', 'onSolid', 'hover', 'text', 'subtle', 'focus'];

export function applyAccent(color: string): void {
  const style = document.documentElement.style;
  const custom = !!color && validAccent(color);
  document.documentElement.toggleAttribute('data-pata-custom-accent', custom);
  if (!custom) {
    for (const mode of ['light', 'dark']) {
      for (const role of roleNames) style.removeProperty(`--pata-${mode}-${role.replace(/[A-Z]/g, (letter) => '-' + letter.toLowerCase())}`);
    }
    return;
  }
  // Generate both sets once; switching light/dark is handled by CSS, without
  // re-saving the user's color or waiting for a React effect.
  for (const mode of ['light', 'dark'] as const) {
    const roles = deriveAccentRoles(color, mode === 'dark');
    for (const role of roleNames) {
      style.setProperty(`--pata-${mode}-${role.replace(/[A-Z]/g, (letter) => '-' + letter.toLowerCase())}`, roles[role]);
    }
  }
}
