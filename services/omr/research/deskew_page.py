"""Research image-only deskew; no notation references or pixel masking."""
import hashlib
import math
from pathlib import Path
import cv2
import numpy as np


def prepare(source: Path, target: Path, *, deskew=True, scale=1):
    pixels=cv2.imread(str(source),cv2.IMREAD_COLOR)
    if pixels is None:raise ValueError('Unreadable image')
    height,width=pixels.shape[:2]
    gray=cv2.cvtColor(pixels,cv2.COLOR_BGR2GRAY)
    edges=cv2.Canny(gray,60,180)
    lines=cv2.HoughLinesP(edges,1,np.pi/1800,threshold=80,minLineLength=width*0.2,maxLineGap=width*0.03)
    candidates=[]
    for x1,y1,x2,y2 in (lines[:,0] if lines is not None else []):
        if x2<x1:x1,y1,x2,y2=x2,y2,x1,y1
        angle=math.degrees(math.atan2(int(y2)-int(y1),int(x2)-int(x1)))
        if abs(angle)<=12:candidates.append((angle,math.hypot(int(x2)-int(x1),int(y2)-int(y1))))
    angle=0.
    if len(candidates)>=10:
        candidates.sort();total=sum(c[1] for c in candidates);running=0
        for candidate,length in candidates:
            running+=length
            if running>=total/2:angle=candidate;break
        agreement=sum(length for candidate,length in candidates if abs(candidate-angle)<0.3)/total
        if agreement<0.65:angle=0.
    else:agreement=0.
    applied=angle if deskew and abs(angle)>=0.1 else 0.
    if applied:
        matrix=cv2.getRotationMatrix2D((width/2,height/2),applied,1)
        new_width=math.ceil(height*abs(matrix[0,1])+width*abs(matrix[0,0]))
        new_height=math.ceil(height*abs(matrix[0,0])+width*abs(matrix[0,1]))
        matrix[0,2]+=new_width/2-width/2;matrix[1,2]+=new_height/2-height/2
        pixels=cv2.warpAffine(pixels,matrix,(new_width,new_height),flags=cv2.INTER_CUBIC,borderMode=cv2.BORDER_CONSTANT,borderValue=(255,255,255))
    effective_scale=min(scale, math.sqrt(18_000_000/(pixels.shape[0]*pixels.shape[1])))
    if effective_scale!=1:
        size=(math.floor(pixels.shape[1]*effective_scale),math.floor(pixels.shape[0]*effective_scale))
        pixels=cv2.resize(pixels,size,interpolation=cv2.INTER_CUBIC)
    if not cv2.imwrite(str(target),pixels):raise OSError('Could not save prepared image')
    return {'angleDegrees':angle,'appliedDegrees':applied,'longSegments':len(candidates),'angleAgreement':agreement,'scale':scale,'effectiveScale':effective_scale,'inputSize':[width,height], 'outputSize':[pixels.shape[1],pixels.shape[0]],'outputSHA256':hashlib.sha256(target.read_bytes()).hexdigest()}
