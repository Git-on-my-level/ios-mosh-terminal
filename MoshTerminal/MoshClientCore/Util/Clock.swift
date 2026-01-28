import Foundation
import Darwin

enum Clock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nowMillis() -> UInt64 {
        let ticks = mach_continuous_time()
        let nanos = (UInt64(ticks) * UInt64(timebase.numer)) / UInt64(timebase.denom)
        return nanos / 1_000_000
    }

    static func timestamp16() -> UInt16 {
        return timestamp16(fromMillis: nowMillis())
    }

    static func diff16(new: UInt16, old: UInt16) -> UInt16 {
        return new &- old
    }

    static func timestamp16(fromMillis millis: UInt64) -> UInt16 {
        var value = UInt16(truncatingIfNeeded: millis)
        if value == UInt16.max {
            value = value &+ 1
        }
        return value
    }
}
