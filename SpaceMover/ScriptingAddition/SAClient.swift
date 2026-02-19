import Foundation

enum SAClient {
    static func send(_ commandData: Data) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            spaceMoverSocketPath.withCString { cstr in
                _ = strlcpy(ptr, cstr, MemoryLayout.size(ofValue: sockaddr_un().sun_path))
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        guard connectResult == 0 else { return false }

        let writeResult = commandData.withUnsafeBytes { bufPtr in
            Darwin.write(fd, bufPtr.baseAddress!, commandData.count)
        }
        guard writeResult == commandData.count else { return false }

        var response: UInt32 = 0
        let readResult = Darwin.read(fd, &response, MemoryLayout<UInt32>.size)
        guard readResult == MemoryLayout<UInt32>.size else { return false }

        return response == SMStatus.ok.rawValue
    }
}
