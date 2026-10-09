# Serve precompiled assets without discovering or starting a development server.
if Workbench::DemoMode.enabled?
  ViteRuby.configure(mode: "production", auto_build: false, public_output_dir: "vite")
end
