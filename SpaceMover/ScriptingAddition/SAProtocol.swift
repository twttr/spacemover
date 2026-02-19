import Foundation

let spaceMoverSocketPath = "/tmp/com.twttr.spacemover.sock"
let smProtocolVersion: UInt32 = 1

enum SMOpcode: UInt32 {
    case moveSpaceToDisplay = 1
    case setCurrentSpace = 3
    case ping = 0xFF
}

enum SMStatus: UInt32 {
    case ok = 1
    case notReady = 2
    case invalidInput = 3
    case unknownOpcode = 4
    case unauthorized = 5
    case versionMismatch = 6
}

func buildCommand(opcode: SMOpcode, spaceID: UInt64 = 0, displayUUID: String = "", targetIndex: UInt32 = 0, afterSpaceID: UInt32 = 0) -> Data {
    var data = Data()

    var ver = smProtocolVersion
    data.append(Data(bytes: &ver, count: 4))

    var op = opcode.rawValue
    data.append(Data(bytes: &op, count: 4))

    var sid = spaceID
    data.append(Data(bytes: &sid, count: 8))

    var tidx = targetIndex
    data.append(Data(bytes: &tidx, count: 4))

    var asid = afterSpaceID
    data.append(Data(bytes: &asid, count: 4))

    var uuidBytes = [CChar](repeating: 0, count: 128)
    if let cString = displayUUID.cString(using: .utf8) {
        let copyLen = min(cString.count, 127)
        for i in 0..<copyLen {
            uuidBytes[i] = cString[i]
        }
    }
    data.append(Data(bytes: &uuidBytes, count: 128))

    return data
}
