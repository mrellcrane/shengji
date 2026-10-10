// ShengjiVectors: writes JSON test vectors from the Swift engine so the TypeScript engine in
// server/ can prove it behaves identically (DESIGN.md, Online multiplayer).
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
    ("rules.json", { RulesVectors.make(positions: 1200) }),
    ("rounds.json", { RoundVectors.make(count: 200) }),
    ("games.json", { GameVectors.make() }),
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
