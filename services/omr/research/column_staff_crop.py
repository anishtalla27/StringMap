"""Compatibility entry point for isolated crop experiments; implementation is shared."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from staff_image import crop_staff, extrapolate
