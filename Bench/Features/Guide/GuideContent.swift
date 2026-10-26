import Foundation

// The in-app guide. English only for now, so it lives here and not with the
// translated strings, which a test holds to all four languages. `**bold**` is
// markdown, drawn by RichText. Names in bold are the app's own button and menu
// names, so they match the screen.

enum GuideBlock: Hashable {
    case text(String)
    case points([String])
    case steps([String])
    case tip(String)
    case caution(String)
    /// A button to one of the main screens: "now", "plan", "log" or "stock".
    case open(String)
}

struct GuideTopic: Identifiable, Hashable {
    var id: String
    var title: String
    var symbol: String
    var summary: String
    var blocks: [GuideBlock]

    /// Everything a search can match.
    var searchText: String {
        ([title, summary] + blocks.flatMap { block -> [String] in
            switch block {
            case .text(let s), .tip(let s), .caution(let s), .open(let s): [s]
            case .points(let p), .steps(let p): p
            }
        }).joined(separator: " ").lowercased()
    }
}

let GUIDE_TOPICS: [GuideTopic] = [
    GuideTopic(id: "start", title: "Getting started", symbol: "flag.checkered",
               summary: "A protocol, a vial, and your first dose.", blocks: [
        .text("Bench keeps three things: what you **plan** (protocols), what you **have** (vials in Stock) and what you **did** (doses you log). Setting them up in that order works best."),
        .steps([
            "In **Plan**, tap **+ → New protocol**. Choose the compound; its typical dose and frequency fill in. Set the dose, the schedule and the times, then **Create protocol**.",
            "In **Stock**, tap **+ → Add a vial**, or **Scan a vial** to read the label with the camera. If you are already drawing from it, set it to **Already reconstituted** and enter the water you added and, if you have used some, how much is left.",
            "A vial that is still sealed is mixed later with **Reconstitute**. Bench can show how many units to draw only once a vial is mixed.",
            "**Now** shows what is due. Tap **Log now**.",
        ]),
        .tip("Coming from another app? **Settings → Your data → Import from another app**. Injectly can bring across protocols, blends, doses and weight in one go."),
        .open("plan"), .open("stock"), .open("now"),
    ]),
    GuideTopic(id: "logging", title: "Logging doses", symbol: "plus.circle",
               summary: "Logging, missed doses and skips.", blocks: [
        .text("A dose that is due or overdue appears at the top of **Now**."),
        .points([
            "**Log now** records it at the suggested injection site and takes it off your stock. Press and hold it to choose a site, or tap **Details** for the full form.",
            "A dose a few hours away sits under **Later today**. Its **+** asks first, since logging early is usually a mistake.",
            "In **Log**, **+** logs any dose, for any day.",
            "On a reminder, the **Log now** button records the dose without opening the app.",
            "**Missed a dose?** In **Log**, a red **Missed** row appears for each scheduled dose with nothing logged, up to 90 days back. **Log it** records it at its scheduled time, from the right vial. **Skipped** records that you chose not to take it. **Show missed doses**, in the **···** menu, turns the rows off.",
            "A **skipped** dose is a record, not a gap: nothing comes out of a vial and your streak is not broken.",
            "Editing or deleting a dose puts what it took back into its vial.",
        ]),
        .tip("If you take an evening dose after midnight, turn on **Late doses count for the night before** in Settings, so it does not show as missed."),
        .open("log"),
    ]),
    GuideTopic(id: "now", title: "Reading the Now screen", symbol: "waveform.path.ecg",
               summary: "The ring, the chart and each protocol's card.", blocks: [
        .points([
            "**Ring and week strip:** the ring counts today's doses; the strip shows the last week. Tap a day to see what was logged or missed. A red outline marks a day with a missed dose.",
            "**Circulating now:** each compound's estimated level over three weeks, drawn from your logged doses and its published half-life. The axis is **× one dose's peak**: 1.0 is how high one of your usual doses would peak on its own, and a line above the dashed 1.0 means doses are stacking up. Each line is scaled to its own compound, so lines cannot be compared with each other. Triangles are logged doses; a dashed line means the half-life is an estimate.",
            "**Active protocols:** each card shows a status (such as Peak or Cleared), the level as a percentage of a single-dose peak, your last dose and site, and your stock. A blend shows each of its parts on its own.",
            "**Worth sorting:** low stock and vials nearing their use-by date.",
            "Hide the cards you do not use in **Settings → Now screen**. Doses that are due, a pause and warnings always show.",
        ]),
        .caution("Levels are estimates from a simple model, not blood tests. See **Reading the numbers**."),
        .open("now"),
    ]),
    GuideTopic(id: "stock", title: "Vials, mixing and stock", symbol: "flask",
               summary: "Sealed and mixed vials, water, and what is left.", blocks: [
        .points([
            "A vial is **sealed**, **mixed** (reconstituted) or **on order**. Units to draw appear only once a vial is mixed, because they depend on how much water went in.",
            "**Reconstitute** records the water, the kind of water and the date, and starts the 28-day use-by date.",
            "**Amount left** corrects how much is in an open vial, in mL or as an amount. Use it when you have counted by eye, or added a vial that was already in use.",
            "**Add diluent** tops up a mixed vial. **Mark empty** retires one.",
            "The **water shelf** tracks bottles of bacteriostatic water, so mixing can take from one.",
            "When you log a dose, Bench takes it from a suitable vial. **Drawn from** in the log form says which, and you can change it.",
            "Low-stock and **runs out** dates follow your plan, so they move if you change the schedule or pause.",
            "Prices you enter give cost per dose and total spent.",
        ]),
        .open("stock"),
    ]),
    GuideTopic(id: "calculator", title: "The calculator", symbol: "function",
               summary: "Where to draw to, and what to do with the answer.", blocks: [
        .steps([
            "Open **More → Calc**. Choose the syringe you are holding. **Check the barrel**: a U-40 barrel read as U-100 delivers 2.5 times the dose.",
            "Optionally choose a peptide to fill in a typical vial size and dose, then enter the vial strength, the water to add and the dose you want.",
            "The syringe shows where to draw to, with the volume, the units and the doses per vial. **Water volumes that read more cleanly** lists amounts of water whose draw lands exactly on a printed mark.",
            "With a peptide chosen, **Use this mix** can start a protocol at this dose, mark a sealed vial as mixed with this water, or add a vial already mixed this way. Each opens the usual form, filled in, for you to check.",
        ]),
        .tip("The arithmetic is exact. It cannot check what is actually in your vial."),
    ]),
    GuideTopic(id: "plans", title: "Protocols, blends and pausing", symbol: "checklist",
               summary: "Schedules, titration, blends and pauses.", blocks: [
        .points([
            "**Fixed** keeps one dose. **Titration** follows a ladder of doses. **By weeks** sets a dose for each stretch of weeks.",
            "A schedule is daily, every N days, set weekdays, or as needed. Several times a day splits the **day's** dose between them. **Weeks on / weeks off** adds a cycle.",
            "Pin **injection sites** and Bench rotates between them. Without pins it suggests the site that has rested longest.",
            "Under the schedule, **Projection** shows how long a protocol takes to settle, how far above a first dose the level builds, and the swing between peaks and troughs. Switch between weekly and daily to compare.",
            "**Pause protocol**, in the **···** on a protocol's card, stops that one. **Plan → ··· → Pause everything** pauses every running protocol until a date or until you resume. Nothing is due, missed or reminded, and the paused days never count against you.",
            "**Blends:** the dose of a blend is the total you draw, shown per part ('250 mcg each'). Each part is modelled on its own half-life. For a library blend that does not state amounts (such as Wolverine), enter what is in your vial when asked, and doses split per part.",
            "A blend that is not in the library: **Not in the list? Add your own**, then list its parts and amounts.",
        ]),
        .open("plan"),
    ]),
    GuideTopic(id: "reminders", title: "Reminders", symbol: "bell",
               summary: "Notifications, what they say, and logging from them.", blocks: [
        .points([
            "**Settings → Dose reminders → Remind me:** at the time, or 15 to 60 minutes before. iOS asks permission the first time.",
            "By default a reminder says only that a dose is due, so a lock screen reveals nothing. Switch **What it says** to name the compound; it then shows the dose and how much to draw, such as '250 mcg due. 10 units.'",
            "A reminder has **Log now** and **Snooze** buttons. Logging from it works with the app closed.",
            "Reminders follow your plan: they update when you change it and stop during a pause. iOS allows about 60 upcoming ones.",
            "**Export doses to calendar** sends the coming weeks to a calendar app as events with alarms.",
        ]),
    ]),
    GuideTopic(id: "body", title: "Weight, how you feel and bloodwork", symbol: "scalemass",
               summary: "Tracking whether it is doing anything.", blocks: [
        .points([
            "**Weight:** add a reading, or let Bench read from Apple Health, which it does each time you open the app. Bench only reads from Health and never writes to it. **Trend** lays your weight against dose steps.",
            "**Goal:** **Set a weight goal** draws a line and, from your last 30 days of weigh-ins, says when the trend would reach it. It never suggests a target.",
            "**How you feel:** rate the day in a few taps. Bench compares ratings across dose changes.",
            "**Bloodwork:** add results by hand or use **Import bloodwork photo** to read a report. Each marker is charted against your doses. Reference ranges are guidelines; enter your lab's own if you have them.",
        ]),
    ]),
    GuideTopic(id: "data", title: "Your data, backups and privacy", symbol: "lock",
               summary: "Where records live, backing up, and the app lock.", blocks: [
        .points([
            "There is no account, no server and no analytics. Records are kept on your device, and also in your private iCloud where a build has iCloud turned on.",
            "**Settings → Automatic backups** keeps rotating copies in Files. **Settings → Your data** exports a full backup, or a CSV of your doses.",
            "**Settings → Your data → Import from another app** reads Injectly, Shotsy, spreadsheets, a Bench backup or a lab report.",
            "A backup is the same format as the web and Android versions of Bench.",
            "**Settings → Privacy → Lock Bench** asks for Face ID, Touch ID or your passcode on opening, and blanks the app switcher.",
        ]),
        .caution("Nobody can recover your records for you. Keep a backup somewhere you control."),
    ]),
    GuideTopic(id: "numbers", title: "Reading the numbers", symbol: "chart.xyaxis.line",
               summary: "Where figures come from, and how far to trust them.", blocks: [
        .points([
            "The library is the original Bench project's reference data. Each half-life and dose range carries a note saying how well supported it is, with sources you can follow.",
            "Dose ranges are tagged **Approved** (a prescribing label), **Clinical** (doses used in published trials), **Preliminary** (very early human data) or **Anecdotal** (community convention).",
            "Levels come from a one-compartment model scaled to your doses. Many compounds have no half-life measured in people; those draw a dashed estimate or no curve at all.",
            "Ranges describe what labels, trials or the community use. They are not recommendations.",
        ]),
        .caution("Bench is not medical advice, and cannot check what is in your vial. Talk to whoever looks after your health."),
    ]),
    GuideTopic(id: "devices", title: "iPad and Mac", symbol: "ipad.and.iphone",
               summary: "What differs on a larger screen.", blocks: [
        .points([
            "A sidebar lists every screen. On a narrow window the extra screens sit under **More**, as on iPhone.",
            "**Now** goes to two columns when there is room.",
            "On a Mac, **⌘N** logs a dose, **⇧⌘N** opens another window (each keeps its own screen), and **⌘,** opens Settings.",
            "The Mac's **Log** has a **Table** view you can sort by any column; double-click a row to edit it.",
            "Scanning a vial on a Mac reads a photo or file, since there is no camera to point. Apple Health is iPhone-only.",
        ]),
    ]),
]
