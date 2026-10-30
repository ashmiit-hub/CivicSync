# CivicSync Security, Privacy, and DPDP Compliance
Version: 1.0-rc1 · Date: 28 Oct 2026

## 1. Threat Model (STRIDE)

| Threat | Risk | Mitigation |
| :--- | :--- | :--- |
| **Spam / Fake Reports** | High | Rate limit (10 reports/account/day); SHA-256 duplicate image detection; officer verification. |
| **Location Spoofing** | Medium | Check `isMocked` flag from Android Location Services; flag as `mock_location`; exclude from auto-verification. |
| **Photo Reuse / Stock Photos** | Medium | SHA-256 hash match against 7-day submission window; EXIF capture timestamp validation. |
| **Sybil Corroboration Attack** | Medium | Corroboration bonus requires $\ge$ 3 distinct accounts; multiple reports from same account within 24 hours at the same spot count once. |
| **Staff Account Takeover** | High | Mandatory TOTP 2FA for municipal staff; 30-minute idle session timeout; immediate account disablement RPC. |
| **Over-Broad Staff Access** | High | PostgreSQL Row-Level Security (RLS) policies scoped to `profiles.ward_ids`. Ward Officers cannot query tickets outside their wards. |
| **Public Photo Leaks** | High | Zero public S3/Supabase storage buckets. Photos are accessible strictly via 15-minute cryptographically signed URLs. |
| **Exposure of Service Keys** | Critical | Anon key only in client apps; service-role key restricted strictly to CI migrations and serverless cron jobs. |

---

## 2. Row-Level Security (RLS) Permission Matrix

| Role | Submit Report | View Own Reports | View Nearby Open | View Ward Tickets | Verify / Assign | Resolve Ticket | City-Wide Analytics |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Citizen** | ✅ | ✅ | ✅ (500m cap, no photos) | ❌ | ❌ | ❌ | ❌ |
| **Ward Officer** | ❌ | ❌ | ✅ | ✅ (Assigned wards) | ✅ | ✅ | ❌ |
| **Crew Lead** | ❌ | ❌ | ✅ | ✅ (Assigned tickets) | ❌ | ✅ (After-photo req) | ❌ |
| **Zonal Engineer** | ❌ | ❌ | ✅ | ✅ (All zonal wards) | ✅ | ✅ | ✅ (Zone level) |
| **City Admin** | ❌ | ❌ | ✅ | ✅ (All city wards) | ✅ | ✅ | ✅ (Full export) |
| **Platform Admin** | ❌ | ❌ | ❌ | Metadata only | ❌ | ❌ | ✅ (Aggregates) |

---

## 3. Indian Digital Personal Data Protection (DPDP) Act Compliance
- **Data Fiduciary**: Municipal Corporation & CivicSync Platform.
- **Lawful Purpose**: Road safety hazard reporting and municipal infrastructure repair triage.
- **Data Minimization**:
  - No names, phone numbers, or email addresses required for citizens to submit hazards.
  - On-device face and vehicle license plate blurring before upload.
  - Automatic EXIF metadata stripping upon WebP re-encoding.
- **Consent Gate**: Plain-language English and Hindi consent screen on first app launch with explicit age confirmation (18+).
- **Citizen Right to Erasure ("Delete My Data")**: Completed within 30 days. Removes account linkage; deletes unmerged open photos; retains anonymized hazard geometry for public safety records.
