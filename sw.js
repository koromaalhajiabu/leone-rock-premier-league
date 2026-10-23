// SLFA app shell service worker.
// Caches only the page shell and icons so the app opens quickly and offline.
// Live data (Supabase, photos, news) is never cached here: it always goes to the network.
const CACHE = 'slfa-shell-v2';
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

// Show an alert pushed from the league system.
self.addEventListener('push', (event) => {
  let data = { title: 'SLFA League', body: 'There is a new update.', url: './index.html' };
  try { data = { ...data, ...event.data.json() }; } catch (_e) { /* keep the default message */ }
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: 'icon-192.png',
      badge: 'icon-192.png',
      data: { url: data.url || './index.html' },
    })
  );
});

// Tapping an alert opens or focuses the app.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || './index.html';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      return self.clients.openWindow(target);
    })
  );
});
