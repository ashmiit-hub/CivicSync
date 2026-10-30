# CivicSync Technical Requirements Document (TRD)
Version: 1.0-rc1 · Date: 28 Oct 2026

## 1. System Targets
- **Reference Device (RD-1)**: Android 11+, 4GB RAM, octa-core CPU (Snapdragon 680 / Helio G-series class).
- **Network Constraints**: Designed for variable 2G/3G/4G connectivity across Tier-2 Indian cities.
- **Client App Size**: Target APK size $\le$ 40 MB inclusive of quantized TFLite assets.
- **Cloud Infrastructure**: Supabase (PostgreSQL 15+ with PostGIS 3.3+), Firebase Cloud Messaging, OpenStreetMap Overpass.

---

## 2. On-Device Machine Learning Pipeline
- **Backbone**: MobileNetV2 (ImageNet pre-trained), $224 \times 224 \times 3$ RGB input.
- **Quantization**: Post-training full INT8 quantization with representative dataset calibration.
- **Size Budget**: `.tflite` model size $\le$ 5.0 MB (achieved: ~2.8 MB).
- **Latency Budget**: $p95 < 150\text{ ms}$ on CPU with XNNPACK delegate.
- **Fallback Rule**: If macro-F1 on held-out field dataset drops below 0.75 by Day 40, fall back to 3 primary classes (`pothole`, `broken_road`, `other`).

---

## 3. Spatial & Database Schemas

### 3.1 PostGIS Distance Formulas
- Duplicate clustering utilizes `ST_DWithin(a.geom, b.geom, distance_meters)`.
- Ward boundary verification utilizes `ST_Contains(ward.geom, point_geom)`.
- Density clustering utilizes `ST_SnapToGrid(point_geom, cell_size_degrees)`.

### 3.2 Database Functions (RPCs)
1. `submit_report(...)`: Atomic transaction with coarse-grid advisory locking `pg_advisory_xact_lock`.
2. `transition_ticket(...)`: Enforces role-based authority, stage transitions, mandatory after-photo for `resolved`, and standardized rejection reasons.
3. `get_nearby_open(...)`: Capped at radius $\le$ 500m and limit $\le$ 50 entries, omitting photos and reporter identities for citizen privacy.
4. `heat_cells(...)`: Density binned grouping for the dashboard map view.

---

## 4. Offline Queue & Background Sync Protocol
- **Local Persistence**: Drift SQLite database on the mobile device.
- **Max Offline Retention**: Unsent reports retained for up to 7 days or 200 submissions.
- **Idempotency**: Every report is tagged with a client-generated UUID (`client_report_id`). Server deduplicates idempotent submissions.
- **Retry Backoff Schedule**: 30 seconds $\rightarrow$ 2 minutes $\rightarrow$ 10 minutes $\rightarrow$ 1 hour $\rightarrow$ daily.
- **Upload Order**: Photo and thumbnail upload to private bucket first; upon storage ACK, database transaction `submit_report` executes. If network fails during step 2, retries reuse the uploaded storage path.
