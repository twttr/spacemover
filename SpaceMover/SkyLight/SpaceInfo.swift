enum SpaceType: Int {
    case desktop = 0
    case fullscreen = 4
}

struct SpaceInfo {
    let spaceID: UInt64
    let displayUUID: String
    let isCurrentSpace: Bool
    let managedSpaceIndex: Int
    let spaceType: SpaceType
    let appNames: [String]
}
