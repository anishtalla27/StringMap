"""Inspect the built Release app, not just source-level feature flags."""
import argparse,json,plistlib,subprocess
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('app',type=Path);args=parser.parse_args();app=args.app
info=plistlib.loads((app/'Info.plist').read_bytes())
for key in ['OMRServiceURL','NSCameraUsageDescription','NSPhotoLibraryUsageDescription','NSMicrophoneUsageDescription']:
 assert key not in info,key
privacy=plistlib.loads((app/'PrivacyInfo.xcprivacy').read_bytes())
assert privacy['NSPrivacyCollectedDataTypes']==[] and privacy['NSPrivacyTracking'] is False
symbols=subprocess.check_output(['nm',str(app/info['CFBundleExecutable'])],text=True,stderr=subprocess.DEVNULL)
for name in ['SheetMusicScanView','OMRClient','OMRAuthentication','CameraPicker','TutorialPitchListener','TutorialYIN','TutorialPitchMatch']:
 assert name not in symbols,name
catalog=json.loads((app/'Exercises/catalog.json').read_text());assert len(catalog)==18
assert {e['resource'] for e in catalog}=={p.stem for p in (app/'Exercises').glob('*.musicxml')}
for name in ['privacy','support']:
 content=(app/'Legal'/f'{name}.md').read_text()
 assert 'stringmap.support@gmail.com' in content
course=json.loads((app/'Tutorial/course.json').read_text())
assert course['version']==1 and len(course['lessons'])==24
phrases=[p['id'] for lesson in course['lessons'] for p in lesson['phrases']]
assert len(set(phrases))==40
assert set(phrases)=={p.stem for p in (app/'Tutorial').glob('*.musicxml')}
print(json.dumps({'tutorialLessons':len(course['lessons']),'tutorialExamples':len(phrases),'microphonePermissionAbsent':True,'listeningSymbolsAbsent':True,'scannerSymbolsAbsent' :True,'photoPermissionsAbsent':True,'recognitionURLAbsent':True,'collectedDataTypes':[],'bundledExercises':18}))
