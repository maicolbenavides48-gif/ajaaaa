const CACHE_NAME = 'aja-app-v5';
const ASSETS = ['/'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)),
    )),
  );
  self.clients.claim();
});

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const requestUrl = new URL(event.request.url);
  const isStaticAsset = requestUrl.pathname.startsWith('/assets/')
    || /\.(?:js|css|map|svg|png|jpg|jpeg|webp|ico|woff2?)$/i.test(requestUrl.pathname);

  event.respondWith(
    fetch(event.request).then((response) => {
      const contentType = response.headers.get('content-type') ?? '';
      const isHtmlFallbackForAsset = isStaticAsset && contentType.includes('text/html');
      if (response.ok && !isHtmlFallbackForAsset) {
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone)).catch(() => {});
      }
      return response;
    }).catch(() => caches.match(event.request).then((cached) => cached ?? Response.error())),
  );
});
