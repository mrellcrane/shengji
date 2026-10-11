import ShengjiCore

/// A tiny JSON value with ordered object keys, so the output is byte-for-byte deterministic
/// (Foundation's serialisers differ between platforms and Swift versions).
indirect enum JSON {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    func write(into out: inout String) {
        switch self {
        case .null:
            out += "null"
        case let .bool(value):
            out += value ? "true" : "false"
        case let .int(value):
            out += String(value)
        case let .string(value):
            JSON.writeString(value, into: &out)
        case let .array(items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                item.write(into: &out)
            }
            out += "]"
        case let .object(fields):
            out += "{"
            for (index, field) in fields.enumerated() {
                if index > 0 { out += "," }
                JSON.writeString(field.0, into: &out)
                out += ":"
                field.1.write(into: &out)
            }
            out += "}"
        }
    }

    static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    /// A top-level object with one field per line; arrays are written one element per line, so
    /// a change to the engine shows up as a readable diff.
    static func document(_ fields: [(String, JSON)]) -> String {
        var out = "{\n"
        for (index, field) in fields.enumerated() {
            if index > 0 { out += ",\n" }
            writeString(field.0, into: &out)
            out += ":"
            if case let .array(items) = field.1, !items.isEmpty {
                out += "[\n"
                for (itemIndex, item) in items.enumerated() {
                    if itemIndex > 0 { out += ",\n" }
                    item.write(into: &out)
                }
                out += "\n]"
            } else {
                field.1.write(into: &out)
            }
        }
        out += "\n}\n"
        return out
    }
}

// MARK: Encoders (field names match the TypeScript engine's types)

func json(_ cards: [Card]) -> JSON { .array(cards.map { .int($0.id) }) }

func json(_ card: Card?) -> JSON { card.map { .int($0.id) } ?? .null }

func json(_ suit: Suit?) -> JSON { suit.map { .int($0.rawValue) } ?? .null }

func json(_ rank: Rank) -> JSON { .int(rank.rawValue) }

func json(_ trump: Trump) -> JSON {
    .object([("rank", json(trump.rank)), ("suit", json(trump.suit))])
}

func json(_ group: SuitGroup) -> JSON {
    switch group {
    case .trump: return .string("trump")
    case let .plain(suit): return .int(suit.rawValue)
    }
}

func json(_ group: SuitGroup?) -> JSON { group.map { json($0) } ?? .null }

func json(_ shape: ComboShape) -> JSON {
    switch shape {
    case .single: return .object([("type", .string("single")), ("pairs", .int(0))])
    case .pair: return .object([("type", .string("pair")), ("pairs", .int(1))])
    case let .tractor(n): return .object([("type", .string("tractor")), ("pairs", .int(n))])
    case let .set(n): return .object([("type", .string("set")), ("width", .int(n))])
    case let .setTractor(width, length):
        return .object([("type", .string("setTractor")), ("width", .int(width)), ("length", .int(length))])
    }
}

func json(_ shape: ComboShape?) -> JSON { shape.map { json($0) } ?? .null }

func json(_ component: Component) -> JSON {
    .object([
        ("shape", json(component.shape)),
        ("cards", json(component.cards)),
        ("group", json(component.group)),
        ("topStrength", .int(component.topStrength)),
    ])
}

func json(_ violation: LeadViolation) -> JSON {
    switch violation {
    case .empty: return .string("empty")
    case .cardsNotInHand: return .string("cardsNotInHand")
    case .mixedSuits: return .string("mixedSuits")
    }
}

func json(_ violation: FollowViolation) -> JSON {
    switch violation {
    case let .wrongCount(expected):
        return .object([("case", .string("wrongCount")), ("expected", .int(expected))])
    case .cardsNotInHand:
        return .object([("case", .string("cardsNotInHand"))])
    case let .mustFollowSuit(group):
        return .object([("case", .string("mustFollowSuit")), ("group", json(group))])
    case let .mustPlayTractor(length):
        return .object([("case", .string("mustPlayTractor")), ("length", .int(length))])
    case let .mustPlayPairs(required):
        return .object([("case", .string("mustPlayPairs")), ("required", .int(required))])
    case let .mustPlaySetTractor(width, length):
        return .object([("case", .string("mustPlaySetTractor")), ("width", .int(width)), ("length", .int(length))])
    case let .mustPlaySets(width, required):
        return .object([("case", .string("mustPlaySets")), ("width", .int(width)), ("required", .int(required))])
    }
}

func json(_ error: RoundError) -> JSON {
    switch error {
    case .wrongPhase: return .object([("case", .string("wrongPhase"))])
    case .notYourTurn: return .object([("case", .string("notYourTurn"))])
    case let .illegalLead(violation): return .object([("case", .string("illegalLead")), ("violation", json(violation))])
    case let .illegalFollow(violation):
        return .object([("case", .string("illegalFollow")), ("violation", json(violation))])
    case .invalidDeclaration: return .object([("case", .string("invalidDeclaration"))])
    case let .invalidBury(reason): return .object([("case", .string("invalidBury")), ("reason", .string(reason))])
    }
}

func json(_ check: ThrowCheck) -> JSON {
    switch check {
    case .ok: return .object([("type", .string("ok"))])
    case let .fails(forced, blocker):
        return .object([("type", .string("fails")), ("forced", json(forced)), ("blocker", .int(blocker))])
    }
}

func json(_ outcome: PlayOutcome) -> JSON {
    switch outcome {
    case .played: return .object([("type", .string("played"))])
    case let .throwFailed(forced, blocker):
        return .object([("type", .string("throwFailed")), ("forced", json(forced)), ("blocker", .int(blocker))])
    }
}

func json(_ requirement: FollowRequirement) -> JSON {
    var fields: [(String, JSON)] = [
        ("tractorLengths", .array(requirement.tractorLengths.map { .int($0) })),
        ("totalPairs", .int(requirement.totalPairs)),
    ]
    // Three or more decks: every owed combination (two-deck requirements are fully described above).
    if !requirement.isClassic || requirement.units != FollowRequirement(
        tractorLengths: requirement.tractorLengths, totalPairs: requirement.totalPairs).units {
        fields.append(("units", .array(requirement.units.map { json($0) })))
    }
    return .object(fields)
}

func json(_ declaration: Declaration) -> JSON {
    .object([
        ("player", .int(declaration.player)),
        ("cards", json(declaration.cards)),
        ("suit", json(declaration.suit)),
        ("strength", .int(declaration.strength)),
    ])
}

func json(_ play: Play) -> JSON {
    .object([("player", .int(play.player)), ("cards", json(play.cards))])
}

func json(_ trick: TrickRecord) -> JSON {
    .object([
        ("plays", .array(trick.plays.map { json($0) })),
        ("winner", .int(trick.winner)),
        ("points", .int(trick.points)),
    ])
}

func json(_ outcome: LevelOutcome) -> JSON {
    .object([
        ("declarersHold", .bool(outcome.declarersHold)),
        ("levels", .int(outcome.levels)),
        ("summary", .string(outcome.summary)),
    ])
}

func json(_ result: RoundResult) -> JSON {
    .object([
        ("dealer", .int(result.dealer)),
        ("declarerTeam", .int(result.declarerTeam)),
        ("trump", json(result.trump)),
        ("trickPoints", .int(result.trickPoints)),
        ("kittyPoints", .int(result.kittyPoints)),
        ("kittyMultiplier", .int(result.kittyMultiplier)),
        ("defenderPoints", .int(result.defenderPoints)),
        ("outcome", json(result.outcome)),
        ("kitty", json(result.kitty)),
        ("lastTrickWinner", .int(result.lastTrickWinner)),
    ] + friendFields(result))
}

/// Finding Friends only (absent at tables of fixed teams): the dealer's side and the calls.
func friendFields(_ result: RoundResult) -> [(String, JSON)] {
    var fields: [(String, JSON)] = []
    if let declarers = result.declarers { fields.append(("declarers", .array(declarers.map { .int($0) }))) }
    if let calls = result.friendCalls { fields.append(("friendCalls", json(calls))) }
    return fields
}

func json(_ call: FriendCall) -> JSON {
    .object([("face", .int(call.face.index)), ("ordinal", .int(call.ordinal)), ("friend", json(call.friend))])
}

func json(_ calls: [FriendCall]) -> JSON { .array(calls.map { json($0) }) }

func json(_ value: Int?) -> JSON { value.map { .int($0) } ?? .null }

func json(_ hands: [[Card]]) -> JSON { .array(hands.map { json($0) }) }
