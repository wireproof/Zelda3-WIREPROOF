#!/usr/bin/env python3
"""Build standalone arm64 iOS and Simulator apps with the installed Apple SDK."""
from pathlib import Path
import subprocess, shutil, plistlib, sys, concurrent.futures, hashlib, json, zipfile
P=Path(__file__).resolve().parents[1]
mode=sys.argv[1] if len(sys.argv)>1 else 'device'
assert mode in ('device','simulator')
sdk='iphoneos' if mode=='device' else 'iphonesimulator'
target='arm64-apple-ios15.0'+('-simulator' if mode=='simulator' else '')
def command(*args): return subprocess.check_output(args,text=True).strip()
sysroot=command('xcrun','--sdk',sdk,'--show-sdk-path')
clang=command('xcrun','--sdk',sdk,'--find','clang')
B=P/'build'/('ios-'+mode);B.mkdir(parents=True,exist_ok=True)
app=B/'Zelda3.app';app.mkdir(exist_ok=True)
exclude={'main.c','config.c','opengl.c','glsl_shader.c'}
sources=[s for s in (P/'src').glob('*.c') if s.name not in exclude]
sources+=list((P/'snes').glob('*.c'))+[P/'third_party/opus-1.3.1-stripped/opus_decoder_amalgam.c',P/'platform/native/zelda_native.c']
sources+=list((P/'platform/ios').glob('*.m'))
common=[clang,'-target',target,'-isysroot',sysroot,'-O2','-g','-fno-strict-aliasing','-DZELDA_NATIVE_PLATFORM=1','-I',str(P)]
def compile(s):
 obj=B/(str(s.relative_to(P)).replace('/','_')+'.o')
 args=common+(['-fobjc-arc'] if s.suffix=='.m' else ['-std=c11'])
 result=subprocess.run(args+['-c',str(s),'-o',str(obj)],capture_output=True,text=True)
 if result.returncode: raise RuntimeError(str(s)+'\n'+result.stderr)
 if result.stderr: print(result.stderr)
 return str(obj)
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool: objects=list(pool.map(compile,sources))
frameworks=['UIKit','CoreGraphics','Foundation','QuartzCore','AVFoundation','AudioToolbox','GameController']
args=common+objects+['-Wl,-dead_strip','-o',str(app/'Zelda3')]
for f in frameworks: args+=['-framework',f]
subprocess.run(args,check=True)
shutil.copy2(P/'zelda3_assets.dat',app/'zelda3_assets.dat')
shutil.copy2(P/'LICENSE.txt',app/'LICENSE.txt')
shutil.copy2(P/'third_party/opus-1.3.1-stripped/COPYING',app/'Opus-COPYING.txt')
if mode=='simulator': shutil.copytree(P/'saves/ref',app/'ref',dirs_exist_ok=True)
info=dict(CFBundleIdentifier='com.wireproof.lozalttp',CFBundleName='Zelda3',CFBundleDisplayName='Zelda',CFBundleExecutable='Zelda3',CFBundlePackageType='APPL',CFBundleShortVersionString='0.2.2',CFBundleVersion='4',MinimumOSVersion='15.0',UIDeviceFamily=[1,2],UILaunchScreen={},UIStatusBarHidden=True,UIViewControllerBasedStatusBarAppearance=True,UIFileSharingEnabled=True,LSSupportsOpeningDocumentsInPlace=True,UIRequiresFullScreen=True,UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],CFBundleSupportedPlatforms=['iPhoneOS' if mode=='device' else 'iPhoneSimulator'],DTPlatformName=sdk,DTSDKName=Path(sysroot).stem.lower())
info['UIApplicationSceneManifest']={'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Game','UISceneDelegateClassName':'SceneDelegate'}]}}
info['UISupportedInterfaceOrientations~ipad']=info['UISupportedInterfaceOrientations']+['UIInterfaceOrientationPortraitUpsideDown']
for icon in (P/'platform/ios/icons').glob('AppIcon*.png'): shutil.copy2(icon,app/icon.name)
info['CFBundleIcons']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon120','AppIcon180'],'UIPrerenderedIcon':True}}
info['CFBundleIcons~ipad']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon76','AppIcon152','AppIcon167'],'UIPrerenderedIcon':True}}
info['CFBundleIconFiles']=['AppIcon120','AppIcon180']
with (app/'Info.plist').open('wb') as f: plistlib.dump(info,f)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
if mode=='device':
 out=P/'dist/LoZ-ALttP-WIREPROOF-iOS-v0.2.2-build4.ipa';out.parent.mkdir(exist_ok=True)
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for f in app.rglob('*'):
   if f.is_file():z.write(f,'Payload/Zelda3.app/'+str(f.relative_to(app)))
 receipt={'file':out.name,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'architecture':'arm64','minimum_iOS':'15.0','device_families':['iPhone','iPad'],'signing':'ad-hoc; requires LiveContainer or signing for device install','runtime_on_physical_device':'not tested'}
 (P/'dist/ios-manifest.json').write_text(json.dumps(receipt,indent=2));print(out)
else: print(app)
