"""Release bundle checks; runs on the build machine, not the recipient's Mac."""
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

bundle=Path(sys.argv[1])
expected_sdk=sys.argv[2]

def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()

def require(condition, message):
    if not condition:
        raise SystemExit(message)

report={"version":None,"minimumOS":"14.0","sdk":expected_sdk,"binaries":[],"signature":"ad-hoc; not notarized"}
for app in [bundle,bundle/'Contents/PlugIns/LivePhotoFinder.appex']:
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    require(info.get('LSMinimumSystemVersion')=='14.0',f'Unexpected minimum OS: {app}')
    if report['version'] is None: report['version']=info['CFBundleShortVersionString']
    require(info['CFBundleShortVersionString']==report['version'],'App and extension versions differ')
    binary=app/'Contents/MacOS'/info['CFBundleExecutable']
    arches=command('lipo','-archs',str(binary)).split()
    require(set(arches)=={'arm64','x86_64'},f'Missing universal architecture: {binary}')
    for arch in arches:
        build=command('xcrun','vtool','-arch',arch,'-show-build',str(binary))
        require(re.search(r'\bminos 14\.0\b',build),f'Wrong deployment target: {binary} {arch}')
        require(re.search(r'\bsdk '+re.escape(expected_sdk)+r'\b',build),f'SDK stamp mismatch: {binary} {arch}')
        linked=command('otool','-arch',arch,'-L',str(binary))
        libraries=[line.strip().split(' (')[0] for line in linked.splitlines() if line.startswith('\t')]
        require(all(p.startswith(('/System/Library/','/usr/lib/')) for p in libraries),f'Non-system dependency: {binary} {arch}: {libraries}')
        commands=command('otool','-arch',arch,'-l',str(binary))
        rpaths=re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset',commands)
        require(all(p in ('/usr/lib/swift','@loader_path','@executable_path') or p.startswith(('@executable_path/','@loader_path/')) for p in rpaths),f'Build-machine rpath: {rpaths}')
        report['binaries'].append({'name':binary.name,'architecture':arch,'systemLibrariesOnly':True,'rpaths':rpaths})
command('codesign','--verify','--deep','--strict',str(bundle))
require((bundle/'Contents/Resources/AppIcon.icns').is_file(),'Missing icon')
print(json.dumps(report,ensure_ascii=False,indent=2))
