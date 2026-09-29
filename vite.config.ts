import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  server: { port: 5173, strictPort: true },
  preview: { port: 4173, strictPort: true },
});
