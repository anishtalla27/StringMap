#!/usr/bin/env python3
"""Reproduce StringMap's CC0 guitar bank from the pinned FreePats source.

No SONiVOX/Creative samples are used. Guitar PCM is unchanged; bank mappings
are adapted and an original synthesized metronome click is appended.
"""
import argparse
import hashlib
import math
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
SOURCE_SHA='0d4c08ea8c1c8924b3829084b0c8778f6d6b906f331e44fde51bc159f76b03b9'
TARGET=ROOT/'apps/ios/StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2'


def chunk(tag,data): return tag+struct.pack('<I',len(data))+data+(b'\0' if len(data)%2 else b'')
def chunks(data):
    result={};pos=0
    while pos<len(data):
        tag,n=struct.unpack_from('<4sI',data,pos);result[tag]=data[pos+8:pos+8+n];pos+=8+n+n%2
    return result

def name(value): return value.encode('ascii').ljust(20,b'\0')[:20]
def gen(operator,amount): return struct.pack('<HH',operator,amount & 65535)


def build(source):
    data=source.read_bytes()
    if hashlib.sha256(data).hexdigest()!=SOURCE_SHA: raise ValueError('Unexpected FreePats source soundfont')
    sections={};pos=12
    while pos<len(data):
        tag,n=struct.unpack_from('<4sI',data,pos);value=data[pos+8:pos+8+n];pos+=8+n+n%2
        if tag!=b'LIST': raise ValueError('Unexpected source structure')
        sections[value[:4]]=chunks(value[4:])
    info,sdta,pdta=(sections[k] for k in [b'INFO',b'sdta',b'pdta'])
    # The sampled guitar has no loops. Its edge zones are extended only for
    # notation audition outside the normal guitar range; the synthesizer
    # preserves each requested MIDI pitch by resampling the nearest sample.
    igen=bytearray(pdta[b'igen'][:-4])
    for offset in range(0,len(igen),4):
        operator,amount=struct.unpack_from('<HH',igen,offset)
        if operator==43:
            low,high=amount&255,amount>>8
            if low==29: low=0
            if high==88: high=127
            struct.pack_into('<HH',igen,offset,43,low|(high<<8))
    sample_id=len(pdta[b'shdr'])//46-1
    sample_start=len(sdta[b'smpl'])//2
    rate=44100;count=int(rate*.06)
    click=[int(18000*math.sin(2*math.pi*1700*i/rate)*math.exp(-i/(rate*.009))*min(1,i/24)) for i in range(count)]
    sdta[b'smpl']+=struct.pack('<'+'h'*(count+46),*(click+[0]*46))
    sample_header=struct.pack('<20sIIIIIBbHH',name('StringMap click'),sample_start,sample_start+count,sample_start,sample_start+count,rate,33,0,0,1)
    pdta[b'shdr']=pdta[b'shdr'][:-46]+sample_header+bytes(46)
    instrument_id=len(pdta[b'inst'])//22-1
    bag_start=len(pdta[b'ibag'])//4-1
    generator_start=len(igen)//4
    click_generators=gen(43,33|(33<<8))+gen(38,-5000)+gen(54,0)+gen(58,33)+gen(53,sample_id)
    pdta[b'igen']=bytes(igen)+click_generators+bytes(4)
    pdta[b'ibag']=pdta[b'ibag'][:-4]+struct.pack('<HHHH',generator_start,0,generator_start+len(click_generators)//4,0)
    pdta[b'inst']=pdta[b'inst'][:-22]+struct.pack('<20sH',name('StringMap click'),bag_start)+struct.pack('<20sH',name('EOI'),bag_start+1)
    # Program 25 is an alias for older saved alphaTex; new scores use nylon 24.
    presets=[('Classical guitar',0,0,0),('Nylon guitar',24,0,0),('Guitar legacy',25,0,0),('Metronome',0,128,instrument_id)]
    phdr=b'';pbag=b'';pgen=b''
    for index,(title,program,bank,instrument) in enumerate(presets):
        phdr+=struct.pack('<20sHHHIII',name(title),program,bank,index,0,0,0)
        pbag+=struct.pack('<HH',len(pgen)//4,0)
        pgen+=(gen(48,100) if bank==0 else b'')+gen(41,instrument)
    phdr+=struct.pack('<20sHHHIII',name('EOP'),0,0,len(presets),0,0,0)
    pbag+=struct.pack('<HH',len(pgen)//4,0)
    pdta.update({b'phdr':phdr,b'pbag':pbag,b'pgen':pgen+bytes(4)})
    info[b'INAM']=b'StringMap Classical Guitar\0'
    info[b'ICOP']=b'CC0 1.0. FreePats Roberto 2019; StringMap metronome and bank adaptation 2026.\0'
    body=b'sfbk'+b''.join(chunk(b'LIST',key+b''.join(chunk(tag,value) for tag,value in table.items())) for key,table in [(b'INFO',info),(b'sdta',sdta),(b'pdta',pdta)])
    output=chunk(b'RIFF',body);TARGET.write_bytes(output)
    print(hashlib.sha256(output).hexdigest(),TARGET)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('source',type=Path)
    build(parser.parse_args().source)
