"""Run in the isolated HOMR environment; never part of the service worker."""
import itertools
import unittest
import numpy as np
from evaluate_homr_beam import joint_top


class JointSearchTests(unittest.TestCase):
    def testJointTopMatchesExhaustiveEnumeration(self):
        rng = np.random.default_rng(7)
        for sizes in [(3,4,2,3,2,2),(2,1,3),(1,)]:
            logits = [rng.normal(size=n) for n in sizes]
            probabilities = [x-x.max()-np.log(np.exp(x-x.max()).sum()) for x in logits]
            expected = sorted([(ids,sum(float(p[i]) for p,i in zip(probabilities,ids)))
                               for ids in itertools.product(*(range(n) for n in sizes))],key=lambda x:-x[1])
            for width in (1,4,8):
                got = joint_top(logits,width)
                self.assertEqual([ids for ids,_ in got],[ids for ids,_ in expected[:width]])
                np.testing.assert_allclose([score for _,score in got],[score for _,score in expected[:width]])

    def testTiesAreDeterministicAndGreedyMatchesArgmax(self):
        logits = [np.array([1.,1.,0.]),np.array([0.,0.])]
        one = joint_top(logits,1)
        self.assertEqual(one[0][0],tuple(int(x.argmax()) for x in logits))
        self.assertEqual(joint_top(logits,6),joint_top(logits,6))
        self.assertEqual(len({ids for ids,_ in joint_top(logits,10)}),6)

    def testRejectsNonfiniteLogits(self):
        for value in [float('nan'),float('inf'),-float('inf')]:
            with self.assertRaises(ValueError):joint_top([np.array([0.,value])],4)


if __name__=='__main__':unittest.main()
