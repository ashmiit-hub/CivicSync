-- ====================================================================
-- CivicSync Seed Data: Pilot Cities (Agra, Jodhpur), Wards, & Rules
-- Specification: RULES.pdf §9, PRD.pdf §1.1, TOOLING.pdf §5
-- ====================================================================

-- 1. Insert Tunable Rule Configuration (RULES.pdf §9)
INSERT INTO rule_config (key, value, version) VALUES
('score.w_class', '0.30'::jsonb, 1),
('score.w_extent', '0.25'::jsonb, 1),
('score.w_conf', '0.15'::jsonb, 1),
('score.w_location', '0.30'::jsonb, 1),
('score.class_weight.open_drain', '1.00'::jsonb, 1),
('score.class_weight.pothole', '0.80'::jsonb, 1),
('score.class_weight.broken_road', '0.60'::jsonb, 1),
('score.class_weight.waterlogging', '0.50'::jsonb, 1),
('score.class_weight.other', '0.40'::jsonb, 1),
('score.extent.large', '1.00'::jsonb, 1),
('score.extent.medium', '0.60'::jsonb, 1),
('score.extent.small', '0.30'::jsonb, 1),
('score.extent.not_sure', '0.50'::jsonb, 1),
('score.bonus_per_reporter', '3'::jsonb, 1),
('score.bonus_cap', '10'::jsonb, 1),
('band.critical_min', '75'::jsonb, 1),
('band.high_min', '55'::jsonb, 1),
('band.medium_min', '35'::jsonb, 1),
('gps.good_max_m', '30'::jsonb, 1),
('gps.weak_max_m', '100'::jsonb, 1),
('intake.daily_limit', '10'::jsonb, 1),
('intake.stale_hours', '72'::jsonb, 1),
('dup.auto_m', '25'::jsonb, 1),
('dup.candidate_m', '50'::jsonb, 1),
('dup.recent_resolved_days', '14'::jsonb, 1)
ON CONFLICT (key) DO NOTHING;

-- 2. Insert Pilot Cities: Agra and Jodhpur
INSERT INTO cities (id, name, state, is_pilot) VALUES
(1, 'Agra', 'Uttar Pradesh', true),
(2, 'Jodhpur', 'Rajasthan', true)
ON CONFLICT (id) DO NOTHING;

-- 3. Insert Sample Pilot Wards with PostGIS Bounding Polygons
-- Agra Ward 1: Tajganj Zone (Sample polygon around Tajganj, Agra)
INSERT INTO wards (id, city_id, code, name, geom) VALUES
(
    1,
    1,
    'AGR-W01',
    'Tajganj Central',
    ST_Multi(ST_GeomFromText(
        'POLYGON((78.0200 27.1600, 78.0600 27.1600, 78.0600 27.1900, 78.0200 27.1900, 78.0200 27.1600))',
        4326
    ))
),
-- Agra Ward 2: Sanjay Place Commercial Hub
(
    2,
    1,
    'AGR-W02',
    'Sanjay Place / Civil Lines',
    ST_Multi(ST_GeomFromText(
        'POLYGON((77.9800 27.1900, 78.0200 27.1900, 78.0200 27.2200, 77.9800 27.2200, 77.9800 27.1900))',
        4326
    ))
),
-- Jodhpur Ward 1: Ratanada Zone
(
    3,
    2,
    'JDH-W01',
    'Ratanada',
    ST_Multi(ST_GeomFromText(
        'POLYGON((73.0100 26.2600, 73.0500 26.2600, 73.0500 26.3000, 73.0100 26.3000, 73.0100 26.2600))',
        4326
    ))
),
-- Jodhpur Ward 2: Sardarpura Market Hub
(
    4,
    2,
    'JDH-W02',
    'Sardarpura',
    ST_Multi(ST_GeomFromText(
        'POLYGON((72.9800 26.2700, 73.0100 26.2700, 73.0100 26.3100, 72.9800 26.3100, 72.9800 26.2700))',
        4326
    ))
)
ON CONFLICT (id) DO NOTHING;

-- Reset sequence for wards
SELECT setval('wards_id_seq', (SELECT MAX(id) FROM wards));

-- 4. Insert Pilot Context Spatial Features (OpenStreetMap derived sample)
INSERT INTO context_features (kind, geom, source) VALUES
-- Agra District Hospital (Hospital -> L = 1.00 within 200m)
('hospital', ST_GeomFromText('POINT(78.0050 27.1850)', 4326), 'osm'),
-- Agra St. Peter''s College (School -> L = 1.00 within 200m)
('school', ST_GeomFromText('POINT(78.0080 27.1950)', 4326), 'osm'),
-- Mahatma Gandhi Road, Agra (Primary Road -> L = 0.90 within 30m)
('road_primary', ST_GeomFromText('LINESTRING(78.0000 27.1800, 78.0100 27.2000, 78.0200 27.2100)', 4326), 'osm'),
-- Agra Cantt Railway Station (Transit -> L = 0.70 within 200m)
('rail_station', ST_GeomFromText('POINT(78.0020 27.1620)', 4326), 'osm'),
-- Jodhpur AIIMS (Hospital -> L = 1.00 within 200m)
('hospital', ST_GeomFromText('POINT(73.0150 26.2750)', 4326), 'osm'),
-- Sardarpura C-Road (Primary Road -> L = 0.90 within 30m)
('road_primary', ST_GeomFromText('LINESTRING(72.9900 26.2800, 73.0050 26.2850)', 4326), 'osm');
