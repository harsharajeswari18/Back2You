/** @type {import('next').NextConfig} */
module.exports = {
  // keep the ML runtime out of the webpack bundle; it is loaded from node_modules
  experimental: {
    serverComponentsExternalPackages: ['@xenova/transformers', 'onnxruntime-node', 'sharp'],
  },
};
