"""Verify every original event through Swift and the actual alphaTab MIDI writer."""
import json, subprocess, hashlib
from pathlib import Path
r=Path(__file__).resolve().parents[1]
folder=r/'apps/ios/StringMap/Resources/Exercises'
output=r/'artifacts/offline-exercise-verification';output.mkdir(exist_ok=True)
catalog=json.loads((folder/'catalog.json').read_text());results=[]
cli=r/'apps/ios/Packages/StringMapCore/.build/debug/stringmap-check'
for entry in catalog:
    path=folder/(entry['resource']+'.musicxml')
    native=json.loads(subprocess.check_output([str(cli),str(path)]))
    assert native['parsed'] and native['tabPlayable'],(entry['title'],native)
    expected=entry['events'];actual=[]
    for measure in native['score']['measures']:
        for wrapped in measure['events']:
            note=wrapped.get('note');event=(note or wrapped['rest'])['_0']
            actual.append({k:event.get(k) for k in ['id','measureIndex','onsetQuarters','durationQuarters','midi']})
    assert expected==actual,entry['title']
    playback=json.loads(subprocess.check_output(['node',str(r/'scripts/verify-score-playback.mjs')],input=json.dumps(native).encode()))
    assert all(playback[k] is True for k in ['tabPitchExact','allNotesAssigned','distinctStrings'])
    for k in ['alphaTex','notationAlphaTex']:
        assert all(playback[k][key] is True for key in ['parsed','exactPlayback','sourceIdentitiesPreserved']), (entry['title'],playback)
    (output/(entry['resource']+'-native.json')).write_text(json.dumps(native,indent=2)+'\n')
    (output/(entry['resource']+'-playback.json')).write_text(json.dumps(playback,indent=2)+'\n')
    results.append(dict(resource=entry['resource'],title=entry['title'],sha256=hashlib.sha256(path.read_bytes()).hexdigest(),events=len(expected),notes=sum(e['midi'] is not None for e in expected),playback=playback))
assert len(results)==18
(output/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
print(f'PASS: {len(results)} pieces, {sum(x["events"] for x in results)} events; exact authored timing, MIDI, source IDs and fret pitches')
