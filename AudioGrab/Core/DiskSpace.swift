import Foundation

enum DiskSpace {
    /// Don't start a recording with less free space than this.
    static let minimumFreeToStart: Int64 = 200 * 1024 * 1024
    /// Stop a running recording (and save it) below this.
    static let minimumFreeWhileRecording: Int64 = 100 * 1024 * 1024

    static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        if let plain = values?.volumeAvailableCapacity { return Int64(plain) }
        return nil
    }

    /// True for the different ways "disk full" shows up from Foundation and Core Audio.
    static func isOutOfSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
        if ns.domain == NSOSStatusErrorDomain && ns.code == -34 { return true } // dskFulErr
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }
}
