"""Image-only staff rectification using detected staff-line geometry.

SPDX-License-Identifier: AGPL-3.0-or-later
Resample each image column around the detected middle staff line. Unlike a
triangulated warp, the mapping has no uncovered triangles or black fill. This
changes pixels only; no reference, pitch, duration or note prediction is read.
"""
from statistics import median
from math import isfinite


def extrapolate(x, xs, ys):
    import numpy as np
    out = np.interp(x,xs,ys)
    if len(xs)>1:
        left=(ys[1]-ys[0])/(xs[1]-xs[0]);right=(ys[-1]-ys[-2])/(xs[-1]-xs[-2])
        out=np.where(x<xs[0],ys[0]+(x-xs[0])*left,out)
        out=np.where(x>xs[-1],ys[-1]+(x-xs[-1])*right,out)
    return out


def crop_staff(pixels, staff, margin_units=2, minimum_span=None):
    import cv2
    import numpy as np
    from homr.staff_parsing import add_image_into_tr_omr_canvas
    xs=np.array([p.x for p in staff.grid],dtype=float)
    centers=np.array([p.y[2] for p in staff.grid],dtype=float)
    units=np.array([p.average_unit_size for p in staff.grid],dtype=float)
    unique,indices=np.unique(xs,return_index=True);xs=unique;centers=centers[indices];units=units[indices]
    if len(xs)<2 or not np.isfinite([*xs,*centers,*units]).all() or np.any(units<=0):
        raise ValueError('Insufficient staff geometry for column resampling')
    unit=float(np.median(units))
    right_end=max(xs[-1],xs[0]+minimum_span) if minimum_span is not None else xs[-1]
    left=int(np.floor(xs[0]-margin_units*unit));right=int(np.ceil(right_end+margin_units*unit))
    width=right-left+1;height=int(np.ceil(12*unit))+1
    if width<1 or width>pixels.shape[1]*2 or height>pixels.shape[0]:
        raise ValueError('Invalid staff crop bounds')
    x=np.arange(left,right+1,dtype=float)
    center=extrapolate(x,xs,centers)
    # Preserve relative staff spacing where photographed perspective changes it.
    spacing=np.interp(x,xs,units)
    offset=(np.arange(height,dtype=float)-(height-1)/2)/unit
    map_x=np.broadcast_to(x,(height,width)).astype(np.float32)
    map_y=(center[None,:]+offset[:,None]*spacing[None,:]).astype(np.float32)
    remapped=cv2.remap(pixels,map_x,map_y,interpolation=cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT,borderValue=(255,255,255))
    return add_image_into_tr_omr_canvas(remapped)


def common_staff_span(staffs):
    """Use page geometry only, and require majority agreement before extending."""
    spans = [float(s.max_x-s.min_x) for s in staffs]
    if len(spans)<3 or any(not isfinite(w) or w<=0 for w in spans):
        return None
    typical = median(spans)
    if sum(abs(w-typical)<=typical*0.05 for w in spans)<len(spans)*0.6:
        return None
    if not any(w<typical*0.9 for w in spans):
        return None
    return typical
