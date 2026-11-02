// SLFA League App service worker.
// 1. Keeps the app shell available offline (pages, scripts, styles, images).
// 2. Shows league alerts sent as push messages.
// League data always comes from the network, so scores and news are never stale.
const CACHE = 'slfa-app-v2';
const SHELL = ['./', './index.html', './config.js', './public.js', './admin.js', './manifest.json',
  './icon-192.png', './icon-512.png', './slfa-logo.png'];

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) { return c.addAll(SHELL); }).then(function () { return self.skipWaiting(); }));
});
self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== CACHE; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});
self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(fetch(req).then(function (res) {
    if (res.ok) { var copy = res.clone(); caches.open(CACHE).then(function (c) { c.put(req, copy); }); }
    return res;
  }).catch(function () {
    return caches.match(req).then(function (hit) { return hit || caches.match('./index.html'); });
  }));
});

self.addEventListener('push', function (event) {
  var data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: 'SLFA League', body: event.data ? event.data.text() : '' }; }
  event.waitUntil(self.registration.showNotification(data.title || 'SLFA League', {
    body: data.body || '', icon: 'icon-192.png', badge: 'icon-192.png', data: { url: data.url || './' }
  }));
});
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data.url || './'));
});
