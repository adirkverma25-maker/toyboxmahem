import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { BokehPass } from 'three/examples/jsm/postprocessing/BokehPass.js';
import { AfterimagePass } from 'three/examples/jsm/postprocessing/AfterimagePass.js';
import { GTAOPass } from 'three/examples/jsm/postprocessing/GTAOPass.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import type { Quality } from '../core/Settings';

/** Replaces NaN / infinite / absurdly bright HDR values with something finite. */
const SanitizeShader = {
  name: 'SanitizeShader',
  uniforms: { tDiffuse: { value: null } },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    varying vec2 vUv;
    float fix1(float v) {
      // NaN fails every comparison, so it lands in the 0.0 branch; +inf is caught by the upper bound
      return (v >= 0.0 && v <= 64.0) ? v : (v > 64.0 ? 64.0 : 0.0);
    }
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      gl_FragColor = vec4(fix1(c.r), fix1(c.g), fix1(c.b), (c.a >= 0.0 && c.a <= 1.0) ? c.a : 1.0);
    }`,
};

/**
 * Owns the WebGL renderer, world + viewmodel scenes, and the post-processing chain.
 * Quality tiers:
 *  low    - no shadows, no post FX, reduced resolution
 *  medium - 1024 soft shadows, bloom, 2x MSAA
 *  high   - 2048 soft shadows, bloom, ambient occlusion (GTAO), 4x MSAA
 */
export class Renderer {
  renderer: THREE.WebGLRenderer;
  scene = new THREE.Scene();
  camera: THREE.PerspectiveCamera;
  vmScene = new THREE.Scene();
  vmCamera: THREE.PerspectiveCamera;
  composer!: EffectComposer;
  private worldPass!: RenderPass;
  private vmPass!: RenderPass;
  private bloom: UnrealBloomPass | null = null;
  private bokeh: BokehPass | null = null;
  private afterimage: AfterimagePass | null = null;
  private gtao: GTAOPass | null = null;
  quality: Quality = 'high';
  menuBlur = false;
  motionBlur = false;
  private envTex: THREE.Texture | null = null;
  sun: THREE.DirectionalLight | null = null;
  pointLights: THREE.PointLight[] = [];

  constructor(public canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance', stencil: false });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 0.98;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.camera = new THREE.PerspectiveCamera(90, 1, 0.05, 400);
    this.vmCamera = new THREE.PerspectiveCamera(62, 1, 0.01, 10);
    this.scene.background = new THREE.Color('#f2e2cc');
    this.scene.fog = new THREE.Fog('#f1dfc6', 70, 190);

    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.envTex = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    pmrem.dispose();
    this.scene.environment = this.envTex;
    this.scene.environmentIntensity = 0.42;
    this.vmScene.environment = this.envTex;
    this.vmScene.environmentIntensity = 0.75;
    // viewmodel lighting: matches the warm room so toy hands look like they belong
    const vmHemi = new THREE.HemisphereLight('#fff1dc', '#7a5a40', 1.6);
    const vmKey = new THREE.DirectionalLight('#ffe2b8', 2.4);
    vmKey.position.set(-1, 2, 1.5);
    const vmRim = new THREE.DirectionalLight('#b8d8ff', 1.2);
    vmRim.position.set(1.5, 0.5, -1);
    this.vmScene.add(vmHemi, vmKey, vmRim);
  }

  setQuality(q: Quality) {
    this.quality = q;
    const dpr = window.devicePixelRatio || 1;
    const pr = q === 'low' ? Math.min(dpr, 1) * 0.8 : q === 'medium' ? Math.min(dpr, 1.25) : Math.min(dpr, 1.75);
    this.renderer.setPixelRatio(pr);
    this.renderer.shadowMap.enabled = q !== 'low';
    if (this.sun) {
      this.sun.castShadow = q !== 'low';
      const size = q === 'high' ? 2048 : 1024;
      if (this.sun.shadow.mapSize.x !== size) {
        this.sun.shadow.mapSize.set(size, size);
        this.sun.shadow.map?.dispose();
        this.sun.shadow.map = null as unknown as THREE.WebGLRenderTarget;
      }
    }
    // dim side lights on low to save fragment cost
    for (const l of this.pointLights) l.visible = q !== 'low' || l.intensity > 15;
    this.buildComposer();
    this.resize();
    // force all materials to recompile for the new shadow settings
    this.scene.traverse((o) => {
      const m = (o as THREE.Mesh).material as THREE.Material | THREE.Material[] | undefined;
      if (!m) return;
      (Array.isArray(m) ? m : [m]).forEach((mm) => (mm.needsUpdate = true));
    });
  }

  private buildComposer() {
    this.composer?.dispose();
    const size = this.renderer.getDrawingBufferSize(new THREE.Vector2());
    const samples = this.quality === 'high' ? 4 : this.quality === 'medium' ? 2 : 0;
    const rt = new THREE.WebGLRenderTarget(Math.max(1, size.x), Math.max(1, size.y), { type: THREE.HalfFloatType, samples });
    this.composer = new EffectComposer(this.renderer, rt);
    this.worldPass = new RenderPass(this.scene, this.camera);
    this.composer.addPass(this.worldPass);
    this.gtao = null;
    if (this.quality === 'high') {
      const g = new GTAOPass(this.scene, this.camera, Math.max(1, size.x >> 1), Math.max(1, size.y >> 1));
      g.blendIntensity = 0.85;
      g.updateGtaoMaterial({ radius: 1.2, distanceExponent: 1.4, thickness: 1.5, scale: 1.0, samples: 12 });
      g.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 6, rings: 2, samples: 12 });
      const origSetSize = g.setSize.bind(g);
      g.setSize = (w: number, h: number) => origSetSize(Math.max(1, w >> 1), Math.max(1, h >> 1));
      this.gtao = g;
      this.composer.addPass(g);
    }
    this.vmPass = new RenderPass(this.vmScene, this.vmCamera);
    this.vmPass.clear = false;
    this.vmPass.clearDepth = true;
    this.composer.addPass(this.vmPass);
    // Some GPUs (seen on Intel Arc) leave a few NaN/infinite pixels in the HDR buffer. Bloom's blur
    // smears those into huge black blocks, so scrub them before any effect that samples neighbors.
    this.composer.addPass(new ShaderPass(SanitizeShader));
    this.bloom = null;
    if (this.quality !== 'low') {
      this.bloom = new UnrealBloomPass(new THREE.Vector2(size.x, size.y), 0.28, 0.5, 0.93);
      this.composer.addPass(this.bloom);
    }
    this.bokeh = new BokehPass(this.scene, this.camera, { focus: 18, aperture: 0.0012, maxblur: 0.008 });
    this.bokeh.enabled = this.menuBlur && this.quality !== 'low';
    this.composer.addPass(this.bokeh);
    this.afterimage = new AfterimagePass(0.55);
    this.afterimage.enabled = this.motionBlur;
    this.composer.addPass(this.afterimage);
    this.composer.addPass(new OutputPass());
  }

  setMenuBlur(on: boolean) {
    this.menuBlur = on;
    if (this.bokeh) this.bokeh.enabled = on && this.quality !== 'low';
    if (this.gtao) this.gtao.enabled = true;
  }
  setMotionBlur(on: boolean) {
    this.motionBlur = on;
    if (this.afterimage) this.afterimage.enabled = on;
  }
  setViewmodelVisible(v: boolean) {
    if (this.vmPass) this.vmPass.enabled = v;
  }

  resize() {
    const w = window.innerWidth, h = window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.vmCamera.aspect = w / h;
    this.vmCamera.updateProjectionMatrix();
    this.composer?.setSize(w, h);
  }

  render() {
    this.composer.render();
  }

  dispose() {
    this.composer?.dispose();
    this.envTex?.dispose();
    this.renderer.dispose();
  }
}
