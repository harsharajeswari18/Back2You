'use client';
import { useState } from 'react';

export default function Home() {
  const [me, setMe] = useState(null);
  const [err, setErr] = useState('');
  const [items, setItems] = useState([]);
  const [q, setQ] = useState('');

  async function login(e) {
    e.preventDefault();
    const f = new FormData(e.target);
    const r = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: f.get('email'), password: f.get('password') }),
    });
    const d = await r.json();
    if (!r.ok) return setErr(d.error);
    setErr(''); setMe(d); search('');
  }
  async function search(text) {
    const r = await fetch('/api/items?limit=20' + (text ? '&q=' + encodeURIComponent(text) : ''));
    if (r.ok) setItems(await r.json());
  }

  if (!me) return (
    <>
      <h1>Back2You</h1>
      <form onSubmit={login}>
        <input name="email" placeholder="email" defaultValue="user11@back2you.test" />{' '}
        <input name="password" type="password" placeholder="password" />{' '}
        <button>Login</button>
      </form>
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
    </>
  );
  return (
    <>
      <h1>Back2You</h1>
      <p>Signed in as {me.name} ({me.role})</p>
      <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="search found items" />{' '}
      <button onClick={() => search(q)}>Search</button>
      <ul>
        {items.map((i) => (
          <li key={i.item_id}>#{i.item_id} {i.title} - {i.location} [{i.status}]</li>
        ))}
      </ul>
    </>
  );
}
