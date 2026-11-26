# 🦷 Oralia — Dental Practice Management & Patient Companion Ecosystem

**Oralia** is a dual-platform software solution designed for a dental clinic in Bouira, Algeria. It combines an internal **Desktop Practice Management System (DPMS)** for clinic staff with the **Oralia Mobile Application** for patients, streamlining daily clinic operations while improving patient communication and experience.

---

## 🎯 Core Objectives

Oralia is built to solve the clinic's primary operational and business challenges:

1. **Grow New-Patient Intake (40% Target):** Balance daily bookings so at least 40% of appointments are reserved for new patients rather than filling the entire schedule with ongoing treatments.
2. **Reduce No-Shows (~25% Baseline):** Send automated reminders and attendance confirmations—particularly for patients with half-finished treatments.
3. **Eliminate Waiting Room Frustration:** Give patients live visibility into how many people are ahead of them and their estimated session time, allowing them to step out and be called back when their turn approaches.
4. **Save Clinical Time & Prevent Disputes:** Replace paper cards (*fiches*) with structured, newest-first clinical histories, clear historical dates, and instant medical risk alerts (*anamnèse*).

---

## 🧩 System Components

### 1. Oralia Mobile App (For Patients)
* **Live Waiting Room Queue:** Displays *only* the number of patients ahead of the user and their estimated session time (15–20 minutes per patient), without exposing total clinic headcount.
* **Step-Out & Callback Alerts:** Patients can step outside while waiting and receive an instant notification when the reception desk calls them back.
* **Role-Adaptive Appointments:** New patients can request initial consultations (with Fridays, Sundays, and annual holidays automatically blocked); existing patients view their dentist-assigned next visit and confirm attendance.
* **Prescriptions & Post-Op Care:** Digital access to prescribed medications (*ordonnances*) and personalized treatment instructions.
* **Clinic Information & Education:** Dental services catalog, preventive care tips, FAQs, clinic announcements (holidays/schedule changes), opening hours, location, and direct contact.

### 2. Oralia DPMS (Desktop App for Clinic Staff)
* **Live Queue & Emergency Control:** Check in arriving patients, prioritize new patients and complex morning procedures, insert emergencies at the top of the queue, and trigger mobile callbacks.
* **Manual Scheduler & Quota Tracking:** Record exact follow-up dates dictated by the dentist (1 day to 1 month out) with strict **no double-booking** rules and real-time tracking of the 40% new-patient daily target.
* **Patient Records & *Anamnèse*:** Maintain newest-first session histories with prominent dates and high-visibility medical risk alerts for *patients à risque* (heart conditions, diabetes, hypertension).
* **Instalment Payments & Financial Privacy:** Track agreed treatment prices, cash instalments (~50% upfront, 5–10% per visit), shorthand payment codes (e.g., `V1` = 1,000 DA), and remaining balances.

---

## 👥 Clinic Roles & Permissions

| Role | Primary Responsibilities |
| :--- | :--- |
| **Dentist (Admin)** | Full clinical oversight and **exclusive access** to daily, weekly, and monthly financial totals. |
| **Informaticienne (PC 1)** | Main clinical data writer: logs *anamnèse* alerts, dictated treatment plans, session notes, prescriptions, and follow-up dates. |
| **Receptionist (PC 2)** | Welcomes patients, manages the live waiting room queue, triggers mobile callbacks, and records individual cash payments (financial totals are hidden). |
| **Assistant** | Chairside support with read-only access to schedules and patient files. |
| **Patient** | Uses the Oralia Mobile App to track their live queue position, manage visits, and access care instructions. |

---

## 🤝 Project Team

* **Mohammed Amine BOUALLAGA** (Team Lead)
* **Mohamed Ayoub BENAMROUCHE**
* **Mohammed Ayoub HOUADJI**