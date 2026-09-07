#!/usr/bin/env python3
"""Fail a distribution build when required release configuration is missing."""
import os
import sys
import subprocess
from pathlib import Path
from urllib.parse import urlparse


def validate(environment):
    errors=[]
    for key in ['PRIVACY_POLICY_URL','SUPPORT_URL']:
        value=environment.get(key,'');url=urlparse(value)
        if url.scheme!='https' or not url.hostname or url.username or url.password or url.fragment or url.query or '$(' in value or url.hostname in {'localhost','127.0.0.1','example.com'} or url.hostname.endswith(('.invalid','.test','.example')):
            errors.append(key+' must be a real public HTTPS URL.')
    if environment.get('CODE_SIGNING_ALLOWED') != 'NO' and not environment.get('DEVELOPMENT_TEAM'):errors.append('DEVELOPMENT_TEAM is required for distribution signing.')
    if environment.get('CODE_SIGN_ENTITLEMENTS'):errors.append('Offline Release must not request scanning App Attest entitlements.')
    return errors

if __name__=='__main__':
    if os.environ.get('CONFIGURATION')!='Release':sys.exit(0)
    errors=validate(os.environ)
    if errors:
        for error in errors:print('error: '+error,file=sys.stderr)
        sys.exit(1)
    root=Path(__file__).resolve().parents[3]
    for name in ['verify-songbook-sources.py', 'verify-songbook-harmony.py']:
        subprocess.run([sys.executable,str(root/'scripts'/name)],check=True)
    print('Release configuration is present. URL contents, signing, archive validation, device QA and TestFlight remain separate gates.')
