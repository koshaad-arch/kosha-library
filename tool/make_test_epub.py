# Builds a small EPUB 3 (nav, two chapters, an image) for the CI parser check.
import sys, zipfile, base64
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
ch = lambda n, extra='': f'''<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter {n}</title><link rel="stylesheet" href="../css/s.css"/></head><body><h1>Chapter {n}</h1>{extra}<p>{"It is a truth universally acknowledged that a reader in possession of a good book must be in want of a quiet corner. " * 40}</p><p><a href="ch2.xhtml#x">link</a></p></body></html>'''
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip')
    z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr('OEBPS/content.opf', '''<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">test</dc:identifier><dc:title>Test Book</dc:title><dc:creator>Jane Tester</dc:creator><dc:language>en</dc:language></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/><item id="img" href="images/cover.png" media-type="image/png" properties="cover-image"/></manifest>
<spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>''')
    z.writestr('OEBPS/nav.xhtml', '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="text/ch1.xhtml">Chapter One</a></li><li><a href="text/ch2.xhtml">Chapter Two</a><ol><li><a href="text/ch2.xhtml#x">Part 2a</a></li></ol></li></ol></nav></body></html>')
    z.writestr('OEBPS/text/ch1.xhtml', ch(1, '<img src="../images/cover.png" alt=""/>'))
    z.writestr('OEBPS/text/ch2.xhtml', ch(2))
    z.writestr('OEBPS/images/cover.png', png)
print('made', sys.argv[1])
