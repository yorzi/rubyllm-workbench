import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'

// Vite serves modules cross-origin in development. Keep the allowlist narrow
// enough for local Rails hosts while reflecting only an accepted origin.
const devHostOrigin = /^https?:\/\/(localhost|127\.0\.0\.1|([\w-]+\.)*(local|lvh\.me))(:\d+)?$/

export default defineConfig({
  plugins: [
    RubyPlugin(),
  ],
  server: {
    allowedHosts: ['localhost', '127.0.0.1', '.local', '.lvh.me'],
    cors: { origin: devHostOrigin },
  },
})
