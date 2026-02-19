import Testing
import Foundation
@testable import SpaceMover

struct SAProtocolTests {
    @Test func commandSizeIs152Bytes() {
        let data = buildCommand(opcode: .ping)
        #expect(data.count == 152)
    }

    @Test func commandFieldLayout() {
        let data = buildCommand(
            opcode: .moveSpaceToDisplay,
            spaceID: 42,
            displayUUID: "ABC-123",
            targetIndex: 5,
            afterSpaceID: 7
        )

        let version = readUInt32(from: data, at: 0)
        #expect(version == 1)

        let opcode = readUInt32(from: data, at: 4)
        #expect(opcode == 1)

        let spaceID = readUInt64(from: data, at: 8)
        #expect(spaceID == 42)

        let targetIndex = readUInt32(from: data, at: 16)
        #expect(targetIndex == 5)

        let afterSpaceID = readUInt32(from: data, at: 20)
        #expect(afterSpaceID == 7)

        let uuidString = readCString(from: data, at: 24, maxLen: 128)
        #expect(uuidString == "ABC-123")
    }

    @Test func pingCommandHasCorrectOpcode() {
        let data = buildCommand(opcode: .ping)
        let opcode = readUInt32(from: data, at: 4)
        #expect(opcode == 0xFF)
    }

    @Test func versionFieldIsSet() {
        let data = buildCommand(opcode: .ping)
        let version = readUInt32(from: data, at: 0)
        #expect(version == smProtocolVersion)
    }

    @Test func emptyDisplayUUIDIsZeroed() {
        let data = buildCommand(opcode: .ping)
        for i in 24..<152 {
            #expect(data[i] == 0)
        }
    }

    @Test func longDisplayUUIDTruncatedAt127() {
        let longUUID = String(repeating: "X", count: 200)
        let data = buildCommand(opcode: .moveSpaceToDisplay, displayUUID: longUUID)
        #expect(data[24 + 126] == UInt8(ascii: "X"))
        #expect(data[24 + 127] == 0)
    }

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private func readUInt64(from data: Data, at offset: Int) -> UInt64 {
        data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
    }

    private func readCString(from data: Data, at offset: Int, maxLen: Int) -> String {
        let bytes = [UInt8](data.subdata(in: offset..<offset+maxLen))
        return String(cString: bytes + [0])
    }
}


struct SpaceEnumeratorTests {
    @Test func enumerateReturnsResults() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        #expect(results.isEmpty == false)
    }

    @Test func eachDisplayHasAtLeastOneSpace() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        for ds in results {
            #expect(ds.spaces.isEmpty == false)
        }
    }

    @Test func exactlyOneCurrentSpacePerDisplay() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        for ds in results {
            let currentCount = ds.spaces.filter(\.isCurrentSpace).count
            #expect(currentCount == 1)
        }
    }

    @Test func spaceIDsAreUnique() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        let allIDs = results.flatMap(\.spaces).map(\.spaceID)
        let uniqueIDs = Set(allIDs)
        #expect(allIDs.count == uniqueIDs.count)
    }

    @Test func displayUUIDsAreNonEmpty() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        for ds in results {
            #expect(ds.display.uuid.isEmpty == false)
            for space in ds.spaces {
                #expect(space.displayUUID == ds.display.uuid)
            }
        }
    }

    @Test func spacesHaveValidType() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        for ds in results {
            for space in ds.spaces {
                #expect(space.spaceType == .desktop || space.spaceType == .fullscreen)
            }
        }
    }

    @Test func desktopSpacesHaveSequentialIndices() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        for ds in results {
            let desktops = ds.spaces.filter { $0.spaceType == .desktop }
            for (i, space) in desktops.enumerated() {
                #expect(space.managedSpaceIndex == i)
            }
        }
    }

    @Test func fullscreenSpacesHaveNegativeIndex() {
        let results = SpaceEnumerator.enumerateDisplaySpaces()
        for ds in results {
            for space in ds.spaces where space.spaceType == .fullscreen {
                #expect(space.managedSpaceIndex == -1)
            }
        }
    }
}
