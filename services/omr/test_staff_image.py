"""Guard crop extension using geometry, without references or model output."""
import unittest
from types import SimpleNamespace
from staff_image import common_staff_span


class StaffSpanTests(unittest.TestCase):
    def span(self, widths):
        return common_staff_span([SimpleNamespace(min_x=50, max_x=50+w) for w in widths])

    def test_majority_width_recovers_a_truncated_staff(self):
        self.assertEqual(self.span([1340,1340,1150,1340,1350,960,1350]),1340)

    def test_complete_uniform_page_needs_no_extension(self):
        self.assertIsNone(self.span([1000,990,1010,995]))

    def test_small_or_inconsistent_groups_cannot_define_page_width(self):
        for widths in [[],[1000],[1000,700],[700,800,900,1000,1100]]:
            with self.subTest(widths=widths): self.assertIsNone(self.span(widths))

    def test_invalid_geometry_cannot_define_page_width(self):
        for width in [0,-1,float('nan'),float('inf')]:
            with self.subTest(width=width): self.assertIsNone(self.span([1000,1000,width]))


if __name__=='__main__': unittest.main()
