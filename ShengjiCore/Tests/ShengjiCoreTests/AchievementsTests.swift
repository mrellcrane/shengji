import Foundation
import XCTest
@testable import ShengjiCore

final class AchievementsTests: XCTestCase {
    private typealias Kit = CoachTestKit
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// SF Symbols that exist on iOS 17 (all introduced in SF Symbols 1 to 4).
    private let knownSymbols: Set<String> = [
        "bolt.fill", "arrow.up.forward", "gift.fill", "tram.fill", "sparkles", "crown.fill", "star.fill",
        "shippingbox.fill", "flag.fill", "arrow.uturn.up", "shield.fill", "hand.raised.fill",
        "arrow.triangle.2.circlepath", "hand.thumbsup.fill", "arrow.up.circle.fill", "trophy.fill",
        "graduationcap.fill", "flame.fill", "checkmark.seal.fill", "questionmark.circle.fill",
    ]

    private func event(_ kind: MoveKind) -> MoveEvent { MoveEvent(kind: kind, detail: kind.title, points: 0) }

    private func definition(_ id: String) throws -> AchievementDefinition { try XCTUnwrap(Achievements.definition(id: id)) }

    // MARK: Definitions

    func testOneAchievementPerMovePlusTheJourney() throws {
        let all = Achievements.all
        XCTAssertEqual(all.count, MoveKind.allCases.count + 6)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "ids are unique")
        for kind in MoveKind.allCases {
            let definition = try XCTUnwrap(Achievements.definition(for: kind))
            XCTAssertEqual(definition.id, "move." + kind.rawValue)
            XCTAssertEqual(definition.category, .moves)
            XCTAssertEqual(definition.source, .move(kind))
            XCTAssertEqual(definition.title, kind.title)
            XCTAssertEqual(definition.symbol, kind.symbol)
            let rare: Set<MoveKind> = [.shutout, .kittyRaid, .cleanThrow, .overrideDeclaration]
            XCTAssertEqual(definition.thresholds, rare.contains(kind) ? [1, 3, 10] : [1, 5, 25], "\(kind)")
        }
        let journey: [(String, AchievementSource, [Int])] = [
            ("journey.levelReached", .levelReached, [3, 8, 12]), ("journey.gamesWon", .gamesWon, [1, 3, 10]),
            ("journey.lessonsCompleted", .lessonsCompleted, [3, 8, 12]), ("journey.studyStreak", .studyStreak, [3, 7, 30]),
            ("journey.skillsMastered", .skillsMastered, [3, 8, 15]), ("journey.questionsAnswered", .questionsAnswered, [50, 250, 1000]),
        ]
        for (id, source, thresholds) in journey {
            let definition = try self.definition(id)
            XCTAssertEqual(definition.source, source)
            XCTAssertEqual(definition.thresholds, thresholds)
            XCTAssertEqual(definition.category, .journey)
        }
        // Levels: reach 5, 10 and A from 2.
        let levels = try definition("journey.levelReached").thresholds
        XCTAssertEqual(levels.map { Rank.two.rawValue + $0 }, [Rank.five.rawValue, Rank.ten.rawValue, Rank.ace.rawValue])
        // Skills mastered gold is reachable: there are enough items to master.
        XCTAssertLessThanOrEqual(15, SkillID.allCases.count + Curriculum.facts.count)
        XCTAssertNil(Achievements.definition(id: "move.nothing"))
        // Moves come first, then the journey.
        XCTAssertEqual(all.prefix(MoveKind.allCases.count).map(\.category), Array(repeating: .moves, count: MoveKind.allCases.count))
    }

    func testTextsAreShortClearAndPlain() {
        for kind in MoveKind.allCases {
            let words = kind.howTo.split(whereSeparator: { $0 == " " }).count
            XCTAssertLessThanOrEqual(words, 40, "\(kind) howTo has \(words) words")
            XCTAssertTrue(kind.howTo.lowercased().contains("you"), "\(kind) howTo speaks to you")
            XCTAssertFalse(kind.title.isEmpty)
            if let term = kind.chineseTerm {
                XCTAssertTrue(term.contains("(") && term.hasSuffix(")"), "\(kind): \(term) needs pinyin")
            }
            XCTAssertTrue(knownSymbols.contains(kind.symbol), "\(kind.symbol)")
        }
        XCTAssertEqual(MoveKind.ruff.chineseTerm, "毙 (bì)")
        XCTAssertEqual(MoveKind.tractor.symbol, "tram.fill")
        for definition in Achievements.all {
            for text in [definition.title, definition.goal, definition.lesson] {
                XCTAssertFalse(text.isEmpty, definition.id)
                XCTAssertFalse(text.contains(Kit.emDash), definition.id)
                XCTAssertFalse(text.contains("**"), definition.id)
            }
            XCTAssertTrue(knownSymbols.contains(definition.symbol), "\(definition.id): \(definition.symbol)")
            XCTAssertTrue(definition.goal.hasSuffix("."), definition.id)
            XCTAssertEqual(definition.thresholds, definition.thresholds.sorted(), definition.id)
            XCTAssertEqual(definition.thresholds.count, 3, definition.id)
            XCTAssertEqual(Set(definition.exampleCards.map(\.id)).count, definition.exampleCards.count, "\(definition.id): duplicate card")
        }
        for kind in MoveKind.allCases {
            let event = MoveEvent(kind: kind, detail: "", points: 0)
            XCTAssertFalse(event.kind.howTo.contains(Kit.emDash))
        }
    }

    func testExampleCardsIllustrateEachMove() throws {
        func example(_ kind: MoveKind) throws -> (cards: [Card], trump: Trump) {
            let definition = try XCTUnwrap(Achievements.definition(for: kind))
            return (definition.exampleCards, definition.exampleTrump ?? Trump(rank: .two, suit: nil))
        }
        for kind in MoveKind.allCases {
            XCTAssertFalse(try example(kind).cards.isEmpty, "\(kind) has no example")
        }
        let ruff = try example(.ruff)
        XCTAssertFalse(ruff.trump.isTrump(ruff.cards[0]))
        XCTAssertTrue(ruff.trump.isTrump(ruff.cards[1]))
        XCTAssertEqual(Rules.winningIndex([Play(player: 1, cards: [ruff.cards[0]]), Play(player: 0, cards: [ruff.cards[1]])], trump: ruff.trump), 1)

        let overruff = try example(.overruff)
        let plays = zip([1, 3, 0], overruff.cards).map { Play(player: $0.0, cards: [$0.1]) }
        XCTAssertEqual(Rules.winningIndex(plays, trump: overruff.trump), 2)
        XCTAssertEqual(MoveDetector.trickMoves(Kit.trick(plays, trump: overruff.trump), trump: overruff.trump, player: 0).map(\.kind), [.overruff])

        let tractor = try example(.tractor)
        XCTAssertEqual(Combos.shape(of: tractor.cards, trump: tractor.trump), .tractor(2))

        let throwExample = try example(.cleanThrow)
        XCTAssertTrue(Rules.isThrow(throwExample.cards, trump: throwExample.trump))
        let rest = Deck.double().filter { card in !throwExample.cards.contains(card) }
        XCTAssertEqual(Rules.checkThrow(throwExample.cards, against: rest, trump: throwExample.trump), .ok,
                       "the example throw can't be beaten by any cards elsewhere")

        // The top-card example is a sure winner even when you have seen nothing else.
        let top = try example(.topCard)
        let topComponents = Combos.decompose(top.cards, trump: top.trump)
        XCTAssertEqual(topComponents.count, 1)
        XCTAssertFalse(top.trump.isTrump(top.cards[0]))
        XCTAssertTrue(MoveDetector.isSureWinner(try XCTUnwrap(topComponents.first), seen: [], trump: top.trump))

        let feed = try example(.feedPartner)
        XCTAssertGreaterThan(feed.cards.points, 0)
        XCTAssertTrue(try example(.bigJoker).cards.contains { $0.face == .bigJoker })
        XCTAssertGreaterThanOrEqual(try example(.bigTrick).cards.points, 30)
        XCTAssertGreaterThan(try example(.kittyRaid).cards.points, 0)
        let override = try example(.overrideDeclaration)
        XCTAssertTrue(Combos.isPair(override.cards))
        XCTAssertEqual(override.cards.first?.rank, override.trump.rank)
        let declare = try example(.declareTrump)
        XCTAssertEqual(declare.cards.first?.rank, declare.trump.rank)
        XCTAssertEqual(declare.cards.first?.suit, declare.trump.suit)
    }

    // MARK: Progress

    func testEmptyProgress() {
        let progress = AchievementProgress()
        XCTAssertEqual(progress.counts, [:])
        XCTAssertEqual(progress.earnedAt, [:])
        XCTAssertEqual(progress.overallFraction, 0)
        for definition in Achievements.all {
            XCTAssertEqual(progress.count(for: definition), 0)
            XCTAssertEqual(progress.tier(for: definition), AchievementTier.none)
            XCTAssertEqual(progress.nextThreshold(for: definition), definition.thresholds.first)
            XCTAssertEqual(progress.fractionToNextTier(for: definition), 0)
        }
    }

    func testRecordingMovesClimbsTiers() throws {
        var progress = AchievementProgress()
        let ruff = try definition("move.ruff")
        let first = progress.record([event(.ruff)], now: now)
        XCTAssertEqual(first, [TierUp(achievement: ruff, tier: .bronze)])
        XCTAssertEqual(progress.tier(for: ruff), .bronze)
        XCTAssertEqual(progress.nextThreshold(for: ruff), 5)
        XCTAssertEqual(progress.fractionToNextTier(for: ruff), 0)
        XCTAssertEqual(progress.earnedDate(for: ruff, tier: .bronze), now)
        XCTAssertEqual(progress.earnedAt["move.ruff#1"], now)

        XCTAssertEqual(progress.record([event(.ruff), event(.ruff)], now: now.addingTimeInterval(60)), [])
        XCTAssertEqual(progress.count(for: ruff), 3)
        XCTAssertEqual(progress.fractionToNextTier(for: ruff), 0.5, accuracy: 1e-9)

        let later = now.addingTimeInterval(3_600)
        XCTAssertEqual(progress.record([event(.ruff), event(.ruff)], now: later), [TierUp(achievement: ruff, tier: .silver)])
        XCTAssertEqual(progress.earnedDate(for: ruff, tier: .silver), later)
        XCTAssertEqual(progress.earnedDate(for: ruff, tier: .bronze), now, "first reach keeps its date")

        let many = Array(repeating: event(.ruff), count: 30)
        XCTAssertEqual(progress.record(many, now: later), [TierUp(achievement: ruff, tier: .gold)])
        XCTAssertEqual(progress.tier(for: ruff), .gold)
        XCTAssertNil(progress.nextThreshold(for: ruff))
        XCTAssertEqual(progress.fractionToNextTier(for: ruff), 1)
        XCTAssertEqual(progress.record([event(.ruff)], now: later), [], "nothing past gold")
        XCTAssertEqual(progress.count(for: ruff), 36)
    }

    /// The bar beside "1 / 5" shows 1 of 5, not progress since the last tier (an empty bar at "1 / 5").
    func testBarMatchesTheCountOverTheNextThreshold() throws {
        var progress = AchievementProgress()
        let ruff = try definition("move.ruff")
        XCTAssertEqual(progress.fractionOfNextThreshold(for: ruff), 0)
        _ = progress.record([event(.ruff)], now: now)
        XCTAssertEqual(progress.count(for: ruff), 1)
        XCTAssertEqual(progress.nextThreshold(for: ruff), 5)
        XCTAssertEqual(progress.fractionOfNextThreshold(for: ruff), 0.2, accuracy: 1e-9, "1 / 5")
        _ = progress.record(Array(repeating: event(.ruff), count: 5), now: now)
        XCTAssertEqual(progress.nextThreshold(for: ruff), 25)
        XCTAssertEqual(progress.fractionOfNextThreshold(for: ruff), 6.0 / 25.0, accuracy: 1e-9, "6 / 25")
        _ = progress.record(Array(repeating: event(.ruff), count: 30), now: now)
        XCTAssertNil(progress.nextThreshold(for: ruff))
        XCTAssertEqual(progress.fractionOfNextThreshold(for: ruff), 1, "gold")
    }

    /// Short games (to 5 or 10) count as won games too, so the badge can't say only A wins.
    func testGameWinnerTextFitsShortGames() throws {
        let wins = try definition("journey.gamesWon")
        for text in [wins.goal, wins.lesson] {
            XCTAssertFalse(text.contains("at level A"), text)
            XCTAssertFalse(text.hasPrefix("Reaching A is not enough"), text)
        }
        XCTAssertTrue(wins.lesson.contains("5 or 10"), wins.lesson)
    }

    func testOneRecordCanReachSeveralTiersInOrder() throws {
        var progress = AchievementProgress()
        let events = Array(repeating: event(.bigTrick), count: 6) + [event(.ruff), event(.cleanThrow), event(.cleanThrow), event(.cleanThrow)]
        let ups = progress.record(events, now: now)
        let expected: [(String, AchievementTier)] = [
            ("move.ruff", .bronze), ("move.cleanThrow", .bronze), ("move.cleanThrow", .silver),
            ("move.bigTrick", .bronze), ("move.bigTrick", .silver),
        ]
        XCTAssertEqual(ups.map(\.achievement.id), expected.map(\.0), "Achievements.all order, lowest tier first")
        XCTAssertEqual(ups.map(\.tier), expected.map(\.1))
        XCTAssertEqual(progress.record([], now: now), [])
    }

    func testGameProgress() throws {
        var progress = AchievementProgress()
        let level = try definition("journey.levelReached")
        let wins = try definition("journey.gamesWon")
        XCTAssertEqual(progress.recordGameProgress(teamLevel: .four, wonGame: false, now: now), [])
        XCTAssertEqual(progress.count(for: level), 2)
        XCTAssertEqual(progress.recordGameProgress(teamLevel: .five, wonGame: false, now: now), [TierUp(achievement: level, tier: .bronze)])
        // A new game starts back at 2: the best level reached stays.
        XCTAssertEqual(progress.recordGameProgress(teamLevel: .two, wonGame: false, now: now), [])
        XCTAssertEqual(progress.count(for: level), 3)
        let ups = progress.recordGameProgress(teamLevel: .ace, wonGame: true, now: now)
        XCTAssertEqual(ups, [TierUp(achievement: level, tier: .silver), TierUp(achievement: level, tier: .gold),
                             TierUp(achievement: wins, tier: .bronze)])
        XCTAssertEqual(progress.count(for: level), 12)
        XCTAssertEqual(progress.count(for: wins), 1)
        _ = progress.recordGameProgress(teamLevel: .ace, wonGame: true, now: now)
        XCTAssertEqual(progress.count(for: wins), 2)
    }

    /// The app reports a won game to achievements first, then the learning store counts it and syncs:
    /// the win must count once, and older wins from the learning store still count.
    func testAWinReportedThenSyncedCountsOnce() throws {
        let wins = try definition("journey.gamesWon")
        var learner = LearnerProgress()
        learner.gamesWon = 2
        var progress = AchievementProgress()
        _ = progress.syncLearning(learner, now: now)
        XCTAssertEqual(progress.count(for: wins), 2, "wins from before achievements existed")
        for game in 1...3 {
            _ = progress.recordGameProgress(teamLevel: .ace, wonGame: true, now: now)
            learner.gamesWon += 1
            _ = progress.syncLearning(learner, now: now)
            XCTAssertEqual(progress.count(for: wins), 2 + game)
        }
        XCTAssertEqual(progress.tier(for: wins), .silver)
    }

    func testSyncingLearningProgress() throws {
        var learner = LearnerProgress()
        for lesson in Curriculum.lessons.prefix(4) { learner.completeLesson(lesson, now: now) }
        learner.studyDays = ["2026-01-30", "2026-01-31", "2026-02-01", "2026-02-02", "2026-03-10", "2026-03-11"]
        // Three items with long intervals and perfect answers are mastered; one weak item is not.
        let mastered = ["skill.pointValue", "skill.countPoints", "skill.isTrump"]
        for id in mastered + ["skill.trumpOrder"] {
            learner.schedules[id] = ItemSchedule(itemID: id, due: now, intervalDays: id == "skill.trumpOrder" ? 0 : 30, ease: 2.5,
                                                 reps: 5, lapses: 0, learningStep: nil, lastReviewed: now)
            learner.stats[id] = SkillStats(attempts: 20, correct: id == "skill.trumpOrder" ? 5 : 20,
                                           recent: Array(repeating: id != "skill.trumpOrder", count: 10))
        }
        learner.stats["fact.teams"] = SkillStats(attempts: 7, correct: 7, recent: [])
        learner.gamesWon = 2

        var progress = AchievementProgress()
        let ups = progress.syncLearning(learner, now: now)
        XCTAssertEqual(progress.count(for: try definition("journey.lessonsCompleted")), 4)
        XCTAssertEqual(progress.count(for: try definition("journey.studyStreak")), 4)
        XCTAssertEqual(progress.count(for: try definition("journey.skillsMastered")), 3)
        XCTAssertEqual(progress.count(for: try definition("journey.questionsAnswered")), 87)
        XCTAssertEqual(progress.count(for: try definition("journey.gamesWon")), 2)
        XCTAssertEqual(ups.map(\.achievement.id), ["journey.gamesWon", "journey.lessonsCompleted", "journey.studyStreak",
                                                   "journey.skillsMastered", "journey.questionsAnswered"])
        XCTAssertEqual(ups.map(\.tier), [.bronze, .bronze, .bronze, .bronze, .bronze])

        // Counts never go down, even if the learning data shrinks (a reset or an older backup).
        let before = progress
        XCTAssertEqual(progress.syncLearning(LearnerProgress(), now: now), [])
        XCTAssertEqual(progress, before)
        // Syncing the same data again reports nothing new.
        XCTAssertEqual(progress.syncLearning(learner, now: now), [])
    }

    func testLongestStreak() {
        XCTAssertEqual(Achievements.longestStreak([]), 0)
        XCTAssertEqual(Achievements.longestStreak(["2026-05-01"]), 1)
        XCTAssertEqual(Achievements.longestStreak(["2026-05-03", "2026-05-01", "2026-05-02", "2026-05-02"]), 3, "unordered, duplicates")
        XCTAssertEqual(Achievements.longestStreak(["2024-02-28", "2024-02-29", "2024-03-01", "2025-12-31", "2026-01-01"]), 3,
                       "leap day and year boundary")
        XCTAssertEqual(Achievements.longestStreak(["2026-05-01", "nonsense", "2026-02-31", "2026-05-02"]), 2, "bad keys are ignored")
    }

    func testOverallFraction() {
        var progress = AchievementProgress()
        let total = Double(Achievements.all.count * 3)
        _ = progress.record([event(.ruff)], now: now)
        XCTAssertEqual(progress.overallFraction, 1 / total, accuracy: 1e-9)
        var events: [MoveEvent] = []
        for kind in MoveKind.allCases { events += Array(repeating: event(kind), count: 25) }
        _ = progress.record(events, now: now)
        _ = progress.recordGameProgress(teamLevel: .ace, wonGame: true, now: now)
        for _ in 0..<9 { _ = progress.recordGameProgress(teamLevel: .ace, wonGame: true, now: now) }
        var learner = LearnerProgress()
        for lesson in Curriculum.lessons { learner.completeLesson(lesson, now: now) }
        learner.studyDays = (1...30).map { day in day < 10 ? "2026-04-0\(day)" : "2026-04-\(day)" }
        for id in learner.unlockedItemIDs.prefix(15) {
            learner.schedules[id]?.intervalDays = 40
            learner.schedules[id]?.learningStep = nil
            learner.stats[id] = SkillStats(attempts: 70, correct: 70, recent: Array(repeating: true, count: 10))
        }
        _ = progress.syncLearning(learner, now: now)
        for definition in Achievements.all {
            XCTAssertEqual(progress.tier(for: definition), .gold, definition.id)
        }
        XCTAssertEqual(progress.overallFraction, 1)
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        var progress = AchievementProgress()
        _ = progress.record([event(.ruff), event(.tractor), event(.tractor)], now: now)
        _ = progress.recordGameProgress(teamLevel: .seven, wonGame: true, now: now)
        let data = try JSONEncoder().encode(progress)
        let decoded = try JSONDecoder().decode(AchievementProgress.self, from: data)
        XCTAssertEqual(decoded, progress)
    }

    func testDecodingOlderOrDamagedJSON() throws {
        let decoder = JSONDecoder()
        let empty = try decoder.decode(AchievementProgress.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, AchievementProgress())

        let countsOnly = try decoder.decode(AchievementProgress.self, from: Data(#"{"counts": {"move.ruff": 3}}"#.utf8))
        XCTAssertEqual(countsOnly.count(for: try definition("move.ruff")), 3)
        XCTAssertEqual(countsOnly.tier(for: try definition("move.ruff")), .bronze)
        XCTAssertEqual(countsOnly.earnedAt, [:])

        let damaged = #"{"counts": {"move.ruff": "lots", "move.tractor": 2, "move.topCard": -4, "move.unknown": 9}, "earnedAt": 17}"#
        let fixed = try decoder.decode(AchievementProgress.self, from: Data(damaged.utf8))
        XCTAssertEqual(fixed.count(for: try definition("move.ruff")), 0)
        XCTAssertEqual(fixed.count(for: try definition("move.tractor")), 2)
        XCTAssertEqual(fixed.count(for: try definition("move.topCard")), 0, "negative counts become 0")
        XCTAssertEqual(fixed.earnedAt, [:])

        let dates = #"{"counts": {}, "earnedAt": {"move.ruff#1": 100, "move.tractor#1": "soon"}}"#
        let withDates = try decoder.decode(AchievementProgress.self, from: Data(dates.utf8))
        XCTAssertEqual(withDates.earnedAt, ["move.ruff#1": Date(timeIntervalSinceReferenceDate: 100)])

        // Progress keeps counting from decoded values.
        var resumed = countsOnly
        XCTAssertEqual(resumed.record([event(.ruff), event(.ruff)], now: now).map(\.tier), [.silver])
    }

    /// Dates must survive whatever date format the app's coder uses (ISO 8601 text, seconds, a property list),
    /// not only the default one.
    func testEarnedDatesSurviveOtherDateFormats() throws {
        var progress = AchievementProgress()
        _ = progress.record([event(.ruff)], now: now)
        _ = progress.recordGameProgress(teamLevel: .six, wonGame: true, now: now.addingTimeInterval(86_400))
        XCTAssertEqual(progress.earnedAt.count, 3)

        let strategies: [(JSONEncoder.DateEncodingStrategy, JSONDecoder.DateDecodingStrategy, String)] = [
            (.iso8601, .iso8601, "ISO 8601"),
            (.secondsSince1970, .secondsSince1970, "seconds since 1970"),
            (.millisecondsSince1970, .millisecondsSince1970, "milliseconds since 1970"),
        ]
        for (encoding, decoding, label) in strategies {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = encoding
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = decoding
            let decoded = try decoder.decode(AchievementProgress.self, from: try encoder.encode(progress))
            XCTAssertEqual(decoded, progress, label)
        }
        let plist = try PropertyListEncoder().encode(progress)
        XCTAssertEqual(try PropertyListDecoder().decode(AchievementProgress.self, from: plist), progress, "property list")

        // A bad date among good ones is still dropped on its own, in any format.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let mixed = #"{"counts": {"move.ruff": 1}, "earnedAt": {"move.ruff#1": "2027-01-15T08:00:00Z", "move.ruff#2": "later"}}"#
        let lenient = try decoder.decode(AchievementProgress.self, from: Data(mixed.utf8))
        XCTAssertEqual(lenient.earnedAt, ["move.ruff#1": Date(timeIntervalSince1970: 1_800_000_000)])
    }

    func testMoveEventCodable() throws {
        let event = MoveEvent(kind: .kittyRaid, detail: "Kitty raid!", points: 40)
        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(MoveEvent.self, from: data), event)
    }

    func testTierTitlesAndOrder() {
        XCTAssertEqual(AchievementTier.allCases.map(\.title), ["Not yet", "Bronze", "Silver", "Gold"])
        XCTAssertLessThan(AchievementTier.bronze, AchievementTier.gold)
        XCTAssertEqual(AchievementCategory.moves.title, "Moves")
        XCTAssertEqual(AchievementCategory.journey.title, "Journey")
    }

    func testMovesFromRealRoundsFeedAchievements() throws {
        var progress = AchievementProgress()
        var total = 0
        for seed in UInt64(0)..<UInt64(20) {
            var rng = SeededGenerator(seed: seed &+ 900)
            var round = Round(trumpRank: .two, dealer: Int(seed % 4), rng: &rng)
            try EngineTestSupport.prepare(&round, rng: &rng)
            try EngineTestSupport.playOut(&round, rng: &rng)
            var events: [MoveEvent] = []
            for index in round.tricks.indices { events += MoveDetector.moves(inTrick: index, of: round) }
            events += MoveDetector.moves(inFinishedRound: round)
            total += events.count
            let before = progress.counts.values.reduce(0, +)
            let ups = progress.record(events, now: now)
            XCTAssertEqual(progress.counts.values.reduce(0, +), before + events.count)
            for up in ups { XCTAssertEqual(progress.tier(for: up.achievement) >= up.tier, true) }
        }
        XCTAssertGreaterThan(total, 20)
    }
}
