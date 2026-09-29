import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: { target: ['chrome113', 'edge113', 'firefox141', 'safari26'] },
  server: { port: 5173, strictPort: true },
  preview: { port: 4173, strictPort: true },
});
