# App Store submission

Everything App Store Connect asks for that is not in the build. The copy is a draft: change anything
that does not sound like you. Nothing here can be filled in by the repository; it all goes into App Store
Connect by hand (or ask for help with a screen).

## Build

Upload through TestFlight (see RELEASING.md), then pick that build on the version page under
"Build". The icon, Health purpose strings and export-compliance answer are already in the app.

## App information

| Field | Value |
| --- | --- |
| Name | Dosebook |
| Subtitle (30 max) | Protocols, vials and doses |
| Category | Health & Fitness (Medical would bring stricter review) |
| Support URL | https://dosebook.app |
| Privacy policy URL | https://dosebook.app/privacy.html |
| Price | Free |
| Copyright | 2026 Craig Mewett |

**Promotional text (170 max)**
A private place to keep track of what you are running, what is in each vial and what you have taken.
No account, no ads, no tracking. Syncs through your own iCloud.

**Keywords (100 max)**
dose,vial,injection,peptide,protocol,reconstitution,syringe,units,tracker,log,half-life,bloodwork,schedule

**Description**
Dosebook keeps a clear record of what you are taking. Set up a protocol, add the vials you have, and log
each dose in a tap, from the app, a notification or the widget.

- Plan: protocols with schedules, titration, rest weeks and site rotation.
- Stock: vials, water and diluent, what is left, and when it will run out.
- Calculator: reconstitution and syringe units, shown exactly.
- Log: every dose, with the vial it came from, the site and a note; search and calendar views.
- Levels: an estimate of what is circulating, from published half-lives.
- Check-ins, weight and bloodwork beside your doses, and a report you can hand to a clinician.
- Reminders that stay discreet: they do not name the compound unless you turn that on.
- iPhone, iPad and Mac, synced through your own iCloud. A backup file you can keep anywhere.

Private by design. There is no account, no server and no analytics. Your records stay on your devices and
in your own private iCloud. Apple Health is read-only (weight, sleep, resting heart rate) and is never
written to or shared.

Dosebook is a record-keeping tool. It is not medical advice, it cannot check what is in a vial, and its
levels are estimates, not blood tests. Talk to whoever looks after your health.

**What's New (1.0.2)**
First release.

## Privacy ("App Privacy" questions)

Answer **Data Not Collected**. The app has no analytics, advertising or server. iCloud sync uses the
user's own private CloudKit database and Apple Health is read on the device; neither is sent to the
developer. Keep the privacy policy page in step with that.

## Age rating

Answer the questionnaire honestly. Dosebook has medical and treatment information (dosing, half-lives,
bloodwork), no user-generated public content, no web access, no purchases. Expect a higher rating
(possibly 17+) because of the medical information. Check what Apple's questionnaire says before settling.

## Export compliance

Already answered in the build (`ITSAppUsesNonExemptEncryption = false`). Choose "No" if asked again.

## Screenshots

Local files, not committed (`screenshots/` is ignored):

- iPhone 6.9": `screenshots/appstore/iphone-6.9/` (1320x2868): Now, Plan, Log, Stock.
- iPad 13": `screenshots/appstore/ipad-13/` (2752x2064): Now, Plan, Log, Stock.

Upload the framed versions (`framed-iphone-6.9/`, `framed-ipad-13/`: gradient, headline and subtitle round the
screenshot); the plain ones are the source. Both are made with `tools/shot.sh` on demo data, and
`python3 -I tools/store-frames.py <raw-dir> <out-dir> iphone|ipad` adds the frames. Change the headlines in
that script. The Simulator cannot write into the project folder, so shoot into a scratch folder and copy. A Mac listing needs its own build and is not part of this submission.

## Notes for the reviewer

> Dosebook needs no sign-in. On first launch it is empty: tap + on Plan to add a protocol from the built-in
> library, add a vial on Stock, then log a dose from Now. Health access is optional and read-only (weight,
> sleep, resting heart rate); the app never writes to Health. iCloud sync is optional and uses the user's own
> private CloudKit database. Dosebook does not sell, supply or recommend any compound; it records what the
> user enters. Every compound figure shows its basis, and the app states throughout that it is not medical
> advice.

## Where review may push back

- **Medical content (guideline 1.4.1).** Dosing and level figures must be accurate and say where they come
  from. The library shows its basis; keep that visible, and keep the not-medical-advice wording.
- **The compounds themselves.** Many in the library are not approved medicines. Apple can object to apps
  that help people use substances. Keep the listing and screenshots neutral: no sourcing, selling or
  claims, and say plainly that the app only records what the user enters.
- **Health data (5.1.3).** Needs the privacy policy to say Health data is read-only and not shared; it does.
- If rejected, the message says which guideline. Reply in Resolution Center before changing the app.
