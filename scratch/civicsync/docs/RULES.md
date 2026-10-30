# CivicSync Business Rules & Scoring Specification
Version: 1.0-rc1 · Date: 28 Oct 2026

This document is the single source of truth for all tunable business rules in CivicSync. In the database, these parameters live in the `rule_config` table.

---

## 1. Triage & Priority Scoring

### 1.1 The Priority Score Formula
The system assigns each hazard a deterministic score from 0 to 100:

$$\text{PriorityScore} = \text{round}\Big(100 \times \big(0.30 \cdot C + 0.25 \cdot E + 0.15 \cdot K + 0.30 \cdot L\big)\Big) + B$$

*(Capped at 100)*

| Symbol | Factor | Source |
| :--- | :--- | :--- |
| **$C$** | **Hazard Class Weight** | §1.2 below |
| **$E$** | **Extent (Size Factor)** | §1.3 below |
| **$K$** | **Model Confidence** | Model output $(0.0 - 1.0)$; if user adjusted class, $K = 1.0$ |
| **$L$** | **Location Context** | OpenStreetMap spatial lookup (§1.4) |
| **$B$** | **Corroboration Bonus** | $\min(10,\, 3 \times (\text{distinct\_reporters} - 1))$ |

### 1.2 Class Weight ($C$)
- `open_drain` (open drain or missing manhole cover): **1.00** *(serious fall / fatal injury potential)*
- `pothole`: **0.80** *(primary cause of two-wheeler road fatalities)*
- `broken_road`: **0.60**
- `waterlogging`: **0.50** *(temporary obstruction, potential to hide deep potholes)*
- `other`: **0.40**

### 1.3 Extent Factor ($E$)
- `Large`: **1.00**
- `Medium`: **0.60**
- `Small`: **0.30**
- `Not sure`: **0.50**

### 1.4 Location Context ($L$)
Evaluated via spatial proximity in PostGIS (highest value applies):
1. Within **200m** of a school or hospital: **1.00**
2. Within **30m** of a primary or secondary road (including highway approaches): **0.90**
3. Within **200m** of a market, bus stand, or railway station: **0.70**
4. Local or residential street: **0.40**
5. Unknown (preliminary calculation on mobile client): **0.50**

### 1.5 Priority Bands
- **Critical**: 75–100 *(Immediate dispatch)*
- **High**: 55–74
- **Medium**: 35–54
- **Low**: 0–34

---

## 2. Duplicate Clustering & Intake Rules

### 2.1 Compatibility Groups
Reports can only merge if their hazard classes belong to the same compatibility group:
- **Surface Damage**: `pothole`, `broken_road`
- **Drain**: `open_drain`
- **Water**: `waterlogging`
- **Other**: `other` (manual merge by officer only)

### 2.2 Distance Thresholds
- **$\le$ 25m** (with GPS accuracy $\le$ 30m): **Auto-Merge**. Report joins existing ticket, increments `report_count`, updates centroid, recomputes priority score.
- **$\le$ 25m** (with either point accuracy > 30m): Creates new ticket + adds row to `duplicate_candidates` for officer review.
- **25m – 50m**: Creates new ticket + adds candidate to `duplicate_candidates`.
- **> 50m**: Creates new independent ticket.

---

## 3. SLA & Escalation Deadlines
Working hours: Monday–Saturday, 10:00–17:00 IST (7 working hours/day).

| Priority Band | Verify SLA (`reported`) | Assign SLA (`verified`) | Resolve SLA (`assigned`) |
| :--- | :--- | :--- | :--- |
| **Critical** | 4 working hours | 1 working day (7h) | 3 working days (21h) |
| **High** | 1 working day (7h) | 2 working days (14h) | 7 working days (49h) |
| **Medium** | 2 working days (14h) | 5 working days (35h) | 14 working days (98h) |
| **Low** | 3 working days (21h) | 7 working days (49h) | 30 working days (210h) |

### Escalation Tiers
- **L1 (100% SLA elapsed)**: Alert Ward Officer or Crew Lead via dashboard badge.
- **L2 (150% SLA elapsed)**: Alert Zonal Engineer via overdue list.
- **L3 (200% SLA elapsed)**: Alert City Admin in weekly executive report.
- **Instant L2**: Triggered immediately if a fixed ticket is reopened twice.

---

## 4. Data Retention Schedule
In compliance with the Indian Digital Personal Data Protection (DPDP) Act:
- **Full Citizen Photos (Open Ticket)**: Retained while ticket is open.
- **Full Photos (Resolved Ticket)**: Automatically deleted after **90 days**.
- **Full Photos (Rejected Ticket)**: Automatically deleted after **30 days**.
- **Photos with `privacy_blur_failed`**: Retention window halved.
- **Thumbnails ($\le$ 30 KB)**: Retained for **12 months** post-resolution.
- **Reporter Account Link**: Stripped after **180 days** (retaining anonymous ticket).
- **Aggregate Analytics Records**: Retained for **3 years**.
