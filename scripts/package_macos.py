from pathlib import Path
import subprocess, shutil, plistlib, hashlib, json, tempfile
p=Path(__file__).resolve().parents[1]
def run(*args, **kw): subprocess.run(args,check=True,**kw)
app=p/'dist/Zelda3 WIREPROOF.app'
mac=app/'Contents/MacOS';res=app/'Contents/Resources';libs=app/'Contents/Frameworks'
for d in (mac,res,libs): d.mkdir(parents=True,exist_ok=True)
shutil.copy2(p/'build/zelda3',mac/'zelda3-engine')
lib=Path('/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib')
if (libs/lib.name).exists(): (libs/lib.name).chmod(0o755)
shutil.copy2(lib,libs/lib.name)
(libs/lib.name).chmod(0o755)
run('install_name_tool','-change',str(lib),'@executable_path/../Frameworks/'+lib.name,str(mac/'zelda3-engine'))
run('install_name_tool','-id','@rpath/'+lib.name,str(libs/lib.name))
run('clang','-fobjc-arc','-framework','Foundation','-framework','AppKit',str(p/'platform/macos/launcher.m'),'-o',str(mac/'Zelda3'))
shutil.copy2(p/'zelda3_assets.dat',res/'zelda3_assets.dat')
shutil.copy2(p/'LICENSE.txt',res/'LICENSE.txt')
shutil.copy2('/opt/homebrew/opt/sdl2/LICENSE.txt',res/'SDL2-LICENSE.txt')
shutil.copy2(p/'third_party/opus-1.3.1-stripped/COPYING',res/'Opus-COPYING.txt')
config=(p/'zelda3.ini').read_text().replace('EnhancedMode7 = 1','EnhancedMode7 = 0').replace('NoSpriteLimits = 1','NoSpriteLimits = 0')
(res/'zelda3.ini').write_text(config)
with (app/'Contents/Info.plist').open('wb') as f:
 plistlib.dump(dict(CFBundleName='Zelda3 WIREPROOF',CFBundleDisplayName='Zelda3 WIREPROOF',CFBundleIdentifier='com.wireproof.zelda3',CFBundleExecutable='Zelda3',CFBundlePackageType='APPL',CFBundleShortVersionString='0.1.0',CFBundleVersion='1',LSMinimumSystemVersion='15.0',NSHighResolutionCapable=True),f)
for binary in (libs/lib.name,mac/'zelda3-engine'):
 run('codesign','--force','--sign','-',str(binary))
run('codesign','--force','--sign','-',str(app))
run('codesign','--verify','--deep','--strict',str(app))
qa=p/'build/qa';qa.mkdir(exist_ok=True)
results=[]
with tempfile.TemporaryDirectory(prefix='zelda3-smoke-') as td:
 t=Path(td); shutil.copy2(res/'zelda3.ini',t/'zelda3.ini');shutil.copy2(p/'zelda3_assets.dat',t/'zelda3_assets.dat')
 shutil.copytree(p/'saves/ref',t/'saves/ref')
 assert len(list((t/'saves/ref').glob('Chapter *.sav')))==13
 for chapter in range(14):
  result=subprocess.run([str(p/'build/zelda3_smoke'),str(chapter),'1200' if chapter==0 else '300',str(qa/f'chapter-{chapter:02}.bmp')],cwd=t,text=True,capture_output=True,timeout=60)
  results.append(dict(chapter=chapter,returncode=result.returncode,stdout=result.stdout,stderr=result.stderr))
  print(chapter,result.returncode,result.stdout[-180:],result.stderr[-200:],flush=True)
 (qa/'results.json').write_text(json.dumps(results,indent=2))
 if any(r['returncode'] for r in results): raise SystemExit('Smoke checks failed')
zipfile=p/'dist/Zelda3-WIREPROOF-macOS-arm64-0.1.0.zip'
run('ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(zipfile))
manifest=dict(upstream_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=p,text=True).strip(),asset_sha256=hashlib.sha256((p/'zelda3_assets.dat').read_bytes()).hexdigest(),archive_sha256=hashlib.sha256(zipfile.read_bytes()).hexdigest(),tests='boot 1200 frames plus 300 frames at each of 13 upstream chapter snapshots; rendering and audio generation; not full playthrough',platform='macOS arm64',signing='ad-hoc, not notarized')
(p/'dist/manifest.json').write_text(json.dumps(manifest,indent=2))
print(zipfile)
