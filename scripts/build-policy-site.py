from pathlib import Path
import html
from markdown_it import MarkdownIt

root=Path(__file__).resolve().parents[1];out=root/'docs/site';out.mkdir(exist_ok=True)
markdown=MarkdownIt('commonmark',{'html':False})
style='''*{box-sizing:border-box}html{color-scheme:light dark}body{margin:0;background:#fffdf7;color:#17140f;font:18px/1.65 system-ui,-apple-system,sans-serif}main,nav,footer{max-width:760px;margin:auto;padding:24px}nav{display:flex;flex-wrap:wrap;gap:22px;border-bottom:1px solid #d7ccbc}a{color:#a73120;text-underline-offset:3px}a:focus-visible{outline:3px solid #a73120;outline-offset:4px}h1,h2,h3{line-height:1.25}h1{font-family:Georgia,serif;font-size:2.3rem}h2{font-size:1.3rem;margin-top:2.5rem}p,li{overflow-wrap:anywhere}footer{font-size:.85rem;border-top:1px solid #d7ccbc}.skip{position:absolute;left:-9999px}.skip:focus{left:12px;top:12px;background:#fff;padding:12px}pre{overflow:auto}table{display:block;overflow:auto}code{font-size:.85em}@media(prefers-color-scheme:dark){body{background:#1e1812;color:#efe6d6}a{color:#f3957c}nav,footer{border-color:#665647}}'''
(out/'style.css').write_text(style)
nav='<a class="skip" href="#content">Skip to content</a><nav aria-label="Main"><a href="./">StringMap</a><a href="privacy.html">Privacy</a><a href="support.html">Support</a><a href="licenses.html">Licenses</a></nav>'

def page(filename,title,body):
    value=f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>{html.escape(title)} · StringMap</title><link rel="stylesheet" href="style.css"></head><body>{nav}<main id="content">{body}</main><footer>© 2026 Anish Talla. <a href="mailto:stringmap.support@gmail.com">Contact support</a></footer></body></html>'
    (out/filename).write_text(value)
for name in ['privacy','support']:
    page(name+'.html',name.title(),markdown.render((root/'docs'/f'{name}.md').read_text()))
licenses=(root/'apps/ios/StringMap/Resources/Legal/licenses.md').read_text()
page('licenses.html','Licenses',markdown.render(licenses))
page('index.html','Guitar notation and practice','<h1>StringMap</h1><p>Guitar notation, tablature, and practice for iPhone and iPad.</p><p>Learn with 12 original beginner lessons, an interactive teaching fretboard, and optional tablature. Practice with 18 original single-note guitar exercises, synchronized notation, playback, and fretboard positions. All music works offline.</p><p>Read the privacy policy, get support, or review the bundled licenses using the links above.</p>')
(out/'.nojekyll').write_text('')
print('Built accessible static policy pages with no scripts or remote assets.')
