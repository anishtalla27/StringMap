import struct, numpy as np
GEN_NAMES={43:'keyRange',44:'velRange',53:'sampleID',58:'overridingRootKey',51:'coarseTune',52:'fineTune',48:'initialAttenuation',17:'pan',41:'instrument',54:'sampleModes',38:'releaseVolEnv',34:'attackVolEnv',36:'decayVolEnv',37:'sustainVolEnv',0:'startAddrsOffset',1:'endAddrsOffset',4:'startAddrsCoarseOffset',12:'endAddrsCoarseOffset'}
def chunks(data):
    r={};p=0
    while p<len(data):
        t,n=struct.unpack_from('<4sI',data,p);r[t]=data[p+8:p+8+n];p+=8+n+n%2
    return r
class SF2:
    def __init__(self,path):
        d=open(path,'rb').read();p=12;S={}
        while p<len(d):
            t,n=struct.unpack_from('<4sI',d,p);v=d[p+8:p+8+n];p+=8+n+n%2
            S[v[:4]]=chunks(v[4:])
        self.smpl=np.frombuffer(S[b'sdta'][b'smpl'],dtype='<i2').astype(np.float32)/32768
        pd=S[b'pdta']
        self.phdr=[struct.unpack_from('<20sHHHIII',pd[b'phdr'],i) for i in range(0,len(pd[b'phdr']),38)]
        self.pbag=[struct.unpack_from('<HH',pd[b'pbag'],i) for i in range(0,len(pd[b'pbag']),4)]
        self.pgen=[struct.unpack_from('<HH',pd[b'pgen'],i) for i in range(0,len(pd[b'pgen']),4)]
        self.inst=[struct.unpack_from('<20sH',pd[b'inst'],i) for i in range(0,len(pd[b'inst']),22)]
        self.ibag=[struct.unpack_from('<HH',pd[b'ibag'],i) for i in range(0,len(pd[b'ibag']),4)]
        self.igen=[struct.unpack_from('<HH',pd[b'igen'],i) for i in range(0,len(pd[b'igen']),4)]
        self.shdr=[struct.unpack_from('<20sIIIIIBbHH',pd[b'shdr'],i) for i in range(0,len(pd[b'shdr']),46)]
    def zones(self,gens,bags,start,end):
        out=[]
        for b in range(start,end):
            g0=bags[b][0];g1=bags[b+1][0]
            z={}
            for g in gens[g0:g1]:
                op,amt=g; z[op]=amt
            out.append(z)
        return out
    def presets(self):
        return [(h[0].split(b'\0')[0].decode(),h[2],h[1]) for h in self.phdr[:-1]]
    def instrument_zones(self,inst_index):
        s=self.inst[inst_index][1];e=self.inst[inst_index+1][1]
        return self.zones(self.igen,self.ibag,s,e)
    def preset_zones(self,pi):
        s=self.phdr[pi][3];e=self.phdr[pi+1][3]
        return self.zones(self.pgen,self.pbag,s,e)
def s16(v): return v-65536 if v>32767 else v
