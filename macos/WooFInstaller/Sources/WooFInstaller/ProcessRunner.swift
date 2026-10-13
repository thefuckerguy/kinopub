import Foundation

struct CommandResult {
    let status: Int32
    let data: Data

    var output: String {
        String(decoding: data, as: UTF8.self)
    }
}

enum CommandFailure: LocalizedError {
    case failed(executable: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case let .failed(executable, status, output):
            let usefulOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return usefulOutput.isEmpty
                ? "Команда \(executable) завершилась с кодом \(status)."
                : usefulOutput
        }
    }
}

enum ProcessRunner {
    static func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil
    ) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let logURL = fileManager.temporaryDirectory
                .appendingPathComponent("woof-installer-command-\(UUID().uuidString).log")
            fileManager.createFile(atPath: logURL.path, contents: nil)
            defer { try? fileManager.removeItem(at: logURL) }

            let logHandle = try FileHandle(forWritingTo: logURL)
            defer { try? logHandle.close() }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.standardOutput = logHandle
            process.standardError = logHandle
            try process.run()
            process.waitUntilExit()
            try logHandle.synchronize()

            return CommandResult(
                status: process.terminationStatus,
                data: (try? Data(contentsOf: logURL)) ?? Data()
            )
        }.value
    }

    static func checked(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil
    ) async throws -> CommandResult {
        let result = try await run(executable, arguments, currentDirectory: currentDirectory)
        guard result.status == 0 else {
            throw CommandFailure.failed(
                executable: URL(fileURLWithPath: executable).lastPathComponent,
                status: result.status,
                output: result.output
            )
        }
        return result
    }
}
