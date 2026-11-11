import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

// `npm run build` makes a normal multi-file build in dist/.
// `npm run build:standalone` makes ONE html file that runs by double-clicking it.
export default defineConfig(({ mode }) => ({
  base: './',
  plugins: mode === 'standalone' ? [viteSingleFile()] : [],
  build: {
    outDir: mode === 'standalone' ? 'standalone' : 'dist',
    target: 'es2020',
    chunkSizeWarningLimit: 4000,
    assetsInlineLimit: mode === 'standalone' ? 100000000 : 4096,
  },
  server: { port: 5173, open: true },
}));
