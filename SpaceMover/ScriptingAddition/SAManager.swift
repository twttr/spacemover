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
        guard loaderPath.hasPrefix(Bundle.main.bundlePath),
              payloadPath.hasPrefix(Bundle.main.bundlePath) else {
            return (false, "Invalid loader or payload path")
        }

        let escapedUser = NSUserName().replacingOccurrences(of: "'", with: "'\\''")
        let sudoersLine = "\(escapedUser) ALL=(root) NOPASSWD: \(loaderPath) \(payloadPath)"
        let escapedSudoersLine = sudoersLine.replacingOccurrences(of: "'", with: "'\\''")

        let source = """
        do shell script "echo '\(escapedSudoersLine)' > /private/etc/sudoers.d/spacemover && chmod 0440 /private/etc/sudoers.d/spacemover" with administrator privileges
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

        try await waitForPayload()

        logger.info("Payload injected successfully")
    }

    private func waitForPayload() async throws {
        var delayNs: UInt64 = 100_000_000
        let maxAttempts = 6
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: delayNs)
            if isPayloadRunning() { return }
            delayNs = min(delayNs * 2, 1_000_000_000)
        }
        logger.error("Payload not responding after waiting")
        throw MoveError.payloadInjectionFailed("Payload socket not responding after injection")
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

        if attemptVisualRefresh(conn: conn, spaceID: spaceID, targetDisplayUUID: targetDisplayUUID, fallbackSpaceID: fallbackSpaceID) {
            logger.info("Space moved with visual refresh")
        } else {
            logger.info("Visual refresh unavailable, restarting Dock")
            restartDock()
            try? await waitForPayload()
        }
    }

    private nonisolated func attemptVisualRefresh(conn: Int32, spaceID: UInt64, targetDisplayUUID: String, fallbackSpaceID: UInt64) -> Bool {
        guard let showFn = SkyLightBridge.showSpaces,
              let hideFn = SkyLightBridge.hideSpaces,
              let setCurrentFn = SkyLightBridge.setCurrentSpace else {
            return false
        }
        let targetCF = targetDisplayUUID as CFString
        let spaceArray = [NSNumber(value: spaceID)] as CFArray
        hideFn(conn, spaceArray)
        showFn(conn, spaceArray)
        setCurrentFn(conn, targetCF, spaceID)
        return true
    }

    private func restartDock() {
        let dockApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.apple.dock"
        }
        for dock in dockApps {
            let terminated = dock.terminate()
            if !terminated {
                logger.warning("dock.terminate() returned false")
            }
        }
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
