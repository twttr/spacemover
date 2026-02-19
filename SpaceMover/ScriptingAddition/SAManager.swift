import Cocoa
import os.log

private let logger = Logger(subsystem: "com.twttr.SpaceMover", category: "SAManager")

@MainActor
final class SAManager {
    static let shared = SAManager()

    private let loaderPath: String = {
        Bundle.main.bundlePath + "/Contents/MacOS/SpaceMoverLoader"
    }()

    private let payloadPath: String = {
        Bundle.main.bundlePath + "/Contents/MacOS/SpacePayload.dylib"
    }()

    private init() {}

    enum MoveError: Error {
        case payloadInjectionFailed(String)
        case commandFailed
        case sudoersNotConfigured
    }

    var isSudoersConfigured: Bool {
        FileManager.default.fileExists(atPath: "/private/etc/sudoers.d/spacemover")
    }

    func configureSudoers() async -> (success: Bool, error: String) {
        let user = NSUserName()
        let sudoersLine = "\(user) ALL=(root) NOPASSWD: \(loaderPath) *"

        let source = """
        do shell script "echo '\(sudoersLine)' > /private/etc/sudoers.d/spacemover && chmod 0440 /private/etc/sudoers.d/spacemover" with administrator privileges
        """

        logger.info("Configuring sudoers for \(self.loaderPath)")

        let result = await runProcess(
            executable: "/usr/bin/osascript",
            arguments: ["-e", source]
        )

        if result.exitCode != 0 {
            let msg = combinedOutput(result.stdout, result.stderr)
            logger.error("Sudoers config failed (exit \(result.exitCode)): \(msg)")
            return (false, msg.isEmpty ? "User cancelled authentication" : msg)
        }

        logger.info("Sudoers configured successfully")
        return (true, "")
    }

    func ensurePayloadLoaded() async throws {
        if isPayloadRunning() { return }
        try await injectPayload()
    }

    private nonisolated func isPayloadRunning() -> Bool {
        let pingData = buildCommand(opcode: .ping)
        return SAClient.send(pingData)
    }

    private var sudoersReconfigureAttempted = false

    private func injectPayload() async throws {
        if !isSudoersConfigured {
            logger.warning("Sudoers file not found")
            throw MoveError.sudoersNotConfigured
        }

        logger.info("Running: sudo \(self.loaderPath) \(self.payloadPath)")

        let result = await runProcess(
            executable: "/usr/bin/sudo",
            arguments: [loaderPath, payloadPath]
        )

        if result.exitCode != 0 {
            let combined = combinedOutput(result.stdout, result.stderr)
            logger.error("Loader failed (exit \(result.exitCode)):\nstdout: \(result.stdout)\nstderr: \(result.stderr)")

            let isSudoRejection = result.exitCode == 1
            if isSudoRejection && !sudoersReconfigureAttempted {
                logger.warning("Sudo rejected command (exit \(result.exitCode)), likely stale hash — reconfigure needed")
                sudoersReconfigureAttempted = true
                throw MoveError.sudoersNotConfigured
            }

            throw MoveError.payloadInjectionFailed(combined.isEmpty ? "exit code \(result.exitCode)" : combined)
        }

        sudoersReconfigureAttempted = false

        try await Task.sleep(nanoseconds: 500_000_000)

        if !isPayloadRunning() {
            logger.error("Payload not responding after injection")
            throw MoveError.payloadInjectionFailed("Payload socket not responding after injection")
        }

        logger.info("Payload injected successfully")
    }

    func moveSpace(
        _ spaceID: UInt64,
        toDisplay targetDisplayUUID: String,
        atIndex index: Int,
        sourceDisplayUUID: String,
        fallbackSpaceID: UInt64
    ) async throws {
        guard let connFn = SkyLightBridge.mainConnectionID,
              let moveFn = SkyLightBridge.moveSpaceToDisplayIndex else {
            logger.error("SkyLight move functions not available")
            throw MoveError.commandFailed
        }

        let conn = connFn()
        let targetCF = targetDisplayUUID as CFString

        logger.info("conn=\(conn) space=\(spaceID) src=\(sourceDisplayUUID) dst=\(targetDisplayUUID) idx=\(index) fallback=\(fallbackSpaceID)")

        moveFn(conn, spaceID, targetCF, UInt32(index))
        logger.info("Space moved, restarting Dock to apply visual changes")

        let dockApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.apple.dock"
        }
        for dock in dockApps {
            dock.terminate()
        }

        logger.info("Move completed")
    }

    private nonisolated func combinedOutput(_ stdout: String, _ stderr: String) -> String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private nonisolated func runProcess(executable: String, arguments: [String]) async -> (exitCode: Int32, stdout: String, stderr: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let stdoutStr = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderrStr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: (process.terminationStatus, stdoutStr, stderrStr))
            }
        }
    }
}
