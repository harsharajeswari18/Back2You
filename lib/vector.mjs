// Qdrant access: one collection, 384-d cosine vectors, payload = searchable metadata.
import { QdrantClient } from '@qdrant/js-client-rest';
import { embed, DIM } from './embed.mjs';

export const COLLECTION = 'found_items';
const g = globalThis;

export function qdrant() {
  return (g.__b2yQdrant ??= new QdrantClient({
    url: process.env.QDRANT_URL || 'http://127.0.0.1:6333',
    apiKey: process.env.QDRANT_API_KEY || undefined,
    checkCompatibility: false,
  }));
}

export async function ensureCollection() {
  const c = qdrant();
  const { collections } = await c.getCollections();
  if (collections.some((x) => x.name === COLLECTION)) return;
  await c.createCollection(COLLECTION, { vectors: { size: DIM, distance: 'Cosine' } });
  await c.createPayloadIndex(COLLECTION, { field_name: 'category_id', field_schema: 'integer' });
  await c.createPayloadIndex(COLLECTION, { field_name: 'location_id', field_schema: 'integer' });
}

// What gets embedded for an item: title + description + category name.
export const itemText = (it) => `${it.title}. ${it.description} Category: ${it.category}.`;

function toPoint(it, vector) {
  return {
    id: it.item_id, // Qdrant point id = MySQL item_id
    vector,
    payload: {
      item_id: it.item_id,
      category_id: it.category_id,
      location_id: it.location_id,
      color: it.color,
      found_ts: Number(it.found_ts),
    },
  };
}

export async function indexItems(items, batch = 50) {
  await ensureCollection();
  for (let i = 0; i < items.length; i += batch) {
    const points = [];
    for (const it of items.slice(i, i + batch)) points.push(toPoint(it, await embed(itemText(it))));
    await qdrant().upsert(COLLECTION, { wait: true, points });
  }
}

// Status is NOT stored in Qdrant: MySQL stays the single source of truth for the
// lifecycle, so the caller filters candidates by status after the vector search.
export async function searchSimilar(text, { limit = 20, categoryId } = {}) {
  const vector = await embed(text);
  const filter = categoryId ? { must: [{ key: 'category_id', match: { value: Number(categoryId) } }] } : undefined;
  return qdrant().search(COLLECTION, { vector, limit, filter, with_payload: true });
}
