"""Image-only recovery for unreadable tilted pages.

SPDX-License-Identifier: AGPL-3.0-or-later
No score reference, note prediction or pitch assumption enters this module.
"""
import math
from pathlib import Path


def prepare_deskewed_page(source: Path, target: Path) -> dict | None:
    import cv2
    import numpy as np

    pixels = cv2.imread(str(source), cv2.IMREAD_COLOR)
    if pixels is None:
        raise ValueError('Unreadable image')
    height, width = pixels.shape[:2]
    gray = cv2.cvtColor(pixels, cv2.COLOR_BGR2GRAY)
    lines = cv2.HoughLinesP(cv2.Canny(gray, 60, 180), 1, np.pi / 1800,
                           threshold=80, minLineLength=width * 0.2, maxLineGap=width * 0.03)
    candidates = []
    for x1, y1, x2, y2 in (lines[:, 0] if lines is not None else []):
        if x2 < x1:
            x1, y1, x2, y2 = x2, y2, x1, y1
        dx, dy = int(x2) - int(x1), int(y2) - int(y1)
        angle = math.degrees(math.atan2(dy, dx))
        if abs(angle) <= 12:
            candidates.append((angle, math.hypot(dx, dy)))
    if len(candidates) < 10:
        return None
    candidates.sort()
    total = sum(length for _, length in candidates)
    running = 0
    for angle, length in candidates:
        running += length
        if running >= total / 2:
            break
    agreement = sum(length for candidate, length in candidates if abs(candidate - angle) < 0.3) / total
    if agreement < 0.65 or abs(angle) < 0.5:
        return None

    matrix = cv2.getRotationMatrix2D((width / 2, height / 2), angle, 1)
    new_width = math.ceil(height * abs(matrix[0, 1]) + width * abs(matrix[0, 0]))
    new_height = math.ceil(height * abs(matrix[0, 0]) + width * abs(matrix[0, 1]))
    matrix[0, 2] += new_width / 2 - width / 2
    matrix[1, 2] += new_height / 2 - height / 2
    corrected = cv2.warpAffine(pixels, matrix, (new_width, new_height), flags=cv2.INTER_CUBIC,
                               borderMode=cv2.BORDER_CONSTANT, borderValue=(255, 255, 255))
    scale = min(1, math.sqrt(18_000_000 / (new_width * new_height)))
    if scale < 1:
        corrected = cv2.resize(corrected, (math.floor(new_width * scale), math.floor(new_height * scale)),
                               interpolation=cv2.INTER_CUBIC)
    if not cv2.imwrite(str(target), corrected):
        raise OSError('Could not save the straightened image')
    return {'rotationDegrees': angle, 'longSegments': len(candidates), 'agreement': agreement}
