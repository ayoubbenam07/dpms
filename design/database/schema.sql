-- ==========================================
-- Dental Practice Management System (DPMS)
-- PostgreSQL Database Schema
-- ==========================================

-- ==========================================
-- 1. ENUMS (Clinical & Operational Rules)
-- ==========================================

-- C1: Staff Roles
CREATE TYPE staff_role AS ENUM (
  'DENTIST',          -- Admin: Exclusive access to total revenue/financial summaries
  'INFORMATICIENNE',  -- PC 1: Main writer (medical history, dictated notes, plans, dates)
  'RECEPTIONIST',     -- PC 2: Welcomes patients, manages live queue, enters cash payments
  'ASSISTANT'         -- Chairside: Read-only / minimal access
);

-- Section 5 Vocabulary: Standard French Dental Categories
CREATE TYPE work_category AS ENUM (
  'SOINS_CONSERVATEURS',       -- Fillings & cavities (3+ sessions/tooth)
  'ORTHOPEDIE_DENTO_FACIALE',  -- Braces / Orthodontics (10-20 sessions)
  'IMPLANTS',                  -- Implants (4-5 sessions over 3-4 months)
  'CHIRURGIE',                 -- Surgery / Extractions (1-2 sessions)
  'PARODONTOLOGIE',            -- Gum treatment (2-3 sessions)
  'PROTHESE_FIXE',             -- Fixed prosthesis (up to 5 sessions)
  'PROTHESE_AMOVIBLE',         -- Removable prosthesis (4-5 sessions)
  'BLANCHIMENT',               -- Whitening (2 sessions)
  'TRAITEMENT_MEDICAMENTEUX'   -- Prescription visit / Ordonnance (1 session)
);

-- C7 & C10: Appointment Lifecycle & 25% No-Show Tracking
CREATE TYPE appointment_status AS ENUM (
  'BOOKED',             -- Scheduled (by phone, on-site, or New Patient app request)
  'PATIENT_CONFIRMED',  -- Patient clicked "Confirm Attendance" on Oralia Mobile App
  'CHECKED_IN',         -- Arrived in waiting room (moved to waiting_queue_item)
  'COMPLETED',          -- Session finished
  'NO_SHOW',            -- Did not come (tracked against the ~25% no-show baseline)
  'CANCELLED'           -- Cancelled or postponed
);

-- Working Hours: 7h/day (4h Morning for complex/tiring work, 3h Afternoon)
CREATE TYPE day_shift AS ENUM (
  'MORNING_4H',         -- Priority for New Patients & complex/tiring procedures
  'AFTERNOON_3H'        -- Follow-up sessions
);

-- C4, C8, C9: Live Waiting Room States
CREATE TYPE queue_status AS ENUM (
  'WAITING_IN_CLINIC',  -- Patient is sitting in the waiting room
  'STEPPED_OUT',        -- Patient left temporarily; tracking live queue on Oralia App
  'CALLED_BACK',        -- Receptionist triggered "Call Back" notification to return
  'IN_CHAIR',           -- Currently with the dentist (15-20 min session)
  'DONE'                -- Left the chair, heading to reception desk for payment/next date
);

-- C5: Payment Methods
CREATE TYPE payment_method AS ENUM (
  'CASH',               -- Active default: Cash in instalments
  'BARIDI_MOB'          -- Planned future payment method
);

-- ==========================================
-- HELPER FUNCTION: Automatic updated_at
-- ==========================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 2. STAFF & ROLE-BASED ACCESS (C1)
-- ==========================================

CREATE TABLE staff_user (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name     TEXT NOT NULL,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role          staff_role NOT NULL,
  pc_station    TEXT, -- e.g., 'PC_1_INFORMATICIENNE' or 'PC_2_RECEPTIONIST'
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 3. PATIENTS & MEDICAL ALERTS (C3, C6, C7)
-- ==========================================

CREATE TABLE patient (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  surname               TEXT NOT NULL, -- Nom (Required per C3)
  first_name            TEXT NOT NULL, -- Prénom (Required per C3)
  telephone             TEXT NOT NULL UNIQUE, -- Téléphone (Strictly important for callbacks & auth)

  -- C7: Tracks New vs Existing status for the 40% New-Patient Target
  is_new_patient        BOOLEAN NOT NULL DEFAULT TRUE,  -- Flips to false after 1st treatment starts
  has_risk_alert        BOOLEAN NOT NULL DEFAULT FALSE, -- Quick flag for "Patients à risque"

  -- Mobile App Auth & Push Notifications (C8, C9)
  fcm_push_token        TEXT, -- For live queue callbacks & anti-no-show reminders
  app_account_activated BOOLEAN NOT NULL DEFAULT FALSE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_patient_surname_first_name ON patient (surname, first_name);

CREATE TRIGGER trg_patient_updated_at
  BEFORE UPDATE ON patient
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- C6: Medical History (L'Anamnèse) for "Patients à risque"
CREATE TABLE medical_alert (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id             UUID NOT NULL UNIQUE REFERENCES patient (id) ON DELETE CASCADE,

  has_heart_problem      BOOLEAN NOT NULL DEFAULT FALSE, -- "Hurt/Heart problems"
  has_diabetes           BOOLEAN NOT NULL DEFAULT FALSE, -- Diabète
  has_high_blood_pressure BOOLEAN NOT NULL DEFAULT FALSE, -- Hypertension
  other_conditions       TEXT, -- Free-text notes entered by informaticienne

  -- Dentist may refuse to work until the condition is controlled
  is_treatment_suspended BOOLEAN NOT NULL DEFAULT FALSE,
  suspension_reason      TEXT,

  entered_by_id          UUID NOT NULL REFERENCES staff_user (id),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_medical_alert_updated_at
  BEFORE UPDATE ON medical_alert
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- ==========================================
-- 4. TREATMENT PLANS & INSTALMENT BALANCES (C5)
-- ==========================================

CREATE TABLE treatment_plan (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id           UUID NOT NULL REFERENCES patient (id) ON DELETE CASCADE,

  work_category        work_category NOT NULL,
  -- Captures oral negotiation (e.g., declined fixed prosthesis -> agreed on removable or extraction)
  oral_proposal_notes  TEXT,
  progress_summary     TEXT, -- e.g., 'Séance 2 sur 5'

  -- C5: Financial Tracking (Price of work minus what was paid = Remaining Balance)
  total_price_da       INTEGER NOT NULL, -- Total agreed price in Algerian Dinars (DA)
  total_paid_da        INTEGER NOT NULL DEFAULT 0, -- Updated automatically on Payment insert
  remaining_balance_da INTEGER NOT NULL, -- Derived: total_price_da - total_paid_da

  is_completed         BOOLEAN NOT NULL DEFAULT FALSE,
  start_date           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_treatment_plan_patient_completed ON treatment_plan (patient_id, is_completed);

CREATE TRIGGER trg_treatment_plan_updated_at
  BEFORE UPDATE ON treatment_plan
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- ==========================================
-- 5. APPOINTMENTS & 40% QUOTA SCHEDULER (C3, C7, C10)
-- ==========================================

CREATE TABLE appointment (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id          UUID NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
  treatment_plan_id   UUID REFERENCES treatment_plan (id) ON DELETE SET NULL,

  -- C3: Decided by the dentist (1 day to 1 month out); no automation, no double-booking
  appointment_date    DATE NOT NULL, -- Date of the visit (Fridays & Sundays blocked in app logic)
  shift               day_shift NOT NULL DEFAULT 'MORNING_4H',
  exact_slot_time     TIMESTAMPTZ, -- Optional specific time slot (strictly unique to prevent double-booking)

  -- C7: Snapshot of whether this booking counts toward the 40% New-Patient daily target
  is_new_patient_slot BOOLEAN NOT NULL DEFAULT FALSE,
  progress_note       TEXT, -- "Progress" field required on appointment record (C3)
  status              appointment_status NOT NULL DEFAULT 'BOOKED',

  -- Mobile App Reminders (Combating the 25% No-Show rate)
  reminder_24h_sent   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Enforce "No Double-Booking" rule when an exact time slot is assigned
  CONSTRAINT uq_appointment_date_slot UNIQUE (appointment_date, exact_slot_time)
);

CREATE INDEX idx_appointment_date_new_status ON appointment (appointment_date, is_new_patient_slot, status);

-- ==========================================
-- 6. LIVE WAITING ROOM QUEUE & CALLBACKS (C4, C8, C9)
-- ==========================================

CREATE TABLE waiting_queue_item (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_date              DATE NOT NULL DEFAULT CURRENT_DATE,
  patient_id              UUID NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
  appointment_id          UUID UNIQUE REFERENCES appointment (id) ON DELETE SET NULL,

  -- Ordering Rules: 1) Emergencies first (C4), 2) New Patients first, 3) Complex work in Morning
  queue_position          INTEGER NOT NULL, -- 1, 2, 3... dynamically re-indexed by Receptionist/Dentist
  is_emergency            BOOLEAN NOT NULL DEFAULT FALSE, -- C4: Emergency inserted into the day
  is_new_patient_priority BOOLEAN NOT NULL DEFAULT FALSE, -- Dentist orders new patients first

  -- C8 & C9: Mobile Live Sync & Callback State
  status                  queue_status NOT NULL DEFAULT 'WAITING_IN_CLINIC',
  estimated_duration_mins INTEGER NOT NULL DEFAULT 18, -- Dentist takes 15 to 20 minutes per patient
  estimated_start_time    TIMESTAMPTZ, -- Dynamically shifts if an emergency is inserted

  checked_in_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  called_back_at          TIMESTAMPTZ, -- Timestamp when Receptionist clicked "Call Patient Back" (C9)
  entered_chair_at        TIMESTAMPTZ,
  completed_at            TIMESTAMPTZ
);

CREATE INDEX idx_waiting_queue_date_status_pos ON waiting_queue_item (queue_date, status, queue_position);

-- ==========================================
-- 7. CLINICAL SESSIONS & HISTORY (C2 — LATEST FIRST)
-- ==========================================

CREATE TABLE clinical_session (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id              UUID NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
  treatment_plan_id       UUID REFERENCES treatment_plan (id) ON DELETE SET NULL,

  -- C2: Dates are extremely important ("you did it 2 months ago" when it was 6 months or 2 years)
  session_date            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  work_performed          work_category NOT NULL,
  progress_notes          TEXT NOT NULL, -- List of notes showing progress entered by informaticienne
  post_op_instructions    TEXT, -- Personalized dental care instructions sent to Oralia Mobile App

  -- Next appointment date fixed orally by the dentist at the end of this session
  next_session_date_fixed DATE,

  recorded_by_id          UUID NOT NULL REFERENCES staff_user (id)
);

-- C2 CRITICAL INDEX: Strictly sorts history with the Latest Session First (DESC)
CREATE INDEX idx_clinical_session_patient_date_desc ON clinical_session (patient_id, session_date DESC);

-- ==========================================
-- 8. PAYMENTS & CODED NOTES LEDGER (C1, C5)
-- ==========================================

CREATE TABLE payment (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id          UUID NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
  treatment_plan_id   UUID NOT NULL REFERENCES treatment_plan (id),
  clinical_session_id UUID REFERENCES clinical_session (id) ON DELETE SET NULL,

  -- C5: About 50% at the start, then 5-10% at each visit
  amount_paid_da      INTEGER NOT NULL, -- Amount paid in Algerian Dinars (e.g., 1000 DA)
  coded_note          TEXT, -- Clinic shorthand code (e.g., 'V1' for 1,000 DA)
  payment_method      payment_method NOT NULL DEFAULT 'CASH',
  payment_date        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- C1: Entered by Receptionist, but total aggregations are restricted to DENTIST role only
  recorded_by_id      UUID NOT NULL REFERENCES staff_user (id)
);

CREATE INDEX idx_payment_date ON payment (payment_date);
CREATE INDEX idx_payment_patient_plan ON payment (patient_id, treatment_plan_id);

-- ==========================================
-- 9. MOBILE APP CONTENT: ORDONNANCES & ANNOUNCEMENTS
-- ==========================================

-- Course Feature: Access to prescribed medications (Traitement médicamenteux / Ordonnance)
CREATE TABLE prescription (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id          UUID NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
  clinical_session_id UUID REFERENCES clinical_session (id) ON DELETE SET NULL,

  issued_date         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- JSON array of medications: [{ "name": "Amoxicilline 1g", "dosage": "1 cp Matin et Soir", "durationDays": 7 }]
  medications_json    JSONB NOT NULL,
  care_instructions   TEXT -- Specific instructions shown on Oralia Mobile App
);

CREATE INDEX idx_prescription_patient_issued_desc ON prescription (patient_id, issued_date DESC);

-- Course Features: Clinic announcements (holidays/schedule changes) & Educational articles/FAQs
CREATE TABLE clinic_broadcast (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type                TEXT NOT NULL, -- 'HOLIDAY_ANNOUNCEMENT' | 'SCHEDULE_CHANGE' | 'HEALTH_TIP' | 'FAQ'
  title               TEXT NOT NULL,
  content             TEXT NOT NULL,
  holiday_start_date  DATE, -- Tracks the dentist's 4 weeks of annual holidays
  holiday_end_date    DATE,
  is_pinned_on_mobile BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
