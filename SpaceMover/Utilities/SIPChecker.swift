import Foundation
import os.log

private let logger = Logger(subsystem: "com.twttr.SpaceMover", category: "SIPChecker")

enum SIPChecker {
    static func isSIPPartiallyDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        process.arguments = ["status"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Failed to run csrutil: \(error.localizedDescription)")
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("disabled") || output.contains("Custom Configuration")
    }
}
