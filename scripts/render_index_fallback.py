#!/usr/bin/env python3
"""Render the no-JavaScript fallback install block in docs/index.html.

Usage: python3 scripts/render_index_fallback.py [--check]

Rewrites the <!-- fallback:start --> ... <!-- fallback:end --> block from the default
bundle in docs/assets/install-groups.json (mirrors commandLines() in docs/assets/app.js).
--check fails instead of writing, so CI catches a stale block. Stdlib only.
"""
import html, json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parent.parent
data = json.loads((root / "docs/assets/install-groups.json").read_text())
groups = {g["id"]: g for g in data["groups"]}
bid = data.get("meta", {}).get("default_bundle", "workstation")
b = next(x for x in data["bundles"] if x["id"] == bid)
def uniq(xs):
    out = []
    [out.append(x) for x in xs if x not in out]
    return out
f, c, t, m = [], [], [], []
for gid in b["include"]:
    g = groups[gid]; f += g["formulae"]; c += g["casks"]; t += g.get("taps", [])
    for e in g.get("mas", []):
        e = e if isinstance(e, dict) else {"id": e, "name": str(e)}
        if all(str(e["id"]) != str(x["id"]) for x in m): m.append(e)
f, c, t = uniq(f), uniq(c), uniq(t)
lines = [f"brew tap {x}" for x in t]
if f: lines.append("brew install " + " ".join(f))
if c: lines.append("brew install --cask " + " ".join(c))
if m:
    lines.append("# App Store: " + ", ".join(x["name"] for x in m))
    lines.append("mas install " + " ".join(str(x["id"]) for x in m))
spans = "".join(f'<span class="ln{" c" if l.startswith("#") else ""}">{html.escape(l, quote=False)}</span>' for l in lines)
counts = f'{len(f)} formulae, {len(c)} casks' + (f', {len(m)} App Store apps' if m else '')
desc = b["description"][0].lower() + b["description"][1:]
ind = " " * 18
block = f'''<!-- fallback:start (server-rendered {b["label"]} bundle for readers without JavaScript) -->
{ind}<p class="bundle-summary">{b["label"]} bundle: {html.escape(desc)} {counts}.</p>
{ind}<figure class="cmd">
{ind}  <div class="cmd-bar"><figcaption>{b["label"]} bundle</figcaption><button type="button" class="copy">Copy</button></div>
{ind}  <pre><code>{spans}</code></pre>
{ind}</figure>
{ind}<p class="muted">Turn on JavaScript to choose the Minimal or Full bundle here, or use the <a href="homebrew.html">Homebrew catalogue</a>.</p>
{ind}<!-- fallback:end -->'''
p = root / "docs/index.html"
s = p.read_text()
new = re.sub(r"<!-- fallback:start.*?<!-- fallback:end -->", lambda _: block, s, flags=re.S)
if "--check" in sys.argv:
    if new != s:
        sys.exit("docs/index.html fallback block is stale: run python3 scripts/render_index_fallback.py")
    print("index fallback up to date")
else:
    p.write_text(new)
    print("changed" if new != s else "unchanged", counts)
