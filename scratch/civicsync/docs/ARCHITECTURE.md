# CivicSync System Architecture
Version: 1.0-rc1 · Date: 28 Oct 2026

## 1. High-Level Concept
The citizen's mobile device performs the tasks that require **zero latency and offline resilience**:
- Camera photo capture (<30 seconds)
- GPS acquisition with accuracy reading
- On-device AI hazard classification via TensorFlow Lite (MobileNetV2 INT8)
- On-device privacy protection (face and vehicle license plate blurring)
- Local SQLite queue (`drift`) with idempotent sync

The cloud infrastructure (Supabase + PostGIS) performs tasks requiring **global municipal context**:
- Spatial point-in-polygon ward assignment
- Duplicate hazard grouping and auto-merging (25m / 50m)
- OpenStreetMap feature proximity lookup (schools, hospitals, primary transit arteries)
- Deterministic Priority Scoring (0–100) and SLA tracking
- Push notifications via Firebase Cloud Messaging

The municipal dashboard (Flutter Web / Modern Web) enables **human decision-making and triage**:
- Ranked priority queue (Critical, High, Medium, Low)
- ST_SnapToGrid 250m density clustering
- Duplicate merge/split review
- Status transitions (`Reported` → `Verified` → `Assigned` → `Resolved` with mandatory after-photo verification)

---

## 2. Status Workflow State Machine

```mermaid
stateDiagram-v2
    [*] --> Reported : Citizen submits report
    Reported --> Verified : Officer verifies OR 3 distinct corroborating reporters
    Reported --> Rejected : Reason required (not_a_road_hazard, unclear, outside)
    Verified --> Assigned : Assigned to Crew Lead
    Verified --> Rejected : Officer rejects with reason
    Assigned --> Resolved : Mandatory "after" repair photo attached
    Assigned --> Verified : Unassigned back to queue
    Resolved --> Verified : Reopened ("Still there?" check x2 or Officer)
    Resolved --> [*] : Archived after retention period
    Rejected --> [*] : Deleted after 30 days
```

---

## 3. Database Schema Overview

```mermaid
erDiagram
    CITIES ||--o{ WARDS : contains
    WARDS ||--o{ TICKETS : locates
    PROFILES ||--o{ REPORTS : submits
    PROFILES ||--o{ TICKETS : assigned_to
    TICKETS ||--|{ REPORTS : clusters
    TICKETS ||--o{ TICKET_EVENTS : logs
    TICKETS ||--o{ DUPLICATE_CANDIDATES : pairs

    TICKETS {
        uuid id PK
        hazard_class class
        geography geom
        int ward_id FK
        ticket_status status
        smallint priority_score
        priority_band priority_band
        int report_count
        int reporter_count
        timestamptz stage_due_at
    }

    REPORTS {
        uuid id PK
        uuid client_report_id UK
        uuid ticket_id FK
        uuid reporter_id FK
        hazard_class class_final
        real model_confidence
        geography geom
        real gps_accuracy_m
        text photo_path
        text photo_sha256
    }
```
