import Foundation

// Port of src/lib/types.ts. JSON keys match the original exactly, so a Bench
// backup imports directly and an export from here opens in the web app.
//
// Timestamps are epoch milliseconds as `Double`, as in the JSON.
// `Protocol` is `DoseProtocol` here, because `Protocol` is taken in Swift.

/// Epoch milliseconds.
public typealias Millis = Double

// MARK: - Enumerations

public struct Route: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let subcutaneous: Route = "subcutaneous"
    public static let intramuscular: Route = "intramuscular"
    public static let oral: Route = "oral"
    public static let intranasal: Route = "intranasal"
    public static let topical: Route = "topical"
    public static let intravenous: Route = "intravenous"
    public static let allCases: [Route] = [.subcutaneous, .intramuscular, .oral, .intranasal, .topical, .intravenous]

    public var label: String {
        switch self {
        case .subcutaneous: "Subcutaneous"
        case .intramuscular: "Intramuscular"
        case .oral: "Oral"
        case .intranasal: "Intranasal"
        case .topical: "Topical"
        case .intravenous: "Intravenous"
        default: rawValue
        }
    }
}

public struct EvidenceLevel: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let approved: EvidenceLevel = "approved"
    public static let clinical: EvidenceLevel = "clinical"
    public static let preliminary: EvidenceLevel = "preliminary"
    public static let preclinical: EvidenceLevel = "preclinical"
    public static let anecdotal: EvidenceLevel = "anecdotal"
    public static let allCases: [EvidenceLevel] = [.approved, .clinical, .preliminary, .preclinical, .anecdotal]

    public var label: String {
        switch self {
        case .approved: "Approved label"
        case .clinical: "Clinical trial"
        case .preliminary: "Early human data"
        case .preclinical: "Animal data only"
        case .anecdotal: "Community practice"
        default: rawValue
        }
    }

    public var detail: String {
        switch self {
        case .approved: "Dosing comes from an FDA-approved prescribing label."
        case .clinical: "Dosing comes from published human clinical trials."
        case .preliminary: "Human data exists but is limited to small or early-phase studies."
        case .preclinical: "Only animal or laboratory data supports this. No human dosing has been established."
        case .anecdotal: "Widely repeated in community protocols with no clinical evidence behind it."
        default: ""
        }
    }
}

public struct MechanismClass: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let glp1Agonist: MechanismClass = "glp1-agonist"
    public static let gipAgonist: MechanismClass = "gip-agonist"
    public static let glucagonAgonist: MechanismClass = "glucagon-agonist"
    public static let amylinAnalogue: MechanismClass = "amylin-analogue"
    public static let ghrhAnalogue: MechanismClass = "ghrh-analogue"
    public static let ghrelinAgonist: MechanismClass = "ghrelin-agonist"
    public static let aromataseInhibitor: MechanismClass = "aromatase-inhibitor"
    public static let serm: MechanismClass = "serm"
    public static let gonadotropin: MechanismClass = "gonadotropin"
    public static let allCases: [MechanismClass] = [
        .glp1Agonist, .gipAgonist, .glucagonAgonist, .amylinAnalogue, .ghrhAnalogue,
        .ghrelinAgonist, .aromataseInhibitor, .serm, .gonadotropin,
    ]
}

public struct PeptideCategory: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let metabolic: PeptideCategory = "metabolic"
    public static let repair: PeptideCategory = "repair"
    public static let growthHormone: PeptideCategory = "growth-hormone"
    public static let cognitive: PeptideCategory = "cognitive"
    public static let longevity: PeptideCategory = "longevity"
    public static let immune: PeptideCategory = "immune"
    public static let sexual: PeptideCategory = "sexual"
    public static let cosmetic: PeptideCategory = "cosmetic"
    public static let anabolic: PeptideCategory = "anabolic"
    public static let ancillary: PeptideCategory = "ancillary"
    public static let blend: PeptideCategory = "blend"
    public static let allCases: [PeptideCategory] = [
        .metabolic, .repair, .growthHormone, .cognitive, .longevity, .immune,
        .sexual, .cosmetic, .anabolic, .ancillary, .blend,
    ]

    public var label: String {
        switch self {
        case .metabolic: "Metabolic"
        case .repair: "Repair & healing"
        case .growthHormone: "Growth hormone axis"
        case .cognitive: "Cognitive"
        case .longevity: "Longevity & mitochondrial"
        case .immune: "Immune"
        case .sexual: "Sexual function"
        case .cosmetic: "Skin & cosmetic"
        case .anabolic: "Anabolic steroids"
        case .ancillary: "Ancillaries & recovery"
        case .blend: "Blends"
        default: rawValue
        }
    }
}

public struct ProfileTone: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let mint: ProfileTone = "mint"
    public static let grape: ProfileTone = "grape"
    public static let tangerine: ProfileTone = "tangerine"
    public static let sky: ProfileTone = "sky"
    public static let rose: ProfileTone = "rose"
    public static let leaf: ProfileTone = "leaf"
    public static let allCases: [ProfileTone] = [.mint, .grape, .tangerine, .sky, .rose, .leaf]
}

public struct WeightUnit: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let kg: WeightUnit = "kg"
    public static let lb: WeightUnit = "lb"
    public static let allCases: [WeightUnit] = [.kg, .lb]
}

public struct ScheduleKind: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let daily: ScheduleKind = "daily"
    public static let intervalDays: ScheduleKind = "interval-days"
    public static let daysOfWeek: ScheduleKind = "days-of-week"
    public static let asNeeded: ScheduleKind = "as-needed"
    public static let allCases: [ScheduleKind] = [.daily, .intervalDays, .daysOfWeek, .asNeeded]
}

public struct SyringeScale: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let u100: SyringeScale = "U100"
    public static let u40: SyringeScale = "U40"
    public static let allCases: [SyringeScale] = [.u100, .u40]
}

public struct MeasurementSource: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let manual: MeasurementSource = "manual"
    /// Kept as the original's value so exports stay compatible. On iOS this means HealthKit.
    public static let healthConnect: MeasurementSource = "health-connect"
    public static let allCases: [MeasurementSource] = [.manual, .healthConnect]
}

public struct SymptomId: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let energy: SymptomId = "energy"
    public static let mood: SymptomId = "mood"
    public static let libido: SymptomId = "libido"
    public static let sleep: SymptomId = "sleep"
    public static let recovery: SymptomId = "recovery"
    public static let appetite: SymptomId = "appetite"
    public static let foodNoise: SymptomId = "foodNoise"
    public static let allCases: [SymptomId] = [.energy, .mood, .libido, .sleep, .recovery, .appetite, .foodNoise]
}

public struct InjectionSite: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let abdomenUL: InjectionSite = "abdomen-ul"
    public static let abdomenUM: InjectionSite = "abdomen-um"
    public static let abdomenUR: InjectionSite = "abdomen-ur"
    public static let abdomenLL: InjectionSite = "abdomen-ll"
    public static let abdomenLM: InjectionSite = "abdomen-lm"
    public static let abdomenLR: InjectionSite = "abdomen-lr"
    public static let thighL: InjectionSite = "thigh-l"
    public static let thighR: InjectionSite = "thigh-r"
    public static let armL: InjectionSite = "arm-l"
    public static let armR: InjectionSite = "arm-r"
    public static let gluteL: InjectionSite = "glute-l"
    public static let gluteR: InjectionSite = "glute-r"
    public static let allCases: [InjectionSite] = INJECTION_SITES.map(\.id)

    /// The English label, also what the CSV export writes. Falls back to the raw id
    /// so a site this version has never heard of still shows something.
    public var label: String {
        INJECTION_SITES.first { $0.id == self }?.label ?? rawValue
    }
}

public struct VialState: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let onOrder: VialState = "on-order"
    public static let sealed: VialState = "sealed"
    public static let reconstituted: VialState = "reconstituted"
    public static let finished: VialState = "finished"
    public static let discarded: VialState = "discarded"
    public static let allCases: [VialState] = [.onOrder, .sealed, .reconstituted, .finished, .discarded]
}

public struct ContainerKind: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let vial: ContainerKind = "vial"
    public static let spray: ContainerKind = "spray"
    public static let pack: ContainerKind = "pack"
    public static let allCases: [ContainerKind] = [.vial, .spray, .pack]
}

public struct DiluentKind: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let bacteriostatic: DiluentKind = "bacteriostatic"
    public static let sterile: DiluentKind = "sterile"
    public static let saline: DiluentKind = "saline"
    public static let oil: DiluentKind = "oil"
    public static let allCases: [DiluentKind] = [.bacteriostatic, .sterile, .saline, .oil]
}

public struct BottleState: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let sealed: BottleState = "sealed"
    public static let open: BottleState = "open"
    public static let finished: BottleState = "finished"
    public static let discarded: BottleState = "discarded"
    public static let allCases: [BottleState] = [.sealed, .open, .finished, .discarded]
}

public struct LabCategory: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let growth: LabCategory = "growth"
    public static let metabolic: LabCategory = "metabolic"
    public static let lipids: LabCategory = "lipids"
    public static let organ: LabCategory = "organ"
    public static let blood: LabCategory = "blood"
    public static let cardio: LabCategory = "cardio"
    public static let allCases: [LabCategory] = [.growth, .metabolic, .lipids, .organ, .blood, .cardio]
}

public struct Sex: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let male: Sex = "male"
    public static let female: Sex = "female"
    public static let other: Sex = "other"
    public static let allCases: [Sex] = [.male, .female, .other]
}

public struct Preparation: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let powder: Preparation = "powder"
    public static let solution: Preparation = "solution"
    public static let tablet: Preparation = "tablet"
    public static let allCases: [Preparation] = [.powder, .solution, .tablet]
}

public struct BlendDosing: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let split: BlendDosing = "split"
    public static let perComponent: BlendDosing = "per-component"
    public static let allCases: [BlendDosing] = [.split, .perComponent]
}

public struct ThemeSetting: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let dark: ThemeSetting = "dark"
    public static let light: ThemeSetting = "light"
    public static let system: ThemeSetting = "system"
    public static let allCases: [ThemeSetting] = [.dark, .light, .system]
}

public struct DoseUnit: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let mcg: DoseUnit = "mcg"
    public static let mg: DoseUnit = "mg"
    public static let allCases: [DoseUnit] = [.mcg, .mg]
}

public struct BandTone: StringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let leaf: BandTone = "leaf"
    public static let tangerine: BandTone = "tangerine"
    public static let rose: BandTone = "rose"
    public static let allCases: [BandTone] = [.leaf, .tangerine, .rose]
}

// MARK: - Library

public struct DoseRange: Codable, Equatable, Sendable {
    public var lowMcg: Double
    public var highMcg: Double
    public var frequency: String
    public var perWeek: Double
    public var evidence: EvidenceLevel
    public var note: String?

    public init(lowMcg: Double, highMcg: Double, frequency: String, perWeek: Double, evidence: EvidenceLevel, note: String? = nil) {
        self.lowMcg = lowMcg; self.highMcg = highMcg; self.frequency = frequency
        self.perWeek = perWeek; self.evidence = evidence; self.note = note
    }
}

public struct TitrationStep: Codable, Equatable, Sendable {
    public var step: Int
    public var doseMcg: Double
    public var weeks: Double
    public var note: String?

    public init(step: Int, doseMcg: Double, weeks: Double, note: String? = nil) {
        self.step = step; self.doseMcg = doseMcg; self.weeks = weeks; self.note = note
    }
}

public struct TitrationPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var source: String
    public var sourceUrl: String?
    public var evidence: EvidenceLevel
    public var steps: [TitrationStep]
    public var note: String?
}

public struct Citation: Codable, Equatable, Sendable {
    public var label: String
    public var url: String
}

public struct HalfLifeEstimate: Codable, Equatable, Sendable {
    public var hours: Double
    /// Only `preclinical`, `preliminary` or `anecdotal`.
    public var evidence: EvidenceLevel
    public var species: String?
    public var route: Route?
    public var source: String
    public var url: String
}

public struct TimelineEntry: Codable, Equatable, Sendable {
    public var fromHours: Double
    public var toHours: Double
    public var label: String
}

public struct BlendComponent: Codable, Equatable, Sendable {
    public var peptideId: String?
    public var name: String
    public var mgPerVial: Double?

    public init(peptideId: String? = nil, name: String, mgPerVial: Double? = nil) {
        self.peptideId = peptideId; self.name = name; self.mgPerVial = mgPerVial
    }
}

public struct Peptide: Row {
    public var id: String
    public var name: String
    public var aka: [String]
    public var category: PeptideCategory
    public var summary: String
    public var mechanism: String
    /// nil when unknown, and then no curve is drawn.
    public var halfLifeHours: Double?
    public var halfLifeNote: String?
    public var halfLifeEstimate: HalfLifeEstimate?
    public var tmaxHours: Double?
    public var routes: [Route]
    public var doseRanges: [DoseRange]
    public var titrations: [TitrationPlan]?
    public var preparation: Preparation?
    public var iuPerMg: Double?
    public var concentrationsMgPerMl: [Double]?
    public var vialSizesMg: [Double]
    public var reconstitutedDays: Double?
    public var c17AlphaAlkylated: Bool?
    public var suppressesNaturalProduction: Bool?
    public var aromatises: Bool?
    public var timeline: [TimelineEntry]?
    public var sideEffects: [String]
    public var contraindications: [String]
    public var status: String
    public var mechanismClass: [MechanismClass]?
    public var components: [BlendComponent]?
    public var blendDosing: BlendDosing?
    public var citations: [Citation]
    public var cautionBanner: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, aka, category, summary, mechanism, halfLifeHours, halfLifeNote, halfLifeEstimate
        case tmaxHours, routes, doseRanges, titrations, preparation, iuPerMg, concentrationsMgPerMl
        case vialSizesMg, reconstitutedDays, c17AlphaAlkylated, suppressesNaturalProduction, aromatises
        case timeline, sideEffects, contraindications, status, mechanismClass, components, blendDosing
        case citations, cautionBanner
    }
    public static let knownKeys = CodingKeys.rawNames

    public init(
        id: String, name: String, aka: [String] = [], category: PeptideCategory, summary: String = "",
        mechanism: String = "", halfLifeHours: Double? = nil, routes: [Route] = [], doseRanges: [DoseRange] = [],
        vialSizesMg: [Double] = [], sideEffects: [String] = [], contraindications: [String] = [],
        status: String = "", citations: [Citation] = []
    ) {
        self.id = id; self.name = name; self.aka = aka; self.category = category; self.summary = summary
        self.mechanism = mechanism; self.halfLifeHours = halfLifeHours; self.routes = routes
        self.doseRanges = doseRanges; self.vialSizesMg = vialSizesMg; self.sideEffects = sideEffects
        self.contraindications = contraindications; self.status = status; self.citations = citations
    }

    // `halfLifeHours: null` must be written as null, not omitted: the original
    // distinguishes "unknown" (null) and the field is required in the type.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(aka, forKey: .aka)
        try c.encode(category, forKey: .category)
        try c.encode(summary, forKey: .summary)
        try c.encode(mechanism, forKey: .mechanism)
        try c.encode(halfLifeHours, forKey: .halfLifeHours)
        try c.encodeIfPresent(halfLifeNote, forKey: .halfLifeNote)
        try c.encodeIfPresent(halfLifeEstimate, forKey: .halfLifeEstimate)
        try c.encodeIfPresent(tmaxHours, forKey: .tmaxHours)
        try c.encode(routes, forKey: .routes)
        try c.encode(doseRanges, forKey: .doseRanges)
        try c.encodeIfPresent(titrations, forKey: .titrations)
        try c.encodeIfPresent(preparation, forKey: .preparation)
        try c.encodeIfPresent(iuPerMg, forKey: .iuPerMg)
        try c.encodeIfPresent(concentrationsMgPerMl, forKey: .concentrationsMgPerMl)
        try c.encode(vialSizesMg, forKey: .vialSizesMg)
        try c.encodeIfPresent(reconstitutedDays, forKey: .reconstitutedDays)
        try c.encodeIfPresent(c17AlphaAlkylated, forKey: .c17AlphaAlkylated)
        try c.encodeIfPresent(suppressesNaturalProduction, forKey: .suppressesNaturalProduction)
        try c.encodeIfPresent(aromatises, forKey: .aromatises)
        try c.encodeIfPresent(timeline, forKey: .timeline)
        try c.encode(sideEffects, forKey: .sideEffects)
        try c.encode(contraindications, forKey: .contraindications)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(mechanismClass, forKey: .mechanismClass)
        try c.encodeIfPresent(components, forKey: .components)
        try c.encodeIfPresent(blendDosing, forKey: .blendDosing)
        try c.encode(citations, forKey: .citations)
        try c.encodeIfPresent(cautionBanner, forKey: .cautionBanner)
    }

    // Custom compounds come from user input and imports, so the arrays that
    // the type calls required are read leniently: missing means empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        aka = try c.decodeIfPresent([String].self, forKey: .aka) ?? []
        category = try c.decodeIfPresent(PeptideCategory.self, forKey: .category) ?? .repair
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        mechanism = try c.decodeIfPresent(String.self, forKey: .mechanism) ?? ""
        halfLifeHours = try c.decodeIfPresent(Double.self, forKey: .halfLifeHours)
        halfLifeNote = try c.decodeIfPresent(String.self, forKey: .halfLifeNote)
        halfLifeEstimate = try? c.decodeIfPresent(HalfLifeEstimate.self, forKey: .halfLifeEstimate)
        tmaxHours = try c.decodeIfPresent(Double.self, forKey: .tmaxHours)
        routes = try c.decodeIfPresent([Route].self, forKey: .routes) ?? []
        doseRanges = try c.decodeIfPresent([DoseRange].self, forKey: .doseRanges) ?? []
        titrations = try c.decodeIfPresent([TitrationPlan].self, forKey: .titrations)
        preparation = try c.decodeIfPresent(Preparation.self, forKey: .preparation)
        iuPerMg = try c.decodeIfPresent(Double.self, forKey: .iuPerMg)
        concentrationsMgPerMl = try c.decodeIfPresent([Double].self, forKey: .concentrationsMgPerMl)
        vialSizesMg = try c.decodeIfPresent([Double].self, forKey: .vialSizesMg) ?? []
        reconstitutedDays = try c.decodeIfPresent(Double.self, forKey: .reconstitutedDays)
        c17AlphaAlkylated = try c.decodeIfPresent(Bool.self, forKey: .c17AlphaAlkylated)
        suppressesNaturalProduction = try c.decodeIfPresent(Bool.self, forKey: .suppressesNaturalProduction)
        aromatises = try c.decodeIfPresent(Bool.self, forKey: .aromatises)
        timeline = try c.decodeIfPresent([TimelineEntry].self, forKey: .timeline)
        sideEffects = try c.decodeIfPresent([String].self, forKey: .sideEffects) ?? []
        contraindications = try c.decodeIfPresent([String].self, forKey: .contraindications) ?? []
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        mechanismClass = try c.decodeIfPresent([MechanismClass].self, forKey: .mechanismClass)
        components = try c.decodeIfPresent([BlendComponent].self, forKey: .components)
        blendDosing = try c.decodeIfPresent(BlendDosing.self, forKey: .blendDosing)
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        cautionBanner = try c.decodeIfPresent(String.self, forKey: .cautionBanner)
    }
}

// MARK: - People

public struct Profile: Row {
    public var id: String
    public var name: String
    public var tone: ProfileTone
    public var weightKg: Double?
    public var heightCm: Double?
    public var birthYear: Int?
    public var sex: Sex?
    public var createdAt: Millis
    public var notes: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, tone, weightKg, heightCm, birthYear, sex, createdAt, notes
    }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, name: String, tone: ProfileTone, createdAt: Millis, weightKg: Double? = nil,
                heightCm: Double? = nil, birthYear: Int? = nil, sex: Sex? = nil, notes: String? = nil) {
        self.id = id; self.name = name; self.tone = tone; self.createdAt = createdAt
        self.weightKg = weightKg; self.heightCm = heightCm; self.birthYear = birthYear
        self.sex = sex; self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        tone = (try? c.decodeIfPresent(ProfileTone.self, forKey: .tone)) ?? .mint
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        heightCm = try? c.decodeIfPresent(Double.self, forKey: .heightCm)
        birthYear = (try? c.decodeIfPresent(Double.self, forKey: .birthYear)).flatMap { $0.map { Int($0) } }
        sex = try? c.decodeIfPresent(Sex.self, forKey: .sex)
        createdAt = (try? c.decodeIfPresent(Millis.self, forKey: .createdAt)) ?? 0
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }
}

// MARK: - Protocols and logs

public struct Schedule: Codable, Equatable, Sendable {
    public var kind: ScheduleKind
    /// For `interval-days`: 1 = daily, 2 = every other day, 3.5 = twice weekly.
    public var intervalDays: Double?
    /// For `days-of-week`: 0 = Sunday … 6 = Saturday.
    public var daysOfWeek: [Int]?
    /// Legacy single "HH:mm".
    public var timeOfDay: String?
    public var timesOfDay: [String]?
    public var cycleWeeksOn: Double?
    public var cycleWeeksOff: Double?

    public init(kind: ScheduleKind, intervalDays: Double? = nil, daysOfWeek: [Int]? = nil, timeOfDay: String? = nil,
                timesOfDay: [String]? = nil, cycleWeeksOn: Double? = nil, cycleWeeksOff: Double? = nil) {
        self.kind = kind; self.intervalDays = intervalDays; self.daysOfWeek = daysOfWeek
        self.timeOfDay = timeOfDay; self.timesOfDay = timesOfDay
        self.cycleWeeksOn = cycleWeeksOn; self.cycleWeeksOff = cycleWeeksOff
    }
}

public struct ProtocolPhase: Codable, Equatable, Sendable {
    public var step: Int
    public var doseMcg: Double
    public var weeks: Double
    public var schedule: Schedule?
    public var note: String?

    public init(step: Int, doseMcg: Double, weeks: Double, schedule: Schedule? = nil, note: String? = nil) {
        self.step = step; self.doseMcg = doseMcg; self.weeks = weeks; self.schedule = schedule; self.note = note
    }
}

/// `Protocol` in the original.
public struct DoseProtocol: Row {
    public var id: String
    public var profileId: String
    public var peptideId: String
    public var name: String
    public var active: Bool
    public var startedAt: Millis
    public var endedAt: Millis?
    public var doseMcg: Double
    public var route: Route
    public var schedule: Schedule
    public var scheduleChangedAt: Millis?
    public var titration: [TitrationStep]?
    public var titrationAutoAdvance: Bool
    public var phases: [ProtocolPhase]?
    public var sites: [InjectionSite]?
    public var notes: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, profileId, peptideId, name, active, startedAt, endedAt, doseMcg, route, schedule
        case scheduleChangedAt, titration, titrationAutoAdvance, phases, sites, notes
    }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, peptideId: String, name: String, active: Bool = true,
                startedAt: Millis, endedAt: Millis? = nil, doseMcg: Double, route: Route, schedule: Schedule,
                scheduleChangedAt: Millis? = nil, titration: [TitrationStep]? = nil,
                titrationAutoAdvance: Bool = false, phases: [ProtocolPhase]? = nil,
                sites: [InjectionSite]? = nil, notes: String? = nil) {
        self.id = id; self.profileId = profileId; self.peptideId = peptideId; self.name = name
        self.active = active; self.startedAt = startedAt; self.endedAt = endedAt; self.doseMcg = doseMcg
        self.route = route; self.schedule = schedule; self.scheduleChangedAt = scheduleChangedAt
        self.titration = titration; self.titrationAutoAdvance = titrationAutoAdvance
        self.phases = phases; self.sites = sites; self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        peptideId = try c.decode(String.self, forKey: .peptideId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        startedAt = try c.decodeIfPresent(Millis.self, forKey: .startedAt) ?? 0
        endedAt = try c.decodeIfPresent(Millis.self, forKey: .endedAt)
        doseMcg = try c.decodeIfPresent(Double.self, forKey: .doseMcg) ?? 0
        route = try c.decodeIfPresent(Route.self, forKey: .route) ?? .subcutaneous
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? Schedule(kind: .daily)
        scheduleChangedAt = try c.decodeIfPresent(Millis.self, forKey: .scheduleChangedAt)
        titration = try c.decodeIfPresent([TitrationStep].self, forKey: .titration)
        titrationAutoAdvance = try c.decodeIfPresent(Bool.self, forKey: .titrationAutoAdvance) ?? false
        phases = try c.decodeIfPresent([ProtocolPhase].self, forKey: .phases)
        sites = try c.decodeIfPresent([InjectionSite].self, forKey: .sites)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

public struct DoseLog: Row {
    public var id: String
    public var profileId: String
    public var protocolId: String?
    public var peptideId: String
    public var at: Millis
    public var doseMcg: Double
    public var route: Route
    public var site: InjectionSite?
    public var vialId: String?
    public var volumeMl: Double?
    public var units: Double?
    public var presses: Double?
    public var tablets: Double?
    public var syringeId: String?
    public var syringeScale: SyringeScale?
    public var skipped: Bool?
    public var notes: String?
    /// 1–5.
    public var feeling: Int?
    public var sideEffects: [String]?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, profileId, protocolId, peptideId, at, doseMcg, route, site, vialId, volumeMl, units
        case presses, tablets, syringeId, syringeScale, skipped, notes, feeling, sideEffects
    }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, protocolId: String? = nil, peptideId: String, at: Millis,
                doseMcg: Double, route: Route, site: InjectionSite? = nil, vialId: String? = nil,
                volumeMl: Double? = nil, units: Double? = nil, presses: Double? = nil, tablets: Double? = nil,
                syringeId: String? = nil, syringeScale: SyringeScale? = nil, skipped: Bool? = nil,
                notes: String? = nil, feeling: Int? = nil, sideEffects: [String]? = nil) {
        self.id = id; self.profileId = profileId; self.protocolId = protocolId; self.peptideId = peptideId
        self.at = at; self.doseMcg = doseMcg; self.route = route; self.site = site; self.vialId = vialId
        self.volumeMl = volumeMl; self.units = units; self.presses = presses; self.tablets = tablets
        self.syringeId = syringeId; self.syringeScale = syringeScale; self.skipped = skipped
        self.notes = notes; self.feeling = feeling; self.sideEffects = sideEffects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        protocolId = try c.decodeIfPresent(String.self, forKey: .protocolId)
        peptideId = try c.decode(String.self, forKey: .peptideId)
        at = try c.decode(Millis.self, forKey: .at)
        doseMcg = try c.decodeIfPresent(Double.self, forKey: .doseMcg) ?? 0
        route = try c.decodeIfPresent(Route.self, forKey: .route) ?? .subcutaneous
        site = try c.decodeIfPresent(InjectionSite.self, forKey: .site)
        vialId = try c.decodeIfPresent(String.self, forKey: .vialId)
        volumeMl = try c.decodeIfPresent(Double.self, forKey: .volumeMl)
        units = try c.decodeIfPresent(Double.self, forKey: .units)
        presses = try c.decodeIfPresent(Double.self, forKey: .presses)
        tablets = try c.decodeIfPresent(Double.self, forKey: .tablets)
        syringeId = try c.decodeIfPresent(String.self, forKey: .syringeId)
        syringeScale = try c.decodeIfPresent(SyringeScale.self, forKey: .syringeScale)
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        feeling = (try? c.decodeIfPresent(Double.self, forKey: .feeling)).flatMap { $0.map { Int(jsRound($0)) } }
        sideEffects = try c.decodeIfPresent([String].self, forKey: .sideEffects)
    }

    public var isSkipped: Bool { skipped == true }
}

// MARK: - Outcomes

public struct SymptomDef: Sendable, Identifiable {
    public var id: SymptomId
    public var label: String
    public var high: String
    public var low: String
    public var higherIsBetter: Bool?
    public var hint: String?
}

public let SYMPTOMS: [SymptomDef] = [
    SymptomDef(id: .energy, label: "Energy", high: "Strong", low: "Flat", higherIsBetter: true),
    SymptomDef(id: .mood, label: "Mood", high: "Good", low: "Low", higherIsBetter: true),
    SymptomDef(id: .libido, label: "Libido", high: "High", low: "Absent", higherIsBetter: true),
    SymptomDef(id: .sleep, label: "Sleep", high: "Deep", low: "Broken", higherIsBetter: true),
    SymptomDef(id: .recovery, label: "Recovery", high: "Fresh", low: "Sore", higherIsBetter: true),
    SymptomDef(
        id: .appetite, label: "Physical hunger", high: "Ravenous", low: "None",
        hint: "What your body is telling you: an empty or growling stomach, flagging energy from not eating, a real need to eat, and whether a meal actually left you satisfied. Not what your head is doing about food, which is the next one."
    ),
    SymptomDef(
        id: .foodNoise, label: "Food noise", high: "Constant", low: "Quiet", higherIsBetter: false,
        hint: "How much of the day food occupied your thoughts: planning the next meal shortly after finishing one, cravings with no hunger behind them, food you could not ignore, the pull to snack when you were not hungry. These two move apart, which is the point of rating them apart: a GLP-1 can quieten the head while the stomach still behaves normally."
    ),
]

public let SYMPTOM_SCALE_MAX = 5

public struct CheckIn: Row {
    public var id: String
    public var profileId: String
    /// Local midnight of the day.
    public var at: Millis
    public var ratings: [String: Double]
    public var notes: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable { case id, profileId, at, ratings, notes }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, at: Millis, ratings: [String: Double], notes: String? = nil) {
        self.id = id; self.profileId = profileId; self.at = at; self.ratings = ratings; self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        at = try c.decode(Millis.self, forKey: .at)
        ratings = (try? c.decodeIfPresent([String: Double].self, forKey: .ratings)) ?? [:]
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public func rating(_ id: SymptomId) -> Double? { ratings[id.rawValue] }
}

public struct BodyMeasurement: Row {
    public var id: String
    public var profileId: String
    public var at: Millis
    public var weightKg: Double?
    public var waistCm: Double?
    public var bodyFatPct: Double?
    public var sleepHours: Double?
    public var restingHrBpm: Double?
    public var notes: String?
    public var source: MeasurementSource?
    public var externalId: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, profileId, at, weightKg, waistCm, bodyFatPct, sleepHours, restingHrBpm, notes, source, externalId
    }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, at: Millis, weightKg: Double? = nil, waistCm: Double? = nil,
                bodyFatPct: Double? = nil, sleepHours: Double? = nil, restingHrBpm: Double? = nil,
                notes: String? = nil, source: MeasurementSource? = nil, externalId: String? = nil) {
        self.id = id; self.profileId = profileId; self.at = at; self.weightKg = weightKg; self.waistCm = waistCm
        self.bodyFatPct = bodyFatPct; self.sleepHours = sleepHours; self.restingHrBpm = restingHrBpm
        self.notes = notes; self.source = source; self.externalId = externalId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        at = try c.decode(Millis.self, forKey: .at)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        waistCm = try c.decodeIfPresent(Double.self, forKey: .waistCm)
        bodyFatPct = try c.decodeIfPresent(Double.self, forKey: .bodyFatPct)
        sleepHours = try c.decodeIfPresent(Double.self, forKey: .sleepHours)
        restingHrBpm = try c.decodeIfPresent(Double.self, forKey: .restingHrBpm)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        source = try c.decodeIfPresent(MeasurementSource.self, forKey: .source)
        externalId = try c.decodeIfPresent(String.self, forKey: .externalId)
    }
}

public let COMMON_SIDE_EFFECTS = [
    "Nausea", "Vomiting", "Diarrhoea", "Constipation", "Headache", "Fatigue", "Appetite loss",
    "Injection site reaction", "Water retention", "Joint pain", "Insomnia", "Flushing",
]

public let FEELING_LABELS: [Int: String] = [1: "Rough", 2: "Off", 3: "Fine", 4: "Good", 5: "Great"]

// MARK: - Stock

public struct Vial: Row {
    public var id: String
    public var profileId: String
    public var peptideId: String
    public var strengthMg: Double
    public var state: VialState
    public var supplier: String?
    public var lot: String?
    public var cost: Double?
    public var currency: String?
    public var orderId: String?
    public var acquiredAt: Millis?
    public var expiresAt: Millis?
    public var reconstitutedAt: Millis?
    public var diluentMl: Double?
    public var diluent: DiluentKind?
    public var diluentBottleId: String?
    /// Mass drawn so far, in mcg. Tracked as mass so sealed-vial doses deplete too.
    public var drawnMcg: Double?
    public var budAt: Millis?
    public var container: ContainerKind?
    public var mgPerTablet: Double?
    public var mlPerSpray: Double?
    public var filledFromVialId: String?
    public var notes: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, profileId, peptideId, strengthMg, state, supplier, lot, cost, currency, orderId
        case acquiredAt, expiresAt, reconstitutedAt, diluentMl, diluent, diluentBottleId, drawnMcg
        case budAt, container, mgPerTablet, mlPerSpray, filledFromVialId, notes
    }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, peptideId: String, strengthMg: Double, state: VialState,
                supplier: String? = nil, lot: String? = nil, cost: Double? = nil, currency: String? = nil,
                orderId: String? = nil, acquiredAt: Millis? = nil, expiresAt: Millis? = nil,
                reconstitutedAt: Millis? = nil, diluentMl: Double? = nil, diluent: DiluentKind? = nil,
                diluentBottleId: String? = nil, drawnMcg: Double? = nil, budAt: Millis? = nil,
                container: ContainerKind? = nil, mgPerTablet: Double? = nil, mlPerSpray: Double? = nil,
                filledFromVialId: String? = nil, notes: String? = nil) {
        self.id = id; self.profileId = profileId; self.peptideId = peptideId; self.strengthMg = strengthMg
        self.state = state; self.supplier = supplier; self.lot = lot; self.cost = cost; self.currency = currency
        self.orderId = orderId; self.acquiredAt = acquiredAt; self.expiresAt = expiresAt
        self.reconstitutedAt = reconstitutedAt; self.diluentMl = diluentMl; self.diluent = diluent
        self.diluentBottleId = diluentBottleId; self.drawnMcg = drawnMcg; self.budAt = budAt
        self.container = container; self.mgPerTablet = mgPerTablet; self.mlPerSpray = mlPerSpray
        self.filledFromVialId = filledFromVialId; self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        peptideId = try c.decode(String.self, forKey: .peptideId)
        strengthMg = try c.decodeIfPresent(Double.self, forKey: .strengthMg) ?? 0
        state = try c.decodeIfPresent(VialState.self, forKey: .state) ?? .sealed
        supplier = try c.decodeIfPresent(String.self, forKey: .supplier)
        lot = try c.decodeIfPresent(String.self, forKey: .lot)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId)
        acquiredAt = try c.decodeIfPresent(Millis.self, forKey: .acquiredAt)
        expiresAt = try c.decodeIfPresent(Millis.self, forKey: .expiresAt)
        reconstitutedAt = try c.decodeIfPresent(Millis.self, forKey: .reconstitutedAt)
        diluentMl = try c.decodeIfPresent(Double.self, forKey: .diluentMl)
        diluent = try c.decodeIfPresent(DiluentKind.self, forKey: .diluent)
        diluentBottleId = try c.decodeIfPresent(String.self, forKey: .diluentBottleId)
        drawnMcg = try c.decodeIfPresent(Double.self, forKey: .drawnMcg)
        budAt = try c.decodeIfPresent(Millis.self, forKey: .budAt)
        container = try c.decodeIfPresent(ContainerKind.self, forKey: .container)
        mgPerTablet = try c.decodeIfPresent(Double.self, forKey: .mgPerTablet)
        mlPerSpray = try c.decodeIfPresent(Double.self, forKey: .mlPerSpray)
        filledFromVialId = try c.decodeIfPresent(String.self, forKey: .filledFromVialId)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    /// Which container, with the pre-spray default applied.
    public var containerKind: ContainerKind { container ?? .vial }
}

public struct DiluentBottle: Row {
    public var id: String
    public var profileId: String
    public var kind: DiluentKind
    public var volumeMl: Double
    public var drawnMl: Double?
    public var state: BottleState
    public var openedAt: Millis?
    public var expiresAt: Millis?
    public var budAt: Millis?
    public var supplier: String?
    public var cost: Double?
    public var currency: String?
    public var orderId: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, profileId, kind, volumeMl, drawnMl, state, openedAt, expiresAt, budAt, supplier, cost, currency, orderId
    }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, kind: DiluentKind, volumeMl: Double, drawnMl: Double? = nil,
                state: BottleState, openedAt: Millis? = nil, expiresAt: Millis? = nil, budAt: Millis? = nil,
                supplier: String? = nil, cost: Double? = nil, currency: String? = nil, orderId: String? = nil) {
        self.id = id; self.profileId = profileId; self.kind = kind; self.volumeMl = volumeMl
        self.drawnMl = drawnMl; self.state = state; self.openedAt = openedAt; self.expiresAt = expiresAt
        self.budAt = budAt; self.supplier = supplier; self.cost = cost; self.currency = currency; self.orderId = orderId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        kind = try c.decodeIfPresent(DiluentKind.self, forKey: .kind) ?? .bacteriostatic
        volumeMl = (try? c.decodeIfPresent(Double.self, forKey: .volumeMl)) ?? 0
        drawnMl = try c.decodeIfPresent(Double.self, forKey: .drawnMl)
        state = try c.decodeIfPresent(BottleState.self, forKey: .state) ?? .sealed
        openedAt = try c.decodeIfPresent(Millis.self, forKey: .openedAt)
        expiresAt = try c.decodeIfPresent(Millis.self, forKey: .expiresAt)
        budAt = try c.decodeIfPresent(Millis.self, forKey: .budAt)
        supplier = try c.decodeIfPresent(String.self, forKey: .supplier)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId)
    }
}

public struct Order: Row {
    public var id: String
    public var profileId: String
    public var shippingCost: Double?
    public var currency: String?
    public var placedAt: Millis
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable { case id, profileId, shippingCost, currency, placedAt }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, shippingCost: Double? = nil, currency: String? = nil, placedAt: Millis) {
        self.id = id; self.profileId = profileId; self.shippingCost = shippingCost
        self.currency = currency; self.placedAt = placedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        shippingCost = try? c.decodeIfPresent(Double.self, forKey: .shippingCost)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        placedAt = (try? c.decodeIfPresent(Millis.self, forKey: .placedAt)) ?? 0
    }
}

// MARK: - Settings

public struct RemindersSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var leadMinutes: Double
    /// Off by default, so a notification on a lock screen does not say what it is for.
    public var showCompound: Bool
    public var calendarDays: Double

    public init(enabled: Bool = false, leadMinutes: Double = 0, showCompound: Bool = false, calendarDays: Double = 90) {
        self.enabled = enabled; self.leadMinutes = leadMinutes
        self.showCompound = showCompound; self.calendarDays = calendarDays
    }

    /// Fills each field from the defaults, as the original's nested spread does.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RemindersSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        leadMinutes = (try? c.decodeIfPresent(Double.self, forKey: .leadMinutes)) ?? d.leadMinutes
        showCompound = (try? c.decodeIfPresent(Bool.self, forKey: .showCompound)) ?? d.showCompound
        calendarDays = (try? c.decodeIfPresent(Double.self, forKey: .calendarDays)) ?? d.calendarDays
    }

    enum CodingKeys: String, CodingKey { case enabled, leadMinutes, showCompound, calendarDays }
}

public let DEFAULT_REMINDERS = RemindersSettings()

public enum StockSort: String, Codable, Sendable { case dateAdded, newestFirst, alphabetical }

public struct ReconstitutionPreference: Codable, Equatable, Sendable {
    public var diluentMl: Double
    public var diluent: DiluentKind
    public var syringeId: String
    public init(diluentMl: Double, diluent: DiluentKind, syringeId: String) {
        self.diluentMl = diluentMl; self.diluent = diluent; self.syringeId = syringeId
    }
}

public struct Settings: Extensible {
    public var theme: ThemeSetting = .system
    public var doseUnit: DoseUnit = .mcg
    public var defaultSyringeId: String?
    public var disclaimerAcceptedAt: Millis?
    public var budWarningDays: Double = 5
    public var lowStockDoses: Double = 4
    /// 0 = Sunday, 1 = Monday.
    public var weekStartsOn: Int = 1
    public var currency: String = defaultCurrency()
    public var weightUnit: WeightUnit = .kg
    public var groupIdenticalVials: Bool?
    public var waterAtBottom: Bool?
    public var backupEnabled: Bool = true
    public var backupIntervalHours: Double = 24
    public var backupKeep: Double = 10
    public var lastBackupAt: Millis?
    public var dataChangedAt: Millis?
    public var backupNagDismissedAt: Millis?
    public var reminders: RemindersSettings? = DEFAULT_REMINDERS
    public var plotWeightOnChart: Bool?
    /// Includes `sync`, which is the self-hosted server's and is carried through untouched.
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case theme, doseUnit, defaultSyringeId, disclaimerAcceptedAt, budWarningDays, lowStockDoses
        case weekStartsOn, currency, weightUnit, groupIdenticalVials, waterAtBottom, backupEnabled
        case backupIntervalHours, backupKeep, lastBackupAt, dataChangedAt, backupNagDismissedAt
        case reminders, plotWeightOnChart
    }
    public static let knownKeys = CodingKeys.rawNames

    public init() {}

    /// `{ ...DEFAULT_SETTINGS, ...stored, reminders: { ...DEFAULT_REMINDERS, ...stored.reminders } }`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        func o<T: Decodable>(_ k: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        theme = v(.theme, d.theme)
        doseUnit = v(.doseUnit, d.doseUnit)
        defaultSyringeId = o(.defaultSyringeId)
        disclaimerAcceptedAt = o(.disclaimerAcceptedAt)
        budWarningDays = v(.budWarningDays, d.budWarningDays)
        lowStockDoses = v(.lowStockDoses, d.lowStockDoses)
        weekStartsOn = v(.weekStartsOn, d.weekStartsOn)
        currency = v(.currency, d.currency)
        weightUnit = v(.weightUnit, d.weightUnit)
        groupIdenticalVials = o(.groupIdenticalVials)
        waterAtBottom = o(.waterAtBottom)
        backupEnabled = v(.backupEnabled, d.backupEnabled)
        backupIntervalHours = v(.backupIntervalHours, d.backupIntervalHours)
        backupKeep = v(.backupKeep, d.backupKeep)
        lastBackupAt = o(.lastBackupAt)
        dataChangedAt = o(.dataChangedAt)
        backupNagDismissedAt = o(.backupNagDismissedAt)
        reminders = v(.reminders, DEFAULT_REMINDERS)
        plotWeightOnChart = o(.plotWeightOnChart)
    }

    public var remindersOrDefault: RemindersSettings { reminders ?? DEFAULT_REMINDERS }
}

public let DEFAULT_SETTINGS = Settings()

/// Doses logged before this hour can count toward the night before.
public let EARLY_HOURS_CUTOFF: Double = 4

extension Settings {
    /// iOS only, kept in `extra` so backups stay readable by the web app and it
    /// syncs: a dose in the early hours answers the previous night's dose when
    /// that is the scheduled time it is nearest to.
    public var earlyHoursCountForNightBefore: Bool {
        get { if case .bool(let b)? = extra["iosEarlyHoursNightBefore"] { return b }; return false }
        set { if newValue { extra["iosEarlyHoursNightBefore"] = .bool(true) } else { extra.removeValue(forKey: "iosEarlyHoursNightBefore") } }
    }

    /// The hours after midnight that count toward the night before; 0 when off.
    public var earlyHours: Double { earlyHoursCountForNightBefore ? EARLY_HOURS_CUTOFF : 0 }

    /// iOS only, in `extra`: how Stock is ordered. Earlier test builds kept it at
    /// the top level, where it now arrives in `extra` under its old name; it is read
    /// from there too, and moves across the next time it is set.
    public var stockSort: StockSort {
        get { (extra["iosStockSort"] ?? extra["stockSort"])?.stringValue.flatMap(StockSort.init(rawValue:)) ?? .dateAdded }
        set {
            extra.removeValue(forKey: "stockSort")
            if newValue == .dateAdded { extra.removeValue(forKey: "iosStockSort") } else { extra["iosStockSort"] = .string(newValue.rawValue) }
        }
    }

    /// iOS only, in `extra`: the water, diluent and syringe last used to mix each
    /// compound, keyed "profileId:peptideId". Read from its old top-level name too.
    public var reconstitutionPreferences: [String: ReconstitutionPreference] {
        get {
            let raw = extra["iosReconstitutionPreferences"] ?? extra["reconstitutionPreferences"]
            return raw.flatMap { try? $0.decode([String: ReconstitutionPreference].self) } ?? [:]
        }
        set {
            extra.removeValue(forKey: "reconstitutionPreferences")
            if newValue.isEmpty { extra.removeValue(forKey: "iosReconstitutionPreferences") }
            else { extra["iosReconstitutionPreferences"] = try? JSONValue.from(newValue) }
        }
    }
}

// MARK: - Labs

public struct LabBand: Codable, Equatable, Sendable {
    public var from: Double?
    public var under: Double?
    public var label: String
    public var tone: BandTone
}

public struct LabGuideline: Codable, Equatable, Sendable {
    public var source: String
    public var bands: [LabBand]
}

public struct LabMarker: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var aka: String?
    public var unit: String
    public var decimals: Int
    public var category: LabCategory
    public var why: String
    public var guideline: LabGuideline?
    public var rangeNote: String?
    public var higherIsBetter: Bool?
}

public struct LabResult: Row {
    public var id: String
    public var profileId: String
    public var at: Millis
    public var markerId: String
    public var value: Double
    public var refLow: Double?
    public var refHigh: Double?
    public var lab: String?
    public var notes: String?
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable { case id, profileId, at, markerId, value, refLow, refHigh, lab, notes }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String, at: Millis, markerId: String, value: Double, refLow: Double? = nil,
                refHigh: Double? = nil, lab: String? = nil, notes: String? = nil) {
        self.id = id; self.profileId = profileId; self.at = at; self.markerId = markerId; self.value = value
        self.refLow = refLow; self.refHigh = refHigh; self.lab = lab; self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        at = try c.decode(Millis.self, forKey: .at)
        markerId = try c.decode(String.self, forKey: .markerId)
        value = try c.decode(Double.self, forKey: .value)
        refLow = try c.decodeIfPresent(Double.self, forKey: .refLow)
        refHigh = try c.decodeIfPresent(Double.self, forKey: .refHigh)
        lab = try c.decodeIfPresent(String.self, forKey: .lab)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

// MARK: - Notes and overrides

public struct HalfLifeOverride: Codable, Equatable, Sendable {
    public var hours: Double
    public var setAt: Millis
    public var note: String?

    public init(hours: Double, setAt: Millis, note: String? = nil) {
        self.hours = hours; self.setAt = setAt; self.note = note
    }
}

public struct CompoundNote: Row {
    public var id: String
    /// Optional in the type, but the store and migration always set it.
    public var profileId: String?
    public var peptideId: String
    public var text: String
    public var updatedAt: Millis
    public var extra: JSONObject = [:]

    enum CodingKeys: String, CodingKey, CaseIterable { case id, profileId, peptideId, text, updatedAt }
    public static let knownKeys = CodingKeys.rawNames

    public init(id: String, profileId: String?, peptideId: String, text: String, updatedAt: Millis) {
        self.id = id; self.profileId = profileId; self.peptideId = peptideId; self.text = text; self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId)
        peptideId = (try? c.decodeIfPresent(String.self, forKey: .peptideId)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        updatedAt = (try? c.decodeIfPresent(Millis.self, forKey: .updatedAt)) ?? 0
    }
}

// MARK: - Constants

public let DEFAULT_PROFILE_ID = "me"
public let DEFAULT_PROFILE = Profile(id: DEFAULT_PROFILE_ID, name: "Me", tone: .mint, createdAt: 0)
public let DATA_VERSION = 9

public struct Currency: Sendable {
    public var code: String
    public var label: String
}

/// The currency of the device's region (Settings > General > Language & Region,
/// no permission needed) when the app offers it, else Australian dollars.
public func defaultCurrency(_ locale: Locale = .autoupdatingCurrent) -> String {
    let code = locale.currency?.identifier ?? ""
    return CURRENCIES.contains { $0.code == code } ? code : "AUD"
}

public let CURRENCIES: [Currency] = [
    Currency(code: "INR", label: "Indian rupee (₹)"),
    Currency(code: "USD", label: "US dollar ($)"),
    Currency(code: "EUR", label: "Euro (€)"),
    Currency(code: "GBP", label: "Pound sterling (£)"),
    Currency(code: "AED", label: "UAE dirham (د.إ)"),
    Currency(code: "CAD", label: "Canadian dollar (C$)"),
    Currency(code: "AUD", label: "Australian dollar (A$)"),
    Currency(code: "SGD", label: "Singapore dollar (S$)"),
]

public struct InjectionSiteInfo: Sendable {
    public var id: InjectionSite
    public var label: String
    public var group: String
}

public let INJECTION_SITES: [InjectionSiteInfo] = [
    InjectionSiteInfo(id: "abdomen-ul", label: "Abdomen, upper left", group: "Abdomen"),
    InjectionSiteInfo(id: "abdomen-um", label: "Abdomen, upper middle", group: "Abdomen"),
    InjectionSiteInfo(id: "abdomen-ur", label: "Abdomen, upper right", group: "Abdomen"),
    InjectionSiteInfo(id: "abdomen-ll", label: "Abdomen, lower left", group: "Abdomen"),
    InjectionSiteInfo(id: "abdomen-lm", label: "Abdomen, lower middle", group: "Abdomen"),
    InjectionSiteInfo(id: "abdomen-lr", label: "Abdomen, lower right", group: "Abdomen"),
    InjectionSiteInfo(id: "thigh-l", label: "Left thigh", group: "Thigh"),
    InjectionSiteInfo(id: "thigh-r", label: "Right thigh", group: "Thigh"),
    InjectionSiteInfo(id: "arm-l", label: "Left arm", group: "Arm"),
    InjectionSiteInfo(id: "arm-r", label: "Right arm", group: "Arm"),
    InjectionSiteInfo(id: "glute-l", label: "Left glute", group: "Glute"),
    InjectionSiteInfo(id: "glute-r", label: "Right glute", group: "Glute"),
]
