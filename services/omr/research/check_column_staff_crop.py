import unittest
from types import SimpleNamespace
import cv2
import numpy as np
from column_staff_crop import crop_staff, extrapolate


def staff():
    return SimpleNamespace(grid=[SimpleNamespace(x=x,y=[100+0.1*x+(i-2)*10 for i in range(5)],average_unit_size=10) for x in [40,160,280,400]])


class ColumnCropTests(unittest.TestCase):
    def test_extrapolates_detected_slope_beyond_short_range(self):
        np.testing.assert_allclose(extrapolate(np.array([-1,0,1,2,3]),[0,2],[5,9]),[3,5,7,9,11])

    def test_white_gray_and_color_pages_stay_white_at_image_edges(self):
        for shape in [(240,480),(240,480,3)]:
            image=np.full(shape,255,np.uint8)
            crop=crop_staff(image,staff(),20)
            self.assertEqual(crop.shape[:2],(256,1280))
            self.assertTrue(np.all(crop==255))

    def test_sloped_staff_lines_become_horizontal(self):
        image=np.full((240,480),255,np.uint8)
        for i in range(5):cv2.line(image,(0,80+i*10),(479,128+i*10),0,1)
        crop=crop_staff(image,staff(),2)
        centers=[]
        for x in [100,300,500,700]:
            rows=np.flatnonzero(crop[:,x]<210)
            lines=np.split(rows,np.where(np.diff(rows)>1)[0]+1)
            self.assertEqual(len(lines),5)
            # Compare line centers, not the mean of all dark pixels: bilinear
            # antialiasing gives individual lines different pixel thicknesses.
            centers.append([float(np.mean(line)) for line in lines])
        self.assertLess(float(np.ptp(np.array(centers),axis=0).max()),2)

    def test_rejects_missing_or_invalid_geometry(self):
        invalid=SimpleNamespace(grid=[SimpleNamespace(x=1,y=[1]*5,average_unit_size=0)])
        with self.assertRaises(ValueError):crop_staff(np.full((240,480),255,np.uint8),invalid)


if __name__=='__main__':unittest.main()
