import Foundation

enum PTY {
    enum PTYError: Error, Equatable {
        case openFailed(Int32)  // errno
    }

    /// Allocate a pseudo-terminal sized to `columns`×`rows`. Returns the master
    /// (parent-side) and slave (child-side) descriptors. The caller dups the
    /// slave onto the child's stdio and closes its own slave copy after spawn.
    static func open(columns: Int, rows: Int) throws -> (master: Int32, slave: Int32) {
        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(
            ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns),
            ws_xpixel: 0, ws_ypixel: 0
        )
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            throw PTYError.openFailed(errno)
        }
        return (master, slave)
    }

    /// Update the terminal window size and deliver SIGWINCH to the foreground
    /// process group (used when the on-screen terminal view resizes).
    @discardableResult
    static func setWinSize(_ fd: Int32, columns: Int, rows: Int) -> Bool {
        var size = winsize(
            ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns),
            ws_xpixel: 0, ws_ypixel: 0
        )
        return ioctl(fd, TIOCSWINSZ, &size) == 0
    }
}
