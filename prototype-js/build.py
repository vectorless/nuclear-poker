#!/usr/bin/env python3
"""Assemble the single-file game: inline CSS, engine, JS and base64 card art into nuclear-poker.html."""
import base64, json, pathlib

root = pathlib.Path(__file__).parent
src = root / 'src'
assets = root / 'assets'

imgs = {}
for p in sorted(assets.glob('*.png')):
    imgs[p.stem] = 'data:image/png;base64,' + base64.b64encode(p.read_bytes()).decode()

html = (src / 'index.template.html').read_text()
html = html.replace('/*{{CSS}}*/', (src / 'style.css').read_text())
html = html.replace('/*{{ENGINE}}*/', (src / 'engine.js').read_text())
html = html.replace('/*{{ASSETS}}*/', 'window.CARD_IMG = ' + json.dumps(imgs) + ';')
html = html.replace('/*{{UI}}*/', (src / 'ui.js').read_text())

out = root / 'nuclear-poker.html'
out.write_text(html)
print(f'wrote {out} ({out.stat().st_size/1024:.0f} KB, {len(imgs)} card images)')
