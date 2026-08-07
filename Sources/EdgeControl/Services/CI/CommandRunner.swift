import Foundation

public protocol CommandRunner: Sendable {
    /// Runs `executable` with `arguments`, optionally writing `stdin`.
    /// Returns trimmed stdout. Throws when the binary is missing or exits
    /// non-zero.
    func run(_ executable: String, _ arguments: [String], stdin: String?) throws -> String
}

/// Spawns real processes.
///
/// Only usable from the main app — the widget extension is sandboxed and must
/// never call this.
public struct ProcessCommandRunner: CommandRunner {
    /// Searched in order. A GUI app launched from Finder does not inherit the
    /// user's shell PATH, so the common install locations are listed
    /// explicitly.
    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin",
    ]

    public init() {}

    public static func locate(_ executable: String) -> String? {
        searchPaths
            .map { $0 + "/" + executable }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func run(
        _ executable: String,
        _ arguments: [String],
        stdin: String?
    ) throws -> String {
        guard let path = Self.locate(executable) else {
            throw CIError.decoding("\(executable) not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        if let stdin {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(stdin.utf8))
            input.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CIError.decoding("\(executable) exited \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
