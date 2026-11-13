import argparse
import json
import plistlib
import sys
from pathlib import Path
parser=argparse.ArgumentParser(description='Write release or explicitly labeled test bundle metadata.')
parser.add_argument('contents',nargs='?',default='../实况工坊.app/Contents')
parser.add_argument('--test',metavar='PURPOSE',help='Label this bundle as a test build, with a short purpose.')
args=parser.parse_args()
if args.test is not None and (not args.test.strip() or len(args.test.strip())>40):
    parser.error('Test purpose must contain 1–40 characters.')
app=Path(args.contents)
base=dict(CFBundleDevelopmentRegion='zh-Hans',CFBundleLocalizations=['zh-Hans','en'],CFBundleVersion='43',CFBundleShortVersionString='1.7.1',LSMinimumSystemVersion='14.0')
test_suffix=f" · 测试版 {base['CFBundleShortVersionString']} · {args.test.strip()}" if args.test else ''
main=dict(base,CFBundleIdentifier='local.livephotostudio.app',CFBundleName='实况工坊'+test_suffix,CFBundleDisplayName='实况工坊'+test_suffix,CFBundleExecutable='LivePhotoStudio',CFBundleIconFile='AppIcon',CFBundlePackageType='APPL',NSPrincipalClass='NSApplication',NSHumanReadableCopyright='© 2026 latter404',CFBundleURLTypes=[dict(CFBundleURLName='livephotostudio.open',CFBundleURLSchemes=['livephotostudio'])],NSPhotoLibraryAddUsageDescription='将你生成的实况照片或 GIF 添加到照片图库。',CFBundleDocumentTypes=[dict(CFBundleTypeName='Video',CFBundleTypeRole='Viewer',LSHandlerRank='Alternate',LSItemContentTypes=['public.movie'])])
ext=dict(base,CFBundleIdentifier='local.livephotostudio.app.finder',CFBundleName='实况工坊 Finder',CFBundleExecutable='LivePhotoFinder',CFBundlePackageType='XPC!',NSExtension=dict(NSExtensionPointIdentifier='com.apple.FinderSync',NSExtensionPrincipalClass='LivePhotoFinder'))
if args.test:
    # Independent settings, history, and URL scheme; never claim the release's file associations.
    main['CFBundleIdentifier'] = 'local.livephotostudio.test'
    ext['CFBundleIdentifier'] = main['CFBundleIdentifier'] + '.finder'
    ext['CFBundleName'] += test_suffix
    main['CFBundleURLTypes'][0]['CFBundleURLSchemes'] = ['livephotostudio-test']
    main.pop('CFBundleDocumentTypes', None)
(app/'Info.plist').write_bytes(plistlib.dumps(main))
(app/'PlugIns/LivePhotoFinder.appex/Contents/Info.plist').write_bytes(plistlib.dumps(ext))

def strings_file(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    quote=lambda value:json.dumps(value,ensure_ascii=False)
    path.write_text('\n'.join(f'{quote(key)} = {quote(value)};' for key,value in values.items())+'\n',encoding='utf-8')

# Native privacy prompts and Finder names follow macOS's selected app language.
# The editor's runtime language preference is intentionally app-local.
localized={
    'zh-Hans':dict(CFBundleDisplayName='实况工坊',CFBundleName='实况工坊',NSHumanReadableCopyright='© 2026 latter404',NSPhotoLibraryAddUsageDescription='将你生成的实况照片或 GIF 添加到照片图库。',Video='视频'),
    'en':dict(CFBundleDisplayName='LivePhoto Studio',CFBundleName='LivePhoto Studio',NSHumanReadableCopyright='© 2026 latter404',NSPhotoLibraryAddUsageDescription='Add the Live Photos or GIFs you create to your Photos library.',Video='Video'),
}
for language, values in localized.items():
    if args.test:
        suffix=test_suffix if language=='zh-Hans' else f" · Test {base['CFBundleShortVersionString']} · {args.test.strip()}"
        values['CFBundleDisplayName']+=suffix
        values['CFBundleName']+=suffix
    strings_file(app/'Resources'/f'{language}.lproj'/'InfoPlist.strings',values)
    finder_name='实况工坊 Finder' if language=='zh-Hans' else 'LivePhoto Studio Finder'
    if args.test: finder_name += suffix
    resources=app/'PlugIns/LivePhotoFinder.appex/Contents/Resources'/f'{language}.lproj'
    strings_file(resources/'InfoPlist.strings',dict(CFBundleDisplayName=finder_name,CFBundleName=finder_name))
    strings_file(resources/'Localizable.strings',{'Convert to Live Photo':('转为实况照片' if language=='zh-Hans' else 'Convert to Live Photo') + (('（测试版）' if language=='zh-Hans' else ' (Test)') if args.test else '')})
Path('FinderExtension/entitlements.plist').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.files.user-selected.read-only':True}))
