import Cocoa

struct SpaceMoveIntent {
    let spaceID: UInt64
    let targetDisplayUUID: String
    let targetIndex: Int
    let sourceDisplayUUID: String
    let fallbackSpaceID: UInt64
}

final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!

    override init() {
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "square.3.layers.3d.top.filled", accessibilityDescription: "SpaceMover") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "SM"
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    func handleHotkeyAction(_ action: HotkeyAction) {
        let displaySpaces = SpaceEnumerator.enumerateDisplaySpaces()
        guard displaySpaces.count >= 2 else { return }

        guard let sourceIndex = displaySpaces.firstIndex(where: { ds in
            ds.spaces.contains { $0.isCurrentSpace }
        }) else { return }

        let sourceDS = displaySpaces[sourceIndex]
        guard let currentSpace = sourceDS.spaces.first(where: { $0.isCurrentSpace }) else { return }

        let targetIndex: Int
        switch action {
        case .moveSpaceLeft:
            targetIndex = sourceIndex == 0 ? displaySpaces.count - 1 : sourceIndex - 1
        case .moveSpaceRight:
            targetIndex = sourceIndex == displaySpaces.count - 1 ? 0 : sourceIndex + 1
        }

        let intent = SpaceMoveIntent(
            spaceID: currentSpace.spaceID,
            targetDisplayUUID: displaySpaces[targetIndex].display.uuid,
            targetIndex: displaySpaces[targetIndex].spaces.count,
            sourceDisplayUUID: sourceDS.display.uuid,
            fallbackSpaceID: sourceDS.spaces.first(where: { $0.spaceID != currentSpace.spaceID })?.spaceID ?? currentSpace.spaceID
        )

        Task { await performMove(intent) }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let displaySpaces = SpaceEnumerator.enumerateDisplaySpaces()

        if displaySpaces.isEmpty {
            let message = SkyLightBridge.isAvailable ? "No displays found" : "SkyLight API unavailable"
            menu.addItem(NSMenuItem(title: message, action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }

        for (displayIndex, ds) in displaySpaces.enumerated() {
            let displayItem = NSMenuItem(title: ds.display.name, action: nil, keyEquivalent: "")
            displayItem.isEnabled = false
            menu.addItem(displayItem)

            for space in ds.spaces {
                let label: String
                if space.spaceType == .fullscreen {
                    let appName = space.appNames.first ?? "Unknown"
                    label = "  \(appName) (fullscreen)\(space.isCurrentSpace ? " ★" : "")"
                } else {
                    let suffix = space.appNames.isEmpty ? "" : " — \(space.appNames.joined(separator: ", "))"
                    label = "  Desktop \(space.managedSpaceIndex + 1)\(suffix)\(space.isCurrentSpace ? " ★" : "")"
                }
                let spaceItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")

                if displaySpaces.count >= 2 {
                    let fallback = ds.spaces.first(where: { $0.spaceID != space.spaceID })?.spaceID ?? space.spaceID
                    let moveSubmenu = NSMenu()
                    for (otherIndex, otherDS) in displaySpaces.enumerated() where otherIndex != displayIndex {
                        let moveItem = NSMenuItem(
                            title: "Move to \(otherDS.display.name)",
                            action: #selector(moveSpaceAction(_:)),
                            keyEquivalent: ""
                        )
                        moveItem.target = self
                        moveItem.representedObject = SpaceMoveIntent(
                            spaceID: space.spaceID,
                            targetDisplayUUID: otherDS.display.uuid,
                            targetIndex: otherDS.spaces.count,
                            sourceDisplayUUID: ds.display.uuid,
                            fallbackSpaceID: fallback
                        )
                        moveSubmenu.addItem(moveItem)
                    }
                    spaceItem.submenu = moveSubmenu
                }

                menu.addItem(spaceItem)
            }

            menu.addItem(.separator())
        }

        let quitItem = NSMenuItem(title: "Quit SpaceMover", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func performMove(_ intent: SpaceMoveIntent) async {
        do {
            try await SAManager.shared.moveSpace(
                intent.spaceID,
                toDisplay: intent.targetDisplayUUID,
                atIndex: intent.targetIndex,
                sourceDisplayUUID: intent.sourceDisplayUUID,
                fallbackSpaceID: intent.fallbackSpaceID
            )
        } catch SAManager.MoveError.commandFailed {
            await showError("Move command failed", detail: "SkyLight API call failed. Check Console.app for details.")
        } catch {
            await showError("Unexpected error", detail: error.localizedDescription)
        }
    }

    private func showError(_ message: String, detail: String) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func moveSpaceAction(_ sender: NSMenuItem) {
        guard let intent = sender.representedObject as? SpaceMoveIntent else { return }
        Task { await performMove(intent) }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
