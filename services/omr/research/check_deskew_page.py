"""Known image geometry checks, independent of musical reference scores."""
from pathlib import Path
import tempfile
import unittest
import cv2
import numpy as np
from deskew_page import prepare


class DeskewTests(unittest.TestCase):
    def testKnownSlopesAreFlattenedWithoutClippingCanvas(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            source=np.full((1000,800,3),255,np.uint8)
            for top in [200,400,600]:
                for line in range(5):cv2.line(source,(100,top+line*14),(700,top+line*14),(0,0,0),2)
            for angle in [-7,5]:
                tilted=cv2.warpAffine(source,cv2.getRotationMatrix2D((400,500),angle,1),(800,1000),borderValue=(255,255,255))
                cv2.imwrite(str(folder/'source.png'),tilted)
                result=prepare(folder/'source.png',folder/'flat.png')
                self.assertAlmostEqual(result['appliedDegrees'],-angle,delta=0.15)
                self.assertGreaterEqual(result['outputSize'][0],800)
                self.assertGreaterEqual(result['outputSize'][1],1000)
                second=prepare(folder/'flat.png',folder/'second.png')
                # Use the same 0.15-degree raster tolerance as the known-angle check.
                self.assertLess(abs(second['angleDegrees']),0.15)
                print({'sourceAngle':angle,'correction':result['appliedDegrees'],'residual':second['angleDegrees']})
                flattened=cv2.imread(str(folder/'flat.png'))
                self.assertGreater(np.count_nonzero(flattened[:,:,0]<100),np.count_nonzero(tilted[:,:,0]<100)*0.8)

    def testNoEvidenceMeansNoRotationOrPixelEditsAtOriginalScale(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            source=np.full((300,400,3),255,np.uint8)
            cv2.circle(source,(200,150),40,(0,0,0),2)
            cv2.imwrite(str(folder/'source.png'),source)
            result=prepare(folder/'source.png',folder/'flat.png')
            self.assertEqual(result['appliedDegrees'],0)
            self.assertTrue(np.array_equal(source,cv2.imread(str(folder/'flat.png'))))

    def testLargeUpscaleStaysBelowEnginePixelLimit(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            cv2.imwrite(str(folder/'source.png'),np.full((2300,2200,3),255,np.uint8))
            result=prepare(folder/'source.png',folder/'scaled.png',deskew=False,scale=2)
            self.assertLessEqual(np.prod(result['outputSize']),18_000_000)
            self.assertGreater(result['effectiveScale'],1)
            self.assertLess(result['effectiveScale'],2)


if __name__=='__main__':unittest.main()
