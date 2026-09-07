import tempfile
import unittest
from pathlib import Path
import cv2
import numpy as np
from page_image import prepare_deskewed_page


class PageImageTests(unittest.TestCase):
    def test_low_evidence_and_straight_pages_are_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'input.png';output=root/'output.png'
            pixels=np.full((1000,800,3),255,np.uint8)
            for lines in [False,True]:
                if lines:
                    for y in range(200,800,14):cv2.line(pixels,(100,y),(700,y),(0,0,0),2)
                cv2.imwrite(str(source),pixels);original=source.read_bytes()
                self.assertIsNone(prepare_deskewed_page(source,output))
                self.assertFalse(output.exists());self.assertEqual(source.read_bytes(),original)

    def test_known_tilt_is_corrected_without_clipping_or_mutating_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'input.png';output=root/'output.png'
            pixels=np.full((1000,800,3),255,np.uint8)
            for top in [200,400,600]:
                for line in range(5):cv2.line(pixels,(100,top+line*14),(700,top+line*14),(0,0,0),2)
            for angle in [-7,5]:
                tilted=cv2.warpAffine(pixels,cv2.getRotationMatrix2D((400,500),angle,1),(800,1000),borderValue=(255,255,255))
                cv2.imwrite(str(source),tilted);original=source.read_bytes()
                result=prepare_deskewed_page(source,output)
                self.assertAlmostEqual(result['rotationDegrees'],-angle,delta=0.15)
                corrected=cv2.imread(str(output))
                self.assertGreaterEqual(corrected.shape[0],1000);self.assertGreaterEqual(corrected.shape[1],800)
                self.assertEqual(source.read_bytes(),original)
                self.assertIsNone(prepare_deskewed_page(output,root/'twice.png'))
                self.assertFalse((root/'twice.png').exists())


if __name__=='__main__':unittest.main()
