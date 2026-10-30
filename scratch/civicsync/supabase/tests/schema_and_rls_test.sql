-- ====================================================================
-- CivicSync Verification Tests: Scoring Formula & RLS Policies
-- Specification: RULES.pdf §1.8, SECURITY.pdf §10
-- ====================================================================

DO $$
DECLARE
    v_res RECORD;
BEGIN
    RAISE NOTICE '=== Running CivicSync Test Suite ===';

    -- Test 1: Worked Example 1 (Large pothole, main road, model 0.90 sure, 1 reporter)
    -- Expected: Score 90, Band Critical
    SELECT score, band INTO v_res
    FROM fn_calculate_priority_score('pothole'::hazard_class, 'large'::hazard_extent, 0.90, 0.90, 1);
    
    ASSERT v_res.score = 90, format('Test 1 Failed: Expected score 90, got %s', v_res.score);
    ASSERT v_res.band = 'critical', format('Test 1 Failed: Expected band critical, got %s', v_res.band);
    RAISE NOTICE 'Test 1 Passed: Case 1 correctly scored 90 (Critical)';

    -- Test 2: Worked Example 2 (Medium waterlogging, residential lane, 0.70 sure, 1 reporter)
    -- Expected: Score 53, Band Medium
    SELECT score, band INTO v_res
    FROM fn_calculate_priority_score('waterlogging'::hazard_class, 'medium'::hazard_extent, 0.70, 0.40, 1);
    
    ASSERT v_res.score = 53, format('Test 2 Failed: Expected score 53, got %s', v_res.score);
    ASSERT v_res.band = 'medium', format('Test 2 Failed: Expected band medium, got %s', v_res.band);
    RAISE NOTICE 'Test 2 Passed: Case 2 correctly scored 53 (Medium)';

    -- Test 3: Worked Example 3 (Same waterlogging, 4 distinct reporters)
    -- Expected: Score 62 (53 + 9 bonus), Band High
    SELECT score, band INTO v_res
    FROM fn_calculate_priority_score('waterlogging'::hazard_class, 'medium'::hazard_extent, 0.70, 0.40, 4);
    
    ASSERT v_res.score = 62, format('Test 3 Failed: Expected score 62, got %s', v_res.score);
    ASSERT v_res.band = 'high', format('Test 3 Failed: Expected band high, got %s', v_res.band);
    RAISE NOTICE 'Test 3 Passed: Case 3 with 4 reporters boosted to 62 (High)';

    -- Test 4: Worked Example 4 (Small broken road, near a school, 0.80 sure)
    -- Expected: Score 68, Band High
    SELECT score, band INTO v_res
    FROM fn_calculate_priority_score('broken_road'::hazard_class, 'small'::hazard_extent, 0.80, 1.00, 1);
    
    ASSERT v_res.score = 68, format('Test 4 Failed: Expected score 68, got %s', v_res.score);
    ASSERT v_res.band = 'high', format('Test 4 Failed: Expected band high, got %s', v_res.band);
    RAISE NOTICE 'Test 4 Passed: Case 4 correctly scored 68 (High)';

    -- Test 5: Location Context Proximity Check
    -- Point near Agra Hospital (78.0050, 27.1850) -> should yield 1.00
    DECLARE
        v_pt GEOGRAPHY;
        v_l REAL;
    BEGIN
        v_pt := ST_SetSRID(ST_MakePoint(78.0051, 27.1851), 4326)::geography;
        v_l := fn_get_location_context(v_pt);
        ASSERT v_l = 1.00, format('Test 5 Failed: Expected location context 1.00 near hospital, got %s', v_l);
        RAISE NOTICE 'Test 5 Passed: Proximity to hospital evaluates to L=1.00';
    END;

    RAISE NOTICE '=== All CivicSync SQL Tests Passed Successfully! ===';
END $$;
