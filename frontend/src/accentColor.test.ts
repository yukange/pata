import test from 'node:test';
import assert from 'node:assert/strict';
import { accentContrast, accentRGB, deriveAccentRoles } from './accentColor.ts';

const LIGHT_SURFACE: [number, number, number] = [255, 255, 255];
const DARK_SURFACE: [number, number, number] = [28, 25, 23];

test('custom accent roles preserve user RGB and meet light/dark contrast targets', () => {
  for (const source of [
    '#ffffff', '#000000', '#007aff', '#34c759', '#ff9500',
    '#ff2d55', '#8e8e93', '#ffeb3b', '#444444',
  ]) {
    for (const dark of [false, true]) {
      const roles = deriveAccentRoles(source, dark);
      const surface = dark ? DARK_SURFACE : LIGHT_SURFACE;
      const label = `${source} / ${dark ? 'dark' : 'light'}`;
      assert.equal(roles.source, source, `${label}: original swatch should be unchanged`);
      assert.ok(accentContrast(accentRGB(roles.solid), surface) >= 3, `${label}: filled control must stand out`);
      assert.ok(accentContrast(accentRGB(roles.solid), accentRGB(roles.onSolid)) >= 4.5, `${label}: control label unreadable`);
      assert.ok(accentContrast(accentRGB(roles.hover), surface) >= 3, `${label}: hover not visible`);
      assert.ok(accentContrast(accentRGB(roles.hover), accentRGB(roles.onSolid)) >= 4.5, `${label}: hover label unreadable`);
      assert.ok(accentContrast(accentRGB(roles.text), surface) >= 4.5, `${label}: accent text unreadable`);
      assert.ok(accentContrast(accentRGB(roles.focus), surface) >= 3, `${label}: focus ring not visible`);
    }
  }
});

test('muted green preset stays green with legible white controls in both themes', () => {
  const chosen = '#27836b';
  for (const dark of [false, true]) {
    const roles = deriveAccentRoles(chosen, dark);
    assert.equal(roles.source, chosen);
    assert.equal(roles.onSolid, '#ffffff');
    assert.ok(accentContrast(accentRGB(roles.solid), accentRGB(roles.onSolid)) >= 4.5);
  }
});

test('white and black accents adapt to theme rather than always being grey or black', () => {
  assert.equal(deriveAccentRoles('#ffffff', true).solid, '#ffffff');
  assert.notEqual(deriveAccentRoles('#ffffff', false).solid, '#ffffff');
  assert.equal(deriveAccentRoles('#000000', false).solid, '#000000');
  assert.notEqual(deriveAccentRoles('#000000', true).solid, '#000000');
});

test('bright fills use dark text and blue buttons retain white text in light mode', () => {
  assert.equal(deriveAccentRoles('#ffeb3b', false).onSolid, '#000000');
  assert.equal(deriveAccentRoles('#007aff', false).onSolid, '#ffffff');
});
