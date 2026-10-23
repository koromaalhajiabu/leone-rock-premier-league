// SLFA app shell service worker.
// Caches only the page shell and icons so the app opens quickly and offline.
// Live data (Supabase, photos, news) is never cached here: it always goes to the network.
const CACHE = 'slfa-shell-v1';
const SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png', './apple-touch-icon.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Only handle files from this site. Leave Supabase, CDNs and other sites alone.
  if (url.origin !== self.location.origin) return;

  // Page: try the network first so updates appear, fall back to the cached copy when offline.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put('./index.html', copy));
        return res;
      }).catch(() => caches.match('./index.html'))
    );
    return;
  }

  // Icons and manifest: cache first.
  event.respondWith(caches.match(req).then((hit) => hit || fetch(req)));
});
