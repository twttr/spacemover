import Foundation
import AppKit

enum SpaceEnumerator {
    struct DisplaySpaces {
        let display: DisplayInfo
        let spaces: [SpaceInfo]
    }

    static func enumerateDisplaySpaces() -> [DisplaySpaces] {
        guard let connFn = SkyLightBridge.mainConnectionID,
              let enumFn = SkyLightBridge.copyManagedDisplaySpaces
        else { return [] }

        let conn = connFn()
        guard let rawArray = enumFn(conn) else { return [] }
        let displays = rawArray as NSArray

        return displays.compactMap { element -> DisplaySpaces? in
            guard let dict = element as? NSDictionary,
                  let uuid = dict["Display Identifier"] as? String,
                  let spacesArray = dict["Spaces"] as? NSArray,
                  let currentDict = dict["Current Space"] as? NSDictionary,
                  let currentSpaceID = currentDict["ManagedSpaceID"] as? UInt64
            else { return nil }

            let displayName = resolveDisplayName(for: uuid)
            let display = DisplayInfo(uuid: uuid, name: displayName)

            var userSpaceIndex = 0
            let spaces: [SpaceInfo] = spacesArray.compactMap { spaceElem in
                guard let spaceDict = spaceElem as? NSDictionary,
                      let spaceID = spaceDict["ManagedSpaceID"] as? UInt64,
                      let rawType = spaceDict["type"] as? Int,
                      let spaceType = SpaceType(rawValue: rawType),
                      spaceType == .desktop || spaceType == .fullscreen
                else { return nil }

                var appNames: [String] = []

                if spaceType == .fullscreen {
                    if let pid = spaceDict["pid"] as? pid_t {
                        if let app = NSRunningApplication(processIdentifier: pid) {
                            appNames = [app.localizedName ?? "Unknown"]
                        }
                    }
                } else {
                    appNames = resolveAppNames(forSpace: spaceID, connection: conn)
                }

                let index = spaceType == .desktop ? userSpaceIndex : -1
                let info = SpaceInfo(
                    spaceID: spaceID,
                    displayUUID: uuid,
                    isCurrentSpace: spaceID == currentSpaceID,
                    managedSpaceIndex: index,
                    spaceType: spaceType,
                    appNames: appNames
                )
                if spaceType == .desktop { userSpaceIndex += 1 }
                return info
            }
            return DisplaySpaces(display: display, spaces: spaces)
        }
    }

    private static func resolveAppNames(forSpace spaceID: UInt64, connection conn: Int32) -> [String] {
        guard let windowsFn = SkyLightBridge.copyWindowsWithOptionsAndTags,
              let ownerFn = SkyLightBridge.getWindowOwner,
              let pidFn = SkyLightBridge.connectionGetPID
        else { return [] }

        let spaceNum = NSNumber(value: spaceID)
        let spacesArray = [spaceNum] as CFArray
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0

        guard let windowIDs = windowsFn(conn, 0, spacesArray, 0x2, &setTags, &clearTags) as? [NSNumber] else {
            return []
        }

        var seenPIDs = Set<pid_t>()
        var names: [String] = []

        for widNum in windowIDs {
            var ownerCid: Int32 = 0
            guard ownerFn(conn, widNum.uint32Value, &ownerCid) == .success else { continue }
            var pid: pid_t = 0
            guard pidFn(ownerCid, &pid) == .success else { continue }
            guard !seenPIDs.contains(pid) else { continue }
            seenPIDs.insert(pid)

            if let app = NSRunningApplication(processIdentifier: pid),
               let name = app.localizedName,
               app.activationPolicy == .regular {
                names.append(name)
            }
        }
        return names
    }

    private static func resolveDisplayName(for uuid: String) -> String {
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            let cfUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber)
            guard let cfUUID else { continue }
            let screenUUID = CFUUIDCreateString(kCFAllocatorDefault, cfUUID.takeRetainedValue()) as String? ?? ""
            if screenUUID == uuid {
                return screen.localizedName
            }
        }
        return String(uuid.prefix(8))
    }
}
