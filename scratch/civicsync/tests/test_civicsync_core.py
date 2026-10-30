"""
CivicSync Core Business Logic & State Machine Test Suite
Specifications: RULES.pdf, ARCHITECTURE.pdf, SECURITY.pdf, TRD.pdf
"""

import math
import unittest
from typing import Optional, List, Dict

# Domain Enums
CLASSES = {
    'open_drain': 1.00,
    'pothole': 0.80,
    'broken_road': 0.60,
    'waterlogging': 0.50,
    'other': 0.40
}

EXTENTS = {
    'large': 1.00,
    'medium': 0.60,
    'small': 0.30,
    'not_sure': 0.50
}

COMPATIBILITY_GROUPS = {
    'surface_damage': {'pothole', 'broken_road'},
    'drain': {'open_drain'},
    'water': {'waterlogging'},
    'other': {'other'}
}

REJECT_REASONS = {
    'not_a_road_hazard',
    'unclear_photo',
    'outside_area',
    'duplicate_merged',
    'test_or_misuse'
}

def calculate_priority_score(
    hazard_class: str,
    extent: str,
    confidence: float,
    location_context: float,
    reporter_count: int
) -> (int, str):
    """Deterministic Priority Scoring Formula (RULES.pdf §1.1) matching SQL ROUND()"""
    c = CLASSES[hazard_class]
    e = EXTENTS[extent]
    k = max(0.0, min(1.0, confidence))
    l = location_context
    b = min(10, 3 * max(0, reporter_count - 1))

    # Standard half-up rounding matching PostgreSQL NUMERIC ROUND()
    inner = 100.0 * (0.30 * c + 0.25 * e + 0.15 * k + 0.30 * l)
    raw = math.floor(round(inner, 4) + 0.5) + b
    score = min(100, max(0, raw))

    if score >= 75:
        band = "critical"
    elif score >= 55:
        band = "high"
    elif score >= 35:
        band = "medium"
    else:
        band = "low"

    return score, band

def generate_why_this_rank(hazard_class: str, extent: str, location_desc: str, reporters: int, band: str) -> str:
    """Explainable ranking generator (RULES.pdf §1.10)"""
    plural = f"{reporters} people" if reporters > 1 else "1 person"
    return f"{band.capitalize()} priority: {extent} {hazard_class.replace('_', ' ')} near {location_desc}, reported by {plural}."

def are_classes_compatible(class_a: str, class_b: str) -> bool:
    """Check duplicate compatibility group (RULES.pdf §6.1)"""
    for group in COMPATIBILITY_GROUPS.values():
        if class_a in group and class_b in group:
            return True
    return False

def decide_duplicate_action(distance_m: float, accuracy_m: float, is_compatible: bool) -> str:
    """Duplicate decision logic (RULES.pdf §6.2)"""
    if not is_compatible:
        return "new_ticket"
    if distance_m <= 25.0 and accuracy_m <= 30.0:
        return "auto_merge"
    elif distance_m <= 50.0:
        return "candidate_review"
    else:
        return "new_ticket"

class TicketStateMachine:
    """Municipal Workflow State Machine (ARCHITECTURE.pdf §4)"""
    def __init__(self, ticket_id: str, ward_id: int):
        self.ticket_id = ticket_id
        self.ward_id = ward_id
        self.status = "reported"
        self.assigned_to: Optional[str] = None
        self.resolution_photo: Optional[str] = None
        self.reject_reason: Optional[str] = None
        self.reopen_count = 0
        self.escalation_level = 0

    def verify(self, actor_role: str, actor_wards: List[int]):
        if actor_role not in ('ward_officer', 'zonal_engineer', 'city_admin'):
            raise PermissionError(f"Role {actor_role} cannot verify tickets.")
        if actor_role == 'ward_officer' and self.ward_id not in actor_wards:
            raise PermissionError("Ward Officer not authorized for this ward.")
        if self.status != "reported":
            raise ValueError(f"Cannot verify ticket from status {self.status}.")
        self.status = "verified"

    def assign(self, crew_lead_id: str):
        if self.status not in ("reported", "verified"):
            raise ValueError(f"Cannot assign from {self.status}.")
        self.assigned_to = crew_lead_id
        self.status = "assigned"

    def resolve(self, after_photo_path: str):
        if not after_photo_path:
            raise ValueError("Mandatory after-photo is required before resolving a ticket.")
        if self.status != "assigned":
            raise ValueError(f"Cannot resolve ticket from status {self.status}.")
        self.resolution_photo = after_photo_path
        self.status = "resolved"

    def reject(self, reason: str):
        if reason not in REJECT_REASONS:
            raise ValueError(f"Invalid rejection reason: {reason}")
        self.reject_reason = reason
        self.status = "rejected"

    def reopen(self):
        if self.status != "resolved":
            raise ValueError("Only resolved tickets can be reopened.")
        self.reopen_count += 1
        self.status = "verified"
        if self.reopen_count >= 2:
            self.escalation_level = 2 # Instant L2 escalation (RULES.pdf §5)


class TestCivicSyncCore(unittest.TestCase):

    def test_worked_example_1(self):
        """Case 1: Large pothole, main road, model 0.90 sure, 1 reporter -> Score 90, Critical"""
        score, band = calculate_priority_score('pothole', 'large', 0.90, 0.90, 1)
        self.assertEqual(score, 90)
        self.assertEqual(band, 'critical')

    def test_worked_example_2(self):
        """Case 2: Medium waterlogging, residential lane, 0.70 sure, 1 reporter -> Score 53, Medium"""
        score, band = calculate_priority_score('waterlogging', 'medium', 0.70, 0.40, 1)
        self.assertEqual(score, 53)
        self.assertEqual(band, 'medium')

    def test_worked_example_3(self):
        """Case 3: Same waterlogging, 4 distinct reporters -> Score 62, High"""
        score, band = calculate_priority_score('waterlogging', 'medium', 0.70, 0.40, 4)
        self.assertEqual(score, 62)
        self.assertEqual(band, 'high')

    def test_worked_example_4(self):
        """Case 4: Small broken road, near a school, 0.80 sure -> Score 68, High"""
        score, band = calculate_priority_score('broken_road', 'small', 0.80, 1.00, 1)
        self.assertEqual(score, 68)
        self.assertEqual(band, 'high')

    def test_duplicate_clustering_logic(self):
        """Verify 25m/50m distance boundaries and accuracy fallbacks"""
        # Compatible pair within 20m and good accuracy -> auto-merge
        self.assertTrue(are_classes_compatible('pothole', 'broken_road'))
        action = decide_duplicate_action(18.0, 15.0, True)
        self.assertEqual(action, "auto_merge")

        # Within 25m but poor GPS accuracy (>30m) -> candidate review
        action_poor_gps = decide_duplicate_action(18.0, 45.0, True)
        self.assertEqual(action_poor_gps, "candidate_review")

        # Between 25m and 50m -> candidate review
        action_mid_dist = decide_duplicate_action(35.0, 10.0, True)
        self.assertEqual(action_mid_dist, "candidate_review")

        # Greater than 50m -> new ticket
        action_far = decide_duplicate_action(55.0, 10.0, True)
        self.assertEqual(action_far, "new_ticket")

        # Incompatible classes (pothole vs open_drain) within 15m -> new ticket
        self.assertFalse(are_classes_compatible('pothole', 'open_drain'))
        action_incompat = decide_duplicate_action(15.0, 10.0, False)
        self.assertEqual(action_incompat, "new_ticket")

    def test_workflow_state_machine(self):
        """Verify valid and invalid state transitions and after-photo guard"""
        t = TicketStateMachine("TK-001", ward_id=1)

        # Unauthorized ward officer cannot verify other ward
        with self.assertRaises(PermissionError):
            t.verify('ward_officer', actor_wards=[2, 3])

        # Authorized ward officer verifies
        t.verify('ward_officer', actor_wards=[1])
        self.assertEqual(t.status, "verified")

        # Assign to crew lead
        t.assign("CREW-99")
        self.assertEqual(t.status, "assigned")
        self.assertEqual(t.assigned_to, "CREW-99")

        # Attempt resolve without after-photo must fail
        with self.assertRaises(ValueError):
            t.resolve("")

        # Resolve with after-photo
        t.resolve("storage/repairs/after_fixed.webp")
        self.assertEqual(t.status, "resolved")
        self.assertIsNotNone(t.resolution_photo)

        # First reopen
        t.reopen()
        self.assertEqual(t.status, "verified")
        self.assertEqual(t.reopen_count, 1)
        self.assertEqual(t.escalation_level, 0)

        # Re-resolve and 2nd reopen -> Instant L2 escalation
        t.assign("CREW-99")
        t.resolve("storage/repairs/second_fix.webp")
        t.reopen()
        self.assertEqual(t.reopen_count, 2)
        self.assertEqual(t.escalation_level, 2)

    def test_why_this_rank_generator(self):
        """Verify explainable human-readable ranking text"""
        text = generate_why_this_rank("pothole", "large", "District Hospital", 3, "critical")
        self.assertIn("Critical priority", text)
        self.assertIn("large pothole", text)
        self.assertIn("3 people", text)

if __name__ == '__main__':
    unittest.main()
