"""Notify IndexNow search engines after the site's changed pages are live."""
from pathlib import Path
import json
import urllib.request
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
key = (root / 'docs/indexnow-key.txt').read_text().strip()
location = 'https://greggroll.github.io/VO2Cue/indexnow-key.txt'
with urllib.request.urlopen(location, timeout=30) as response:
    if response.read().decode().strip() != key:
        raise SystemExit('Live verification file does not match. Publish first.')
urls = [el.text for el in ET.parse(root / 'docs/sitemap.xml').findall('.//{*}loc')]
payload = {'host': 'greggroll.github.io', 'key': key, 'keyLocation': location, 'urlList': urls}
request = urllib.request.Request('https://api.indexnow.org/indexnow', data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json; charset=utf-8'})
with urllib.request.urlopen(request, timeout=30) as response:
    print(json.dumps({'status': response.status, 'urls': urls, 'meaning': 'Received; key validation pending' if response.status == 202 else 'Received; indexing is not guaranteed'}))
