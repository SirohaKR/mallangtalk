import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';

const html = readFileSync(new URL('../web/index.html', import.meta.url), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function browser(hasViewport = true) {
  const listeners = {};
  const frames = [];
  const timers = new Map();
  let nextTimer = 0;
  let restores = 0;
  const listen = (target) => (name, callback) => {
    listeners[`${target}:${name}`] = callback;
  };
  const window = {
    scrollX: 0,
    scrollY: 0,
    addEventListener: listen('window'),
    requestAnimationFrame: (callback) => { frames.push(callback); return frames.length; },
    setTimeout: (callback) => { timers.set(++nextTimer, callback); return nextTimer; },
    clearTimeout: (id) => timers.delete(id),
    scrollTo: (x, y) => {
      restores++;
      window.scrollX = x;
      window.scrollY = y;
      if (window.visualViewport) window.visualViewport.offsetTop = 0;
    },
  };
  if (hasViewport) {
    window.visualViewport = {
      offsetTop: 0, offsetLeft: 0, addEventListener: listen('viewport'),
    };
  }
  runInNewContext(script, { window, document: { addEventListener: listen('document') } });
  return {
    window, timers,
    fire: (event, arg) => listeners[event](arg),
    flush: () => { while (frames.length) frames.shift()(); },
    restores: () => restores,
  };
}

test('keyboard dismissal restores viewport offset even with focus retained and scrollY zero', () => {
  const b = browser();
  b.window.visualViewport.offsetTop = 240;
  b.fire('viewport:resize');
  b.flush();
  assert.equal(b.restores(), 1);
  // The browser can move the viewport again at the end of its keyboard animation.
  b.window.visualViewport.offsetTop = 120;
  for (const callback of b.timers.values()) callback();
  b.flush();
  assert.equal(b.restores(), 2);
});

test('resize bursts coalesce frames and replace pending animation retries', () => {
  const b = browser();
  b.window.scrollY = 200;
  for (let i = 0; i < 10; i++) b.fire('viewport:resize');
  assert.equal(b.timers.size, 3);
  b.flush();
  assert.equal(b.restores(), 1);
  b.fire('window:scroll');
  b.flush();
  assert.equal(b.restores(), 1);
});

test('focusout and window resize work without the Visual Viewport API', () => {
  const b = browser(false);
  for (const event of ['document:focusout', 'window:resize', 'window:pageshow']) {
    b.window.scrollY = 200;
    b.fire(event);
    b.flush();
    assert.equal(b.window.scrollY, 0);
  }
  assert.equal(b.restores(), 3);
});

test('element scroll from keyboard focus is undone, but text boxes keep their own scroll', () => {
  const b = browser();
  const body = { tagName: 'BODY', scrollTop: 180, scrollLeft: 0 };
  b.fire('document:scroll', { target: body });
  assert.equal(body.scrollTop, 0);
  const box = { tagName: 'TEXTAREA', scrollTop: 40, scrollLeft: 0 };
  b.fire('document:scroll', { target: box });
  assert.equal(box.scrollTop, 40);
});

test('keyboard resizes the page instead of panning it (Android Chrome / Samsung Internet)', () => {
  const meta = html.match(/<meta name="viewport" content="([^"]*)">/)[1];
  assert.match(meta, /interactive-widget=resizes-content/);
});
