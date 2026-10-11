// ShengjiVectors: writes JSON test vectors from the Swift engine and bots so the TypeScript engine
// and bots in server/ can prove they behave identically (DESIGN.md, Online multiplayer).
//
//   cd ShengjiCore && swift run ShengjiVectors ../server/test/vectors
//
// Output is deterministic: fixed seeds, a private RNG on top of SeededGenerator, and a JSON
// writer with ordered keys. CI regenerates the files and fails if they differ from the committed
// ones. The file formats are described in server/README.md.

import Foundation
import ShengjiCore

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: ShengjiVectors <output directory>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("cannot create \(directory.path): \(error)\n".utf8))
    exit(1)
}

let outputs: [(name: String, make: () -> [(String, JSON)])] = [
    ("combos.json", { CombosVectors.make() }),
    ("rules.json", { RulesVectors.make(positions: 1200, bigPositions: 200) }),
    ("rounds.json", { RoundVectors.make(count: 200, bigCount: 40, oddCount: 45) }),
    ("games.json", { GameVectors.make() }),
    ("edges.json", { EdgeVectors.make(count: 200, bigCount: 100) }),
    ("views.json", { ViewVectors.make(games: 20, bigGames: 10, oddGames: 12) }),
    ("bots.json", { BotVectors.make(online: 240, offline: 60, deals: 400, ruffRounds: 80,
                                    bigOnline: 40, bigOffline: 20, bigDeals: 80,
                                    oddOnline: 45, oddOffline: 15, oddDeals: 60) }),
]

var total = 0
for output in outputs {
    let text = JSON.document(output.make())
    let url = directory.appendingPathComponent(output.name)
    do {
        try Data(text.utf8).write(to: url)
    } catch {
        FileHandle.standardError.write(Data("cannot write \(url.path): \(error)\n".utf8))
        exit(1)
    }
    total += text.utf8.count
    print("\(output.name): \(text.utf8.count) bytes")
}
print("total: \(total) bytes in \(directory.path)")
