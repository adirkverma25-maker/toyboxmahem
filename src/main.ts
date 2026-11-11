import '@fontsource/luckiest-guy/latin-400.css';
import '@fontsource/baloo-2/latin-500.css';
import '@fontsource/baloo-2/latin-700.css';
import './ui/styles.css';
import { Game } from './core/Game';

const canvas = document.getElementById('game') as HTMLCanvasElement;
const ui = document.getElementById('ui') as HTMLElement;

const loading = document.createElement('div');
loading.className = 'loading';
loading.innerHTML = `<div><div class="logo-mini">Toybox Mayhem</div><div class="bar"><i></i></div><p class="step">Opening the toy box</p></div>`;
document.body.appendChild(loading);
const bar = loading.querySelector('.bar i') as HTMLElement;
const step = loading.querySelector('.step') as HTMLElement;

function fail(msg: string) {
  const p = document.createElement('p');
  p.className = 'err';
  p.textContent = msg;
  loading.firstElementChild!.appendChild(p);
}

function webglOk() {
  try {
    const c = document.createElement('canvas');
    return !!(c.getContext('webgl2') || c.getContext('webgl'));
  } catch {
    return false;
  }
}

async function boot() {
  if (!webglOk()) {
    fail('This browser has WebGL turned off or unsupported. Try the latest Chrome, Edge or Firefox with hardware acceleration on.');
    return;
  }
  try {
    await Promise.race([
      Promise.all([document.fonts.load('64px "Luckiest Guy"'), document.fonts.load('700 20px "Baloo 2"'), document.fonts.load('500 20px "Baloo 2"')]),
      new Promise((r) => setTimeout(r, 2500)),
    ]);
  } catch {
    /* fonts are optional */
  }
  const game = new Game();
  (window as any).__toybox = game;
  try {
    await game.init(canvas, ui, (s, f) => {
      step.textContent = s;
      bar.style.width = `${Math.round(f * 100)}%`;
    });
    loading.style.opacity = '0';
    setTimeout(() => loading.remove(), 600);
    (window as any).__ready = true;
  } catch (e) {
    console.error(e);
    fail(`Something broke while loading: ${(e as Error).message}. Reload the page to try again.`);
  }
}

window.addEventListener('error', (e) => console.error('[uncaught]', e.message));
boot();
