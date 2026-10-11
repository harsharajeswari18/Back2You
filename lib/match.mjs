// Hybrid re-ranking: semantic similarity from Qdrant + structured signals from MySQL.
export const WEIGHTS = { vector: 0.65, category: 0.12, location: 0.1, color: 0.08, time: 0.05 };

// cands: [{ item_id, vector_score, category_id, location_id, color, found_ts }]
// q:     { category_id?, location_id?, color?, lost_ts? }   (all optional)
// mode:  'vector' (cosine only) | 'hybrid'
export function rerank(cands, q, mode = 'hybrid') {
  const scored = cands.map((c) => {
    const b = {
      vector: c.vector_score,
      category: q.category_id && c.category_id === q.category_id ? 1 : 0,
      location: q.location_id && c.location_id === q.location_id ? 1 : 0,
      color: q.color && c.color && c.color.toLowerCase() === String(q.color).toLowerCase() ? 1 : 0,
      time: 0,
    };
    if (q.lost_ts && c.found_ts) {
      const hours = (c.found_ts - q.lost_ts) / 3600; // an item cannot be found before it was lost
      b.time = hours >= 0 ? Math.exp(-hours / 72) : 0;
    }
    const score =
      mode === 'vector'
        ? b.vector
        : Object.keys(WEIGHTS).reduce((s, k) => s + WEIGHTS[k] * b[k], 0);
    return { ...c, score, breakdown: b };
  });
  return scored.sort((a, b) => b.score - a.score);
}

export function summarize(ranks, n) {
  const hit = (k) => ranks.filter((r) => r <= k).length / n;
  return {
    top1: hit(1),
    top3: hit(3),
    top5: hit(5),
    mrr: ranks.reduce((s, r) => s + (Number.isFinite(r) ? 1 / r : 0), 0) / n,
  };
}
