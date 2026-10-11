// Text -> 384-dimension unit vector using all-MiniLM-L6-v2 (Transformers.js, runs in Node).
// The model (~25 MB) is downloaded on first use and cached on disk.
export const DIM = 384;
const g = globalThis;

export async function embed(text) {
  if (process.env.EMBEDDER === 'hash') return hashEmbed(text);
  if (!g.__b2yExtractor) {
    const { pipeline } = await import('@xenova/transformers');
    g.__b2yExtractor = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
  }
  const out = await g.__b2yExtractor(text, { pooling: 'mean', normalize: true });
  return Array.from(out.data);
}

// Offline stand-in for tests when the model cannot be downloaded: hashed
// bag of words + bigrams. NOT semantic; never use it for reported results.
function hashEmbed(text) {
  const v = new Array(DIM).fill(0);
  const toks = text.toLowerCase().match(/[a-z0-9]+/g) || [];
  const add = (t) => {
    let h = 2166136261;
    for (const ch of t) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619) >>> 0; }
    v[h % DIM] += h & 0x10000 ? 1 : -1;
  };
  toks.forEach((t, i) => { add(t); if (toks[i + 1]) add(t + ' ' + toks[i + 1]); });
  const n = Math.sqrt(v.reduce((s, x) => s + x * x, 0)) || 1;
  return v.map((x) => x / n);
}
