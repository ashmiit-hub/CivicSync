# CivicSync Product Requirements Document (PRD)
Version: 1.0-rc1 · Date: 28 Oct 2026

## 1. Problem Statement
When a road hazard (pothole, open drain, broken road surface, or waterlogging) occurs on a daily commute, citizens face significant friction:
- Unclear municipal channels (ward vs PWD vs NHAI vs development authority).
- Cumbersome forms requiring manual ward numbers and descriptions.
- Lack of accountability or feedback after reporting.

On the municipal side, complaints arrive disjointed, lacking exact geolocations, clear photos, or severity categorization. Duplicate complaints flood officers while genuine safety risks go untracked.

CivicSync solves this with a **bilingual mobile app** for 30-second hazard capture and a **unified municipal dashboard** for deterministic triage and SLA tracking.

---

## 2. Target Personas

| Persona | Role | Key Pain Point | CivicSync Solution |
| :--- | :--- | :--- | :--- |
| **Imran** | Daily two-wheeler commuter (Jodhpur) | High risk of fatal pothole crash; no time for forms. | 1-button camera capture, offline-first reporting under 30 seconds. |
| **Meena** | Pedestrian & bus commuter (Agra) | Hazards repeatedly reported without updates. | Transparent 4-stage tracking ("Received", "Checked", "Crew assigned", "Fixed"). |
| **Kavita** | Ward Officer (Ward AGR-W01) | Overwhelmed by repetitive complaints without photos. | Ranked priority queue (Critical/High/Med/Low), auto-merged duplicates, 1-click Fast Lane verify. |
| **Deepak** | Repair Crew Lead | Vague addresses; duplicate dispatches to the same spot. | Precise GPS pin, required before-photo, mandatory after-photo to close job. |
| **Mr. Sharma** | Zonal Engineer / City Admin | Lack of evidence for road repair budget allocation. | City-wide density heatmap (`ST_SnapToGrid`), overdue escalation tracking (L1–L3). |

---

## 3. Functional Requirements

### 3.1 Citizen Mobile App
- **FR-C1 (Must)**: Open straight to camera with zero onboarding friction.
- **FR-C2 (Must)**: Capture GPS location, accuracy, and timestamp automatically.
- **FR-C3 (Must)**: On-device offline hazard class inference (`pothole`, `open_drain`, `broken_road`, `waterlogging`, `other`).
- **FR-C4 (Must)**: Let user override class and select damage extent (`Small`, `Medium`, `Large`, `Not sure`).
- **FR-C5 (Must)**: Offline local SQLite queue with automatic background sync when connectivity resumes.
- **FR-C6 (Must)**: "My Reports" view with plain-language status updates.
- **FR-C7 (Should)**: Display "Already reported nearby" prompt before submission to prevent redundant reports.
- **FR-C8 (Should)**: Full bilingual UI (English and Hindi) from Day 1.
- **FR-C9 (Should)**: Push notifications via FCM when report status updates.
- **FR-C10 (Should)**: On-device automated blurring of faces and vehicle license plates.
- **FR-C11 (Could)**: Post-resolution "Still there?" verification check.

### 3.2 Municipal Dashboard (Web)
- **FR-M1 (Must)**: Role-based authentication (Ward Officer, Crew Lead, Zonal Engineer, City Admin).
- **FR-M2 (Must)**: Ranked priority queue with score breakdowns and filters.
- **FR-M3 (Must)**: Interactive map with ST_SnapToGrid density cells (replacing deprecated HeatmapLayer).
- **FR-M4 (Must)**: Ticket detail modal featuring timeline, before-photo, and contributor count.
- **FR-M5 (Must)**: Status actions (`Verify`, `Assign`, `Resolve` with after-photo, `Reject` with reason).
- **FR-M6 (Should)**: Duplicate review interface for 25m–50m candidates.
- **FR-M7 (Should)**: Overdue SLA escalation tracker (L1, L2, L3).
- **FR-M8 (Could)**: CSV analytics export for City Admin.

---

## 4. Key Performance Indicators (Metrics)

| ID | Metric | Target | Measurement Method |
| :--- | :--- | :--- | :--- |
| **PRD-M1** | First-time reporter completion time | $\le$ 30 seconds for $\ge$ 80% users | Instrumented mobile app timing events |
| **PRD-M2** | Capture-to-"Thanks" latency on 4G | < 3 seconds | Telemetry from capture tap to server ACK |
| **PRD-M3** | On-device inference latency (p95) | < 150 ms | Benchmark on reference device (RD-1) |
| **PRD-M4** | Model classification quality | Top-1 $\ge$ 80%, Macro-F1 $\ge$ 0.75 | Held-out field test set (Agra/Jodhpur) |
| **PRD-M5** | Duplicate grouping precision | $\ge$ 90% correct merges | Officer manual split rate audit |
| **PRD-M6** | Pilot reach | $\ge$ 40 distinct testers; $\ge$ 200 reports | Dashboard telemetry across Agra & Jodhpur |
| **PRD-M8** | Pilot monthly cloud infrastructure cost | < $50 / month | Supabase & GCP billing monitoring |
