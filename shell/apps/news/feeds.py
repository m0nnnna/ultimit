#!/usr/bin/env python3
"""feeds.py - RSS 2.0 / RSS 1.0 / Atom fetcher for the Ultimit news ticker (stdlib only).

Usage:
  feeds.py URL                              one feed -> {"title","link","items":[{title,link,ts}],"error":""}
  feeds.py [--cache FILE] [--cached] -- URL...
                                            several feeds, merged newest-first (max 20 items)

Never raises: every failure (bad XML, redirects to odd schemes, non-200, no network, ...) is
reported as {"items": [], "error": "..."} (per feed in multi mode: feeds[i].error).
Feed content is untrusted: titles are stripped of tags/entities/control characters and capped,
and only http/https links survive. --cache keeps the last good result per feed (offline start-up).
"""
import html
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

UA = "Ultimit/0.1"
TIMEOUT = 10            # seconds, per request (also enforced as an overall deadline)
MAX_BYTES = 2 * 1024 * 1024
MAX_TITLE = 140
PER_FEED = 40
TOTAL = 20

TAG_RE = re.compile(r"</?[A-Za-z!][^>]*>")
BAD_CHARS = re.compile("[\x00-\x1f\x7f​-‏‪-‮⁦-⁩﻿]")


def clean(s, cap=MAX_TITLE):
    s = s or ""
    for _ in range(2):                       # second pass catches double-encoded markup
        s = html.unescape(TAG_RE.sub(" ", s))
    s = re.sub(r"\s+", " ", BAD_CHARS.sub(" ", s)).strip()
    if len(s) > cap:
        s = s[:cap - 1].rstrip() + "…"
    return s


def safe_url(u, base=""):
    u = (u or "").strip()
    if not u:
        return ""
    try:
        if base:
            u = urllib.parse.urljoin(base, u)
        p = urllib.parse.urlsplit(u)
    except ValueError:
        return ""
    if p.scheme.lower() not in ("http", "https") or not p.netloc or re.search(r"[\x00-\x20]", u):
        return ""
    return u[:2000]


def parse_date(s):
    s = (s or "").strip()
    if not s:
        return 0
    d = None
    try:
        d = parsedate_to_datetime(s)
    except Exception:
        pass
    if d is None:
        try:
            d = datetime.fromisoformat(s.replace("Z", "+00:00").replace("z", "+00:00"))
        except Exception:
            return 0
    try:
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return int(d.timestamp())
    except Exception:
        return 0


def local(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def kids(el, name):
    return [c for c in el if local(c.tag) == name]


def text_of(el, *names):
    for n in names:
        for c in kids(el, n):
            t = "".join(c.itertext()).strip()
            if t:
                return t
    return ""


def link_of(el, base):
    """RSS <link>text</link> or Atom <link rel=alternate href=.../> (never rel=self)."""
    best = ""
    for c in kids(el, "link"):
        href = c.get("href")
        if href is not None:
            if c.get("rel", "alternate") == "alternate":
                best = best or safe_url(href, base)
            continue
        u = safe_url("".join(c.itertext()), base)
        if u:
            return u
    return best


def parse_feed(data, url):
    if re.search(rb"<!ENTITY", data, re.I):
        raise ValueError("not a feed")           # entity-expansion tricks: refuse
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        raise ValueError("not a feed")
    kind = local(root.tag)
    if kind == "rss":
        chan = (kids(root, "channel") or [None])[0]
        if chan is None:
            raise ValueError("not a feed")
        entries, meta = kids(chan, "item"), chan
    elif kind == "RDF":
        entries, meta = kids(root, "item"), (kids(root, "channel") or [root])[0]
    elif kind == "feed":
        entries, meta = kids(root, "entry"), root
    else:
        raise ValueError("not a feed")
    items = []
    for e in entries[:PER_FEED]:
        title = clean(text_of(e, "title"))
        if not title:
            continue
        link = link_of(e, url)
        if not link:
            link = safe_url(text_of(e, "guid", "id"), url)
        ts = parse_date(text_of(e, "pubDate", "published", "date", "updated"))
        items.append({"title": title, "link": link, "ts": ts})
    return {"title": clean(text_of(meta, "title"), 80), "link": link_of(meta, url), "items": items}


class _Redirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not safe_url(newurl):
            raise urllib.error.URLError("redirect to unsupported scheme")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_bytes(url):
    opener = urllib.request.build_opener(_Redirect)
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/atom+xml, application/rss+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5"})
    deadline = time.monotonic() + TIMEOUT
    with opener.open(req, timeout=TIMEOUT) as r:
        if getattr(r, "status", 200) != 200:
            raise urllib.error.HTTPError(url, r.status, "HTTP %d" % r.status, r.headers, None)
        buf = b""
        while True:
            chunk = r.read(65536)
            if not chunk:
                return buf
            buf += chunk
            if len(buf) > MAX_BYTES:
                raise ValueError("not a feed")
            if time.monotonic() > deadline:
                raise TimeoutError("timed out")


def fetch_one(url):
    out = {"url": url, "title": "", "link": "", "items": [], "error": ""}
    try:
        if not safe_url(url):
            out["error"] = "not a feed (URL must be http or https)"
            return out
        out.update(parse_feed(fetch_bytes(url), url))
    except urllib.error.HTTPError as e:
        out["error"] = "HTTP %s" % e.code
    except ValueError as e:
        out["error"] = str(e) if str(e) == "not a feed" else "not a feed"
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError, OSError) as e:
        why = getattr(e, "reason", e)
        why = re.sub(r"\[Errno \d+\]\s*", "", str(why)).strip().lower()
        out["error"] = "couldn't reach (%s)" % clean(why, 60)
    except Exception as e:                       # never crash
        out["error"] = "failed (%s)" % clean(type(e).__name__, 40)
    if out["error"]:
        out["items"] = []
    return out


def load_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        if isinstance(d, dict) and isinstance(d.get("feeds"), dict):
            return d
    except Exception:
        pass
    return {"version": 1, "feeds": {}}


def save_cache(path, cache):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp%d" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        pass


def merge(urls, results):
    """results: [{url,title,link,items,error,fetched,stale}] -> output object."""
    allitems, feeds = [], []
    for r in results:
        feeds.append({"url": r["url"], "title": r.get("title", ""), "link": r.get("link", ""),
                      "ok": not r.get("error"), "error": r.get("error", ""),
                      "count": len(r.get("items", [])), "fetched": r.get("fetched", 0),
                      "stale": bool(r.get("stale"))})
        for i, it in enumerate(r.get("items", [])):
            allitems.append({"title": it["title"], "link": it["link"], "ts": it["ts"],
                             "site": r.get("link", ""), "src": r.get("title", ""), "_o": i})
    allitems.sort(key=lambda x: (-x["ts"], x["_o"]))
    seen, items = set(), []
    for it in allitems:
        key = it["link"] or it["title"]
        if key in seen:
            continue
        seen.add(key)
        it.pop("_o")
        items.append(it)
        if len(items) >= TOTAL:
            break
    err = ""
    if urls and not items and all(f["error"] for f in feeds):
        err = "no feed could be loaded"
    return {"items": items, "feeds": feeds, "error": err}


def run_multi(urls, cache_path, cached_only):
    cache = load_cache(cache_path) if cache_path else {"feeds": {}}
    old = cache.get("feeds", {})
    results = []
    if cached_only:
        for u in urls:
            c = old.get(u)
            if isinstance(c, dict) and c.get("items"):
                results.append({"url": u, "title": c.get("title", ""), "link": c.get("link", ""),
                                "items": c["items"], "fetched": c.get("fetched", 0), "error": "", "stale": True})
            else:
                results.append({"url": u, "items": [], "error": "not loaded yet"})
        out = merge(urls, results)
        out["cached"] = True
        return out
    with ThreadPoolExecutor(max_workers=max(1, min(8, len(urls)))) as ex:
        fetched = list(ex.map(fetch_one, urls))
    new = {}
    now = int(time.time())
    for u, r in zip(urls, fetched):
        if not r["error"]:
            new[u] = {"title": r["title"], "link": r["link"], "items": r["items"], "fetched": now}
            r["fetched"] = now
        else:
            c = old.get(u)
            if isinstance(c, dict) and isinstance(c.get("items"), list):   # keep last good, mark stale
                new[u] = c
                r.update({"title": c.get("title", ""), "link": c.get("link", ""), "items": c["items"],
                          "fetched": c.get("fetched", 0), "stale": True})
        results.append(r)
    if cache_path and new != old:
        save_cache(cache_path, {"version": 1, "feeds": new})
    out = merge(urls, results)
    out["cached"] = False
    return out


def main(argv):
    cache_path, cached_only, urls = "", False, []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--":
            urls += argv[i + 1:]
            break
        if a == "--cache" and i + 1 < len(argv):
            cache_path = argv[i + 1]
            i += 1
        elif a == "--cached":
            cached_only = True
        else:
            urls.append(a)
        i += 1
    if len(urls) == 1 and not cache_path and not cached_only:
        r = fetch_one(urls[0])
        return {"title": r["title"], "link": r["link"], "items": r["items"], "error": r["error"]}
    return run_multi(urls, cache_path, cached_only)


if __name__ == "__main__":
    try:
        res = main(sys.argv[1:])
    except Exception as e:                       # last resort
        res = {"items": [], "error": "failed (%s)" % type(e).__name__}
    sys.stdout.write(json.dumps(res, ensure_ascii=False))
    sys.stdout.write("\n")
