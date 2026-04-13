import Foundation
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.twttr.SpaceMover", category: "SkyLightBridge")

enum SkyLightBridge {
    private static let handle: UnsafeMutableRawPointer? = {
        let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        if h == nil {
            logger.error("Failed to load SkyLight framework: \(String(cString: dlerror()))")
        }
        return h
    }()

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle else { return nil }
        guard let sym = dlsym(handle, name) else {
            logger.warning("SkyLight symbol not found: \(name)")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }

    typealias MainConnectionFn = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> CFArray?
    typealias GetCurrentSpaceFn = @convention(c) (Int32, CFString) -> UInt64
    typealias CopyManagedDisplaysFn = @convention(c) (Int32) -> CFArray?
    typealias MoveSpaceToDisplayIndexFn = @convention(c) (Int32, UInt64, CFString, UInt32) -> Void
    typealias SetCurrentSpaceFn = @convention(c) (Int32, CFString, UInt64) -> Void
    typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Void
    typealias HideSpacesFn = @convention(c) (Int32, CFArray) -> Void
    typealias DisableUpdateFn = @convention(c) (Int32) -> Void
    typealias ReenableUpdateFn = @convention(c) (Int32) -> Void
    typealias CopyWindowsWithOptionsAndTagsFn = @convention(c) (Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> CFArray?
    typealias GetWindowOwnerFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> CGError
    typealias ConnectionGetPIDFn = @convention(c) (Int32, UnsafeMutablePointer<pid_t>) -> CGError

    static let mainConnectionID: MainConnectionFn? = symbol("SLSMainConnectionID")
    static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? = symbol("SLSCopyManagedDisplaySpaces")
    static let getCurrentSpace: GetCurrentSpaceFn? = symbol("SLSManagedDisplayGetCurrentSpace")
    static let copyManagedDisplays: CopyManagedDisplaysFn? = symbol("SLSCopyManagedDisplays")
    static let moveSpaceToDisplayIndex: MoveSpaceToDisplayIndexFn? = symbol("SLSMoveManagedSpaceToDisplayIndex")
    static let setCurrentSpace: SetCurrentSpaceFn? = symbol("SLSManagedDisplaySetCurrentSpace")
    static let showSpaces: ShowSpacesFn? = symbol("SLSShowSpaces")
    static let hideSpaces: HideSpacesFn? = symbol("SLSHideSpaces")
    static let disableUpdate: DisableUpdateFn? = symbol("SLSDisableUpdate")
    static let reenableUpdate: ReenableUpdateFn? = symbol("SLSReenableUpdate")
    static let copyWindowsWithOptionsAndTags: CopyWindowsWithOptionsAndTagsFn? = symbol("SLSCopyWindowsWithOptionsAndTags")
    static let getWindowOwner: GetWindowOwnerFn? = symbol("SLSGetWindowOwner")
    static let connectionGetPID: ConnectionGetPIDFn? = symbol("SLSConnectionGetPID")

    static var isAvailable: Bool {
        mainConnectionID != nil
            && copyManagedDisplaySpaces != nil
            && moveSpaceToDisplayIndex != nil
    }
}
