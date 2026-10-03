#!/usr/bin/env python3
"""Copy exact production Watch view/types to an isolated no-network watchOS app."""
import argparse, hashlib, json, pathlib, struct, subprocess, zlib
root = pathlib.Path(__file__).resolve().parents[2]
a = argparse.ArgumentParser(); a.add_argument('--output', required=True); a.add_argument('--ref', default='WORKTREE'); o = a.parse_args()
out = pathlib.Path(o.output); sources = out/'Sources'; sources.mkdir(parents=True, exist_ok=True)
manifest = {'source_ref': o.ref, 'checkout_sha': subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(), 'boundary':'Actual unchanged WatchPhotoView and production Codable/read model; synthetic connector and photo IO. Does not prove WatchConnectivity, physical Crown input, complications or device migration.', 'files': []}
for path in ['BubuWatch/Views/WatchPhotoView.swift','WatchShared/WatchBrowseSelection.swift','WatchShared/WatchLink.swift']:
    data = (root/path).read_bytes() if o.ref == 'WORKTREE' else subprocess.check_output(['git','show',o.ref+':'+path],cwd=root)
    (sources/pathlib.Path(path).name).write_bytes(data)
    manifest['files'].append({'path':path,'sha256':hashlib.sha256(data).hexdigest(),'transformations':[]})
(sources/'Fixture.swift').write_bytes((root/'scripts/watch-product-audit/Fixture.swift').read_bytes())
# Deterministic synthetic illustration only, no user image or family metadata.
w,h=200,230
raw=bytearray()
for y in range(h):
    raw.append(0)
    for x in range(w):
        color = (110,187,216) if y < 130 else (54,126,88)
        if (x-151)**2+(y-48)**2 < 23**2: color=(249,219,118)
        if y > 80+abs(x-80)*.6: color=(69,134,116)
        if y > 150: color=(61,101,82)
        raw.extend(color)
def chunk(t,d): return struct.pack('!I',len(d))+t+d+struct.pack('!I',zlib.crc32(t+d)&0xffffffff)
(sources/'synthetic.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
(out/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
(out/'project.yml').write_text('''name: WatchProductAudit
options:
  bundleIdPrefix: org.bubu.audit
settings:
  base:
    SWIFT_VERSION: "6.0"
    CODE_SIGNING_ALLOWED: NO
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  WatchProductAudit:
    type: application
    platform: watchOS
    deploymentTarget: "26.0"
    sources: [Sources]
    info:
      path: Info.plist
      properties:
        CFBundleDisplayName: Synthetic audit
        WKApplication: true
        WKWatchOnly: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: org.bubu.audit.watch-product
        TARGETED_DEVICE_FAMILY: "4"
schemes:
  WatchProductAudit:
    build:
      targets:
        WatchProductAudit: all
    run:
      config: Debug
''')
