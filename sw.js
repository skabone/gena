/* Daybook service worker — network-first so updates always arrive online,
   with a cache fallback so the installed app still opens offline.
   Required Notice: Copyright (c) 2026 Mintay Misgano (https://github.com/skabone) */
var CACHE = "daybook-v1";

self.addEventListener("install", function (e) {
  self.skipWaiting();
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches.keys()
      .then(function (keys) {
        // Only Gena's own caches. skabone.github.io is a shared origin — FantasyCast keeps its offline
        // shell here too, and deleting every key would evict a neighbouring app on each Gena release.
        return Promise.all(keys.filter(function (k) { return k !== CACHE && k.indexOf("daybook-") === 0; })
          .map(function (k) { return caches.delete(k); }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // let cross-origin (GitHub API, etc.) pass through untouched

  // GitHub Pages sends cache-control: max-age=600, so a plain fetch() can serve a copy up to ten
  // minutes stale — which made "network-first" still miss a fresh push. "no-cache" revalidates with
  // the server on every request: a 304 when nothing changed (cheap), the new build when it did.
  e.respondWith(
    fetch(req, { cache: "no-cache" })
      .then(function (res) {
        if (res && res.ok) {
          var copy = res.clone();
          caches.open(CACHE).then(function (c) { c.put(req, copy); }).catch(function () {});
        }
        return res;
      })
      .catch(function () {
        return caches.match(req).then(function (hit) {
          return hit || caches.match("./") || caches.match("index.html");
        });
      })
  );
});
