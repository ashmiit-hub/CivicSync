-- ====================================================================
-- CivicSync Initial Database Schema & Core Functions
-- Specification: TRD.pdf, RULES.pdf, SECURITY.pdf, ARCHITECTURE.pdf
-- ====================================================================

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Enumerated Types
CREATE TYPE user_role AS ENUM (
    'citizen',
    'ward_officer',
    'crew_lead',
    'zonal_engineer',
    'city_admin',
    'platform_admin'
);

CREATE TYPE hazard_class AS ENUM (
    'pothole',
    'open_drain',
    'broken_road',
    'waterlogging',
    'other'
);

CREATE TYPE hazard_extent AS ENUM (
    'small',
    'medium',
    'large',
    'not_sure'
);

CREATE TYPE ticket_status AS ENUM (
    'reported',
    'verified',
    'assigned',
    'resolved',
    'rejected'
);

CREATE TYPE priority_band AS ENUM (
    'critical',
    'high',
    'medium',
    'low'
);

CREATE TYPE ticket_event_type AS ENUM (
    'created',
    'report_added',
    'status_changed',
    'merged',
    'split',
    'escalated',
    'reopened',
    'note'
);

CREATE TYPE duplicate_state AS ENUM (
    'open',
    'merged',
    'kept_apart'
);

CREATE TYPE reject_reason AS ENUM (
    'not_a_road_hazard',
    'unclear_photo',
    'outside_area',
    'duplicate_merged',
    'test_or_misuse'
);

CREATE TYPE feature_kind AS ENUM (
    'school',
    'hospital',
    'market',
    'bus_stand',
    'rail_station',
    'road_primary',
    'road_secondary',
    'road_local'
);

-- ====================================================================
-- 3. Core Tables
-- ====================================================================

-- Cities table
CREATE TABLE cities (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    state TEXT NOT NULL,
    is_pilot BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Wards table with PostGIS boundary polygons
CREATE TABLE wards (
    id SERIAL PRIMARY KEY,
    city_id INT NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    geom GEOMETRY(MultiPolygon, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_wards_geom ON wards USING GIST (geom);

-- Profiles table (extends Supabase auth.users)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'citizen',
    display_name TEXT,
    city_id INT REFERENCES cities(id),
    ward_ids INT[] NOT NULL DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Rule configurations (tunable parameters from RULES.pdf §9)
CREATE TABLE rule_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    version INT NOT NULL DEFAULT 1,
    updated_by UUID REFERENCES profiles(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Context spatial features for location scoring (RULES.pdf §1.4)
CREATE TABLE context_features (
    id SERIAL PRIMARY KEY,
    kind feature_kind NOT NULL,
    geom GEOMETRY(Geometry, 4326) NOT NULL,
    source TEXT NOT NULL DEFAULT 'osm',
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_context_features_geom ON context_features USING GIST (geom);

-- Master Tickets Table (One ticket = one real-world hazard)
CREATE TABLE tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class hazard_class NOT NULL,
    geom GEOGRAPHY(Point, 4326) NOT NULL,
    ward_id INT REFERENCES wards(id),
    status ticket_status NOT NULL DEFAULT 'reported',
    priority_score SMALLINT NOT NULL DEFAULT 0 CHECK (priority_score >= 0 AND priority_score <= 100),
    priority_band priority_band NOT NULL DEFAULT 'low',
    location_context REAL NOT NULL DEFAULT 0.5 CHECK (location_context >= 0.0 AND location_context <= 1.0),
    report_count INT NOT NULL DEFAULT 1,
    reporter_count INT NOT NULL DEFAULT 1,
    reopen_count INT NOT NULL DEFAULT 0,
    first_reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    verified_at TIMESTAMPTZ,
    assigned_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    assigned_to UUID REFERENCES profiles(id),
    stage_due_at TIMESTAMPTZ,
    escalation_level SMALLINT NOT NULL DEFAULT 0 CHECK (escalation_level BETWEEN 0 AND 3),
    resolution_photo_path TEXT,
    reject_reason reject_reason,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_tickets_geom ON tickets USING GIST (geom);
CREATE INDEX idx_tickets_status_score ON tickets (status, priority_score DESC);
CREATE INDEX idx_tickets_ward_status ON tickets (ward_id, status);

-- Reports Table (Citizen submissions that attach to a ticket)
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_report_id UUID UNIQUE NOT NULL,
    ticket_id UUID REFERENCES tickets(id) ON DELETE SET NULL,
    reporter_id UUID NOT NULL REFERENCES profiles(id),
    class_model TEXT,
    class_final hazard_class NOT NULL,
    model_confidence REAL CHECK (model_confidence IS NULL OR (model_confidence >= 0 AND model_confidence <= 1.0)),
    extent hazard_extent NOT NULL DEFAULT 'not_sure',
    severity_prelim SMALLINT NOT NULL CHECK (severity_prelim >= 0 AND severity_prelim <= 100),
    geom GEOGRAPHY(Point, 4326) NOT NULL,
    gps_accuracy_m REAL NOT NULL,
    captured_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ward_id INT REFERENCES wards(id),
    photo_path TEXT NOT NULL,
    thumb_path TEXT,
    photo_sha256 TEXT NOT NULL,
    quality_flags TEXT[] NOT NULL DEFAULT '{}',
    note VARCHAR(200),
    app_version TEXT,
    model_version TEXT
);
CREATE INDEX idx_reports_geom ON reports USING GIST (geom);
CREATE INDEX idx_reports_ticket_id ON reports (ticket_id);
CREATE INDEX idx_reports_reporter_id ON reports (reporter_id);

-- Ticket Audit & Timeline Events
CREATE TABLE ticket_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    event_type ticket_event_type NOT NULL,
    from_status ticket_status,
    to_status ticket_status,
    actor_id UUID REFERENCES profiles(id),
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_ticket_events_ticket ON ticket_events (ticket_id, created_at ASC);

-- Duplicate Review Candidates (25m - 50m distance)
CREATE TABLE duplicate_candidates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_a UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    ticket_b UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    distance_m REAL NOT NULL,
    state duplicate_state NOT NULL DEFAULT 'open',
    decided_by UUID REFERENCES profiles(id),
    decided_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT diff_tickets CHECK (ticket_a <> ticket_b)
);
CREATE INDEX idx_duplicate_candidates_state ON duplicate_candidates (state);

-- Push Notification Tokens
CREATE TABLE device_tokens (
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, fcm_token)
);

-- Staff Audit Log (SECURITY.pdf §4.3)
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES profiles(id),
    action TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id TEXT,
    details JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_log_created_at ON audit_log (created_at DESC);

-- ====================================================================
-- 4. Helper & Scoring Functions (RULES.pdf §1)
-- ====================================================================

-- Function: Compute location context factor L (0.40 to 1.00)
CREATE OR REPLACE FUNCTION fn_get_location_context(p_geom GEOGRAPHY)
RETURNS REAL AS $$
DECLARE
    v_pt GEOMETRY;
    v_loc REAL := 0.40; -- Default: local/residential street
BEGIN
    v_pt := p_geom::geometry;

    -- 1. Within 200m of a school or hospital -> 1.00
    IF EXISTS (
        SELECT 1 FROM context_features
        WHERE kind IN ('school', 'hospital')
        AND ST_DWithin(geom::geography, p_geom, 200)
        LIMIT 1
    ) THEN
        RETURN 1.00;
    END IF;

    -- 2. Within 30m of primary or secondary road -> 0.90
    IF EXISTS (
        SELECT 1 FROM context_features
        WHERE kind IN ('road_primary', 'road_secondary')
        AND ST_DWithin(geom::geography, p_geom, 30)
        LIMIT 1
    ) THEN
        RETURN 0.90;
    END IF;

    -- 3. Within 200m of market, bus stand, or railway station -> 0.70
    IF EXISTS (
        SELECT 1 FROM context_features
        WHERE kind IN ('market', 'bus_stand', 'rail_station')
        AND ST_DWithin(geom::geography, p_geom, 200)
        LIMIT 1
    ) THEN
        RETURN 0.70;
    END IF;

    RETURN v_loc;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Compute deterministic Priority Score and Band
CREATE OR REPLACE FUNCTION fn_calculate_priority_score(
    p_class hazard_class,
    p_extent hazard_extent,
    p_confidence REAL,
    p_location_context REAL,
    p_reporter_count INT
)
RETURNS TABLE(score SMALLINT, band priority_band) AS $$
DECLARE
    v_c REAL;
    v_e REAL;
    v_k REAL;
    v_l REAL;
    v_b REAL;
    v_raw_score REAL;
    v_final_score SMALLINT;
    v_band priority_band;
BEGIN
    -- Class weight C (RULES.pdf §1.2)
    CASE p_class
        WHEN 'open_drain' THEN v_c := 1.00;
        WHEN 'pothole' THEN v_c := 0.80;
        WHEN 'broken_road' THEN v_c := 0.60;
        WHEN 'waterlogging' THEN v_c := 0.50;
        ELSE v_c := 0.40; -- other
    END CASE;

    -- Extent E (RULES.pdf §1.3)
    CASE p_extent
        WHEN 'large' THEN v_e := 1.00;
        WHEN 'medium' THEN v_e := 0.60;
        WHEN 'small' THEN v_e := 0.30;
        ELSE v_e := 0.50; -- not_sure
    END CASE;

    -- Model confidence K
    v_k := COALESCE(p_confidence, 1.0);
    IF v_k < 0.0 THEN v_k := 0.0; END IF;
    IF v_k > 1.0 THEN v_k := 1.0; END IF;

    -- Location context L
    v_l := COALESCE(p_location_context, 0.50);

    -- Corroboration bonus B = min(10, 3 * (distinct_reporters - 1))
    v_b := LEAST(10, 3 * GREATEST(0, p_reporter_count - 1));

    -- PriorityScore = round(100 * (0.30*C + 0.25*E + 0.15*K + 0.30*L)) + B
    v_raw_score := ROUND(100.0 * (0.30 * v_c + 0.25 * v_e + 0.15 * v_k + 0.30 * v_l)) + v_b;
    v_final_score := LEAST(100, GREATEST(0, v_raw_score::SMALLINT));

    -- Priority Bands (RULES.pdf §1.7)
    IF v_final_score >= 75 THEN
        v_band := 'critical';
    ELSIF v_final_score >= 55 THEN
        v_band := 'high';
    ELSIF v_final_score >= 35 THEN
        v_band := 'medium';
    ELSE
        v_band := 'low';
    END IF;

    RETURN QUERY SELECT v_final_score, v_band;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function: Compute stage SLA deadline (RULES.pdf §4)
-- Working hours: Mon-Sat 10:00-17:00 IST (7 working hours/day)
CREATE OR REPLACE FUNCTION fn_calculate_stage_due_at(
    p_status ticket_status,
    p_band priority_band,
    p_start_time TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TIMESTAMPTZ AS $$
DECLARE
    v_hours_needed INT;
BEGIN
    IF p_status = 'reported' THEN
        -- Verification SLA
        CASE p_band
            WHEN 'critical' THEN v_hours_needed := 4;
            WHEN 'high' THEN v_hours_needed := 7;      -- 1 working day
            WHEN 'medium' THEN v_hours_needed := 14;   -- 2 working days
            WHEN 'low' THEN v_hours_needed := 21;      -- 3 working days
        END CASE;
    ELSIF p_status = 'verified' THEN
        -- Assignment SLA
        CASE p_band
            WHEN 'critical' THEN v_hours_needed := 7;    -- 1 working day
            WHEN 'high' THEN v_hours_needed := 14;      -- 2 working days
            WHEN 'medium' THEN v_hours_needed := 35;    -- 5 working days
            WHEN 'low' THEN v_hours_needed := 49;       -- 7 working days
        END CASE;
    ELSIF p_status = 'assigned' THEN
        -- Resolution SLA
        CASE p_band
            WHEN 'critical' THEN v_hours_needed := 21;   -- 3 working days
            WHEN 'high' THEN v_hours_needed := 49;      -- 7 working days
            WHEN 'medium' THEN v_hours_needed := 98;    -- 14 working days
            WHEN 'low' THEN v_hours_needed := 210;      -- 30 working days
        END CASE;
    ELSE
        RETURN NULL;
    END IF;

    -- Simplified working clock: add required calendar duration equivalent
    RETURN p_start_time + (v_hours_needed || ' hours')::INTERVAL;
END;
$$ LANGUAGE plpgsql STABLE;

-- ====================================================================
-- 5. RPC Methods (TRD.pdf §5)
-- ====================================================================

-- RPC: submit_report
CREATE OR REPLACE FUNCTION submit_report(
    p_client_report_id UUID,
    p_class_final hazard_class,
    p_class_model TEXT,
    p_model_confidence REAL,
    p_extent hazard_extent,
    p_severity_prelim SMALLINT,
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_gps_accuracy_m REAL,
    p_captured_at TIMESTAMPTZ,
    p_photo_path TEXT,
    p_thumb_path TEXT,
    p_photo_sha256 TEXT,
    p_quality_flags TEXT[] DEFAULT '{}',
    p_note VARCHAR(200) DEFAULT NULL,
    p_app_version TEXT DEFAULT NULL,
    p_model_version TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_reporter_id UUID;
    v_geom GEOGRAPHY;
    v_pt_geom GEOMETRY;
    v_ward_id INT;
    v_lock_key BIGINT;
    v_candidate_ticket_id UUID;
    v_candidate_dist REAL;
    v_target_ticket_id UUID;
    v_target_status ticket_status;
    v_loc_ctx REAL;
    v_score SMALLINT;
    v_band priority_band;
    v_report_id UUID;
    v_distinct_reporters INT;
    v_total_reports INT;
    v_recent_same_reporter BOOLEAN;
BEGIN
    v_reporter_id := auth.uid();
    IF v_reporter_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to submit report.';
    END IF;

    -- Construct point
    v_geom := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;
    v_pt_geom := v_geom::geometry;

    -- Verify ward coverage (point in polygon)
    SELECT id INTO v_ward_id
    FROM wards
    WHERE ST_Contains(geom, v_pt_geom)
    LIMIT 1;

    IF v_ward_id IS NULL THEN
        RAISE EXCEPTION 'Location is outside of supported municipal pilot wards.';
    END IF;

    -- Coarse Grid Advisory Lock (prevent race conditions on concurrent reports nearby)
    v_lock_key := (ROUND(p_latitude * 1000)::BIGINT << 32) | (ROUND(p_longitude * 1000)::BIGINT & 4294967295);
    PERFORM pg_advisory_xact_lock(v_lock_key);

    -- Check duplicate SHA256 within 7 days
    IF EXISTS (
        SELECT 1 FROM reports
        WHERE photo_sha256 = p_photo_sha256
        AND received_at > NOW() - INTERVAL '7 days'
    ) THEN
        RAISE EXCEPTION 'This photo has already been submitted.';
    END IF;

    -- Find nearest open compatible ticket within 50m
    -- Compatibility groups: {pothole, broken_road}, {open_drain}, {waterlogging}, {other}
    SELECT t.id, ST_Distance(t.geom, v_geom)
    INTO v_candidate_ticket_id, v_candidate_dist
    FROM tickets t
    WHERE t.status IN ('reported', 'verified', 'assigned')
    AND ST_DWithin(t.geom, v_geom, 50.0)
    AND (
        (p_class_final IN ('pothole', 'broken_road') AND t.class IN ('pothole', 'broken_road'))
        OR (p_class_final = 'open_drain' AND t.class = 'open_drain')
        OR (p_class_final = 'waterlogging' AND t.class = 'waterlogging')
        OR (p_class_final = 'other' AND t.class = 'other')
    )
    ORDER BY ST_Distance(t.geom, v_geom) ASC
    LIMIT 1;

    -- Duplicate Clustering decision (RULES.pdf §6.2)
    IF v_candidate_ticket_id IS NOT NULL AND v_candidate_dist <= 25.0 AND p_gps_accuracy_m <= 30.0 THEN
        -- Auto-merge directly into candidate ticket
        v_target_ticket_id := v_candidate_ticket_id;
    ELSE
        -- Calculate location context for new ticket
        v_loc_ctx := fn_get_location_context(v_geom);
        
        -- Calculate initial priority score
        SELECT s.score, s.band INTO v_score, v_band
        FROM fn_calculate_priority_score(p_class_final, p_extent, p_model_confidence, v_loc_ctx, 1) s;

        -- Create new ticket
        INSERT INTO tickets (
            class,
            geom,
            ward_id,
            status,
            priority_score,
            priority_band,
            location_context,
            report_count,
            reporter_count,
            first_reported_at,
            stage_due_at
        ) VALUES (
            p_class_final,
            v_geom,
            v_ward_id,
            'reported',
            v_score,
            v_band,
            v_loc_ctx,
            1,
            1,
            NOW(),
            fn_calculate_stage_due_at('reported', v_band, NOW())
        ) RETURNING id, status INTO v_target_ticket_id, v_target_status;

        -- Add ticket creation event
        INSERT INTO ticket_events (ticket_id, event_type, to_status, actor_id, note)
        VALUES (v_target_ticket_id, 'created', 'reported', v_reporter_id, 'Ticket created from citizen report');

        -- If distance was 25m-50m or accuracy > 30m, flag as duplicate candidate for review
        IF v_candidate_ticket_id IS NOT NULL AND v_candidate_dist <= 50.0 THEN
            INSERT INTO duplicate_candidates (ticket_a, ticket_b, distance_m, state)
            VALUES (v_target_ticket_id, v_candidate_ticket_id, v_candidate_dist, 'open');
        END IF;
    END IF;

    -- Insert Report row
    INSERT INTO reports (
        client_report_id,
        ticket_id,
        reporter_id,
        class_model,
        class_final,
        model_confidence,
        extent,
        severity_prelim,
        geom,
        gps_accuracy_m,
        captured_at,
        received_at,
        ward_id,
        photo_path,
        thumb_path,
        photo_sha256,
        quality_flags,
        note,
        app_version,
        model_version
    ) VALUES (
        p_client_report_id,
        v_target_ticket_id,
        v_reporter_id,
        p_class_model,
        p_class_final,
        p_model_confidence,
        p_extent,
        p_severity_prelim,
        v_geom,
        p_gps_accuracy_m,
        p_captured_at,
        NOW(),
        v_ward_id,
        p_photo_path,
        p_thumb_path,
        p_photo_sha256,
        p_quality_flags,
        p_note,
        p_app_version,
        p_model_version
    ) RETURNING id INTO v_report_id;

    -- If merged into existing ticket, update centroid, reporter count & recalculate priority
    IF v_target_ticket_id = v_candidate_ticket_id THEN
        SELECT COUNT(DISTINCT reporter_id), COUNT(*)
        INTO v_distinct_reporters, v_total_reports
        FROM reports
        WHERE ticket_id = v_target_ticket_id;

        -- Fetch existing location context
        SELECT location_context INTO v_loc_ctx FROM tickets WHERE id = v_target_ticket_id;

        -- Recompute score
        SELECT s.score, s.band INTO v_score, v_band
        FROM fn_calculate_priority_score(p_class_final, p_extent, p_model_confidence, v_loc_ctx, v_distinct_reporters) s;

        -- Update ticket stats
        UPDATE tickets
        SET report_count = v_total_reports,
            reporter_count = v_distinct_reporters,
            priority_score = v_score,
            priority_band = v_band,
            updated_at = NOW()
        WHERE id = v_target_ticket_id;

        -- Timeline event
        INSERT INTO ticket_events (ticket_id, event_type, actor_id, note)
        VALUES (v_target_ticket_id, 'report_added', v_reporter_id, 'Additional corroborating citizen report attached');
    END IF;

    -- Return response payload
    SELECT status INTO v_target_status FROM tickets WHERE id = v_target_ticket_id;
    RETURN jsonb_build_object(
        'success', true,
        'report_id', v_report_id,
        'ticket_id', v_target_ticket_id,
        'status', v_target_status,
        'priority_score', v_score,
        'priority_band', v_band
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: transition_ticket (Municipal Workflow)
CREATE OR REPLACE FUNCTION transition_ticket(
    p_ticket_id UUID,
    p_to_status ticket_status,
    p_note TEXT DEFAULT NULL,
    p_assigned_to UUID DEFAULT NULL,
    p_resolution_photo_path TEXT DEFAULT NULL,
    p_reject_reason reject_reason DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role user_role;
    v_actor_wards INT[];
    v_ticket_ward INT;
    v_current_status ticket_status;
    v_current_band priority_band;
    v_next_due_at TIMESTAMPTZ;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    -- Get actor role & wards
    SELECT role, ward_ids INTO v_actor_role, v_actor_wards
    FROM profiles
    WHERE id = v_actor_id AND is_active = true;

    IF v_actor_role IS NULL OR v_actor_role = 'citizen' THEN
        RAISE EXCEPTION 'Citizens cannot transition tickets.';
    END IF;

    -- Get ticket current status and ward
    SELECT status, ward_id, priority_band
    INTO v_current_status, v_ticket_ward, v_current_band
    FROM tickets
    WHERE id = p_ticket_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'Ticket % not found.', p_ticket_id;
    END IF;

    -- Check ward authority: Ward Officer must have ticket's ward in ward_ids
    IF v_actor_role = 'ward_officer' AND NOT (v_ticket_ward = ANY(v_actor_wards)) THEN
        RAISE EXCEPTION 'Ward Officers can only transition tickets within their assigned wards.';
    END IF;

    -- Validate transitions (ARCHITECTURE.pdf §4 & RULES.pdf §3)
    IF p_to_status = 'verified' THEN
        IF v_actor_role NOT IN ('ward_officer', 'zonal_engineer', 'city_admin', 'platform_admin') THEN
            RAISE EXCEPTION 'Role % cannot verify tickets.', v_actor_role;
        END IF;
    ELSIF p_to_status = 'assigned' THEN
        IF p_assigned_to IS NULL THEN
            RAISE EXCEPTION 'A Crew Lead must be assigned.';
        END IF;
    ELSIF p_to_status = 'resolved' THEN
        IF p_resolution_photo_path IS NULL THEN
            RAISE EXCEPTION 'An after-photo is mandatory before resolving a ticket.';
        END IF;
    ELSIF p_to_status = 'rejected' THEN
        IF p_reject_reason IS NULL THEN
            RAISE EXCEPTION 'A standardized reject reason is required.';
        END IF;
    END IF;

    -- Calculate new stage deadline
    v_next_due_at := fn_calculate_stage_due_at(p_to_status, v_current_band, NOW());

    -- Perform ticket update
    UPDATE tickets
    SET status = p_to_status,
        verified_at = CASE WHEN p_to_status = 'verified' AND verified_at IS NULL THEN NOW() ELSE verified_at END,
        assigned_at = CASE WHEN p_to_status = 'assigned' AND assigned_at IS NULL THEN NOW() ELSE assigned_at END,
        resolved_at = CASE WHEN p_to_status = 'resolved' THEN NOW() ELSE resolved_at END,
        assigned_to = COALESCE(p_assigned_to, assigned_to),
        resolution_photo_path = COALESCE(p_resolution_photo_path, resolution_photo_path),
        reject_reason = COALESCE(p_reject_reason, reject_reason),
        stage_due_at = v_next_due_at,
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Record audit timeline event
    INSERT INTO ticket_events (
        ticket_id,
        event_type,
        from_status,
        to_status,
        actor_id,
        note
    ) VALUES (
        p_ticket_id,
        'status_changed',
        v_current_status,
        p_to_status,
        v_actor_id,
        p_note
    );

    RETURN jsonb_build_object(
        'success', true,
        'ticket_id', p_ticket_id,
        'from_status', v_current_status,
        'to_status', p_to_status,
        'stage_due_at', v_next_due_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: get_nearby_open (Privacy-preserving citizen map/list query)
CREATE OR REPLACE FUNCTION get_nearby_open(
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_radius_m REAL DEFAULT 500.0
)
RETURNS TABLE (
    ticket_id UUID,
    hazard_class hazard_class,
    status ticket_status,
    report_count INT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    distance_m REAL
) AS $$
DECLARE
    v_point GEOGRAPHY;
    v_capped_radius REAL;
BEGIN
    -- Security cap: max 500m radius (SECURITY.pdf T9)
    v_capped_radius := LEAST(500.0, GREATEST(10.0, p_radius_m));
    v_point := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;

    RETURN QUERY
    SELECT 
        t.id AS ticket_id,
        t.class AS hazard_class,
        t.status,
        t.report_count,
        ST_Y(t.geom::geometry) AS latitude,
        ST_X(t.geom::geometry) AS longitude,
        ST_Distance(t.geom, v_point)::REAL AS distance_m
    FROM tickets t
    WHERE t.status IN ('reported', 'verified', 'assigned')
    AND ST_DWithin(t.geom, v_point, v_capped_radius)
    ORDER BY ST_Distance(t.geom, v_point) ASC
    LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- RPC: heat_cells (ST_SnapToGrid density binned clustering for dashboard)
CREATE OR REPLACE FUNCTION heat_cells(
    p_min_lat DOUBLE PRECISION,
    p_min_lng DOUBLE PRECISION,
    p_max_lat DOUBLE PRECISION,
    p_max_lng DOUBLE PRECISION,
    p_cell_size_deg DOUBLE PRECISION DEFAULT 0.0025 -- Approx 250m
)
RETURNS TABLE (
    cell_center_lat DOUBLE PRECISION,
    cell_center_lng DOUBLE PRECISION,
    ticket_count BIGINT,
    max_priority SMALLINT
) AS $$
DECLARE
    v_bbox GEOMETRY;
BEGIN
    v_bbox := ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326);

    RETURN QUERY
    SELECT
        ST_Y(ST_Centroid(ST_Collect(geom::geometry))) AS cell_center_lat,
        ST_X(ST_Centroid(ST_Collect(geom::geometry))) AS cell_center_lng,
        COUNT(*)::BIGINT AS ticket_count,
        MAX(priority_score)::SMALLINT AS max_priority
    FROM tickets
    WHERE status IN ('reported', 'verified', 'assigned')
    AND geom::geometry && v_bbox
    GROUP BY ST_SnapToGrid(geom::geometry, p_cell_size_deg);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ====================================================================
-- 6. Row-Level Security (RLS) Policies (SECURITY.pdf §4.2 - §4.3)
-- ====================================================================

ALTER TABLE cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE wards ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE rule_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE context_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE duplicate_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Helper RLS function: current user role
CREATE OR REPLACE FUNCTION auth_role()
RETURNS user_role AS $$
    SELECT role FROM profiles WHERE id = auth.uid() AND is_active = true;
$$ LANGUAGE sql STABLE;

-- Helper RLS function: current user assigned wards
CREATE OR REPLACE FUNCTION auth_wards()
RETURNS INT[] AS $$
    SELECT ward_ids FROM profiles WHERE id = auth.uid() AND is_active = true;
$$ LANGUAGE sql STABLE;

-- Cities & Wards: Public read for app & dashboard
CREATE POLICY cities_read_all ON cities FOR SELECT USING (true);
CREATE POLICY wards_read_all ON wards FOR SELECT USING (true);

-- Profiles Policies
CREATE POLICY profiles_read_self ON profiles FOR SELECT
    USING (id = auth.uid() OR auth_role() IN ('city_admin', 'platform_admin'));

CREATE POLICY profiles_update_self ON profiles FOR UPDATE
    USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- Tickets Policies
-- Staff can view tickets for their ward/city; citizens see via my_reports / RPC
CREATE POLICY tickets_staff_select ON tickets FOR SELECT USING (
    auth_role() IN ('city_admin', 'platform_admin', 'zonal_engineer')
    OR (auth_role() = 'ward_officer' AND ward_id = ANY(auth_wards()))
    OR (auth_role() = 'crew_lead' AND (assigned_to = auth.uid() OR ward_id = ANY(auth_wards())))
);

-- Reports Policies
-- Citizens see only their own reports. Staff see reports for tickets in their wards.
CREATE POLICY reports_citizen_select ON reports FOR SELECT USING (
    reporter_id = auth.uid()
    OR auth_role() IN ('city_admin', 'platform_admin', 'zonal_engineer')
    OR (auth_role() = 'ward_officer' AND ward_id = ANY(auth_wards()))
    OR (auth_role() = 'crew_lead' AND ward_id = ANY(auth_wards()))
);

CREATE POLICY reports_citizen_insert ON reports FOR INSERT WITH CHECK (
    reporter_id = auth.uid()
);

-- Ticket Events Policies
CREATE POLICY events_select ON ticket_events FOR SELECT USING (
    auth_role() IN ('ward_officer', 'crew_lead', 'zonal_engineer', 'city_admin', 'platform_admin')
    OR EXISTS (
        SELECT 1 FROM reports r
        WHERE r.ticket_id = ticket_events.ticket_id
        AND r.reporter_id = auth.uid()
    )
);

-- Duplicate Candidates Policies (Staff only)
CREATE POLICY dups_staff_select ON duplicate_candidates FOR SELECT USING (
    auth_role() IN ('ward_officer', 'zonal_engineer', 'city_admin', 'platform_admin')
);

-- Device Tokens Policies
CREATE POLICY tokens_manage_self ON device_tokens FOR ALL USING (
    user_id = auth.uid()
);

-- Audit Log Policies (Only City Admin & Platform Admin can view)
CREATE POLICY audit_view ON audit_log FOR SELECT USING (
    auth_role() IN ('city_admin', 'platform_admin')
);
