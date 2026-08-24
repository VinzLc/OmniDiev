/** @type {import('next').NextConfig} */
const nextConfig = {
  // transformers.js charge onnxruntime-node : il doit rester hors du bundle.
  serverExternalPackages: ["@huggingface/transformers", "onnxruntime-node"],
  // La pastille de développement de Next se superpose au composeur.
  devIndicators: false,
};
export default nextConfig;
