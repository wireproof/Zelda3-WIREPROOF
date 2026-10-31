#!/usr/bin/env python3
"""Sign the native device build with an installed Apple development identity/profile."""
import argparse,hashlib,json,plistlib,shutil,subprocess,zipfile
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--profile',required=True,type=Path);parser.add_argument('--identity',required=True);parser.add_argument('--device',required=True);a=parser.parse_args()
p=Path(__file__).resolve().parents[1]
d=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(a.profile)]))
assert a.identity.upper() in [hashlib.sha1(c).hexdigest().upper() for c in d['DeveloperCertificates']], 'Certificate not in profile'
assert a.device in d['ProvisionedDevices'], 'Device not provisioned'
source=p/'build/ios-device/Zelda3.app';info=plistlib.loads((source/'Info.plist').read_bytes());bundle=info['CFBundleIdentifier'];team=d['TeamIdentifier'][0]
allowed=d['Entitlements']['application-identifier'];identifier=team+'.'+bundle
assert allowed==identifier or (allowed.endswith('.*') and identifier.startswith(allowed[:-1])), 'Profile does not allow bundle ID'
app=p/'build/ios-signed/Zelda3.app';shutil.copytree(source,app,dirs_exist_ok=True);shutil.copy2(a.profile,app/'embedded.mobileprovision')
e={'application-identifier':identifier,'com.apple.developer.team-identifier':team,'get-task-allow':True,'keychain-access-groups':[identifier]}
ent=app.parent/'entitlements.plist';ent.write_bytes(plistlib.dumps(e))
subprocess.run(['codesign','--force','--sign',a.identity,'--entitlements',str(ent),'--generate-entitlement-der',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
out=p/('dist/LoZ-ALttP-WIREPROOF-iOS-v'+info['CFBundleShortVersionString']+'-build'+info['CFBundleVersion']+'-signed.ipa')
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 for f in app.rglob('*'):
  if f.is_file():z.write(f,'Payload/Zelda3.app/'+str(f.relative_to(app)))
print(out);print(hashlib.sha256(out.read_bytes()).hexdigest())
