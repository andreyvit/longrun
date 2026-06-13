/// Turns a raw PTY byte stream into clean, matchable text lines: strips ANSI
/// escape sequences, drops control bytes, and splits on line boundaries
/// (including a lone `\r`, so progress-bar overwrites become separate lines).
///
/// This feeds output MATCHING only — the terminal view renders the raw bytes
/// itself. State persists across `feed` calls, so an escape sequence or a UTF-8
/// rune split across read chunks is handled correctly; bytes accumulate raw and
/// are decoded (lossy UTF-8) only when a line is emitted.
public struct AnsiLineAssembler {
    private enum State: Equatable {
        case normal
        case escape        // saw ESC, deciding what the sequence is
        case csi           // ESC [ … — until a final byte 0x40–0x7E
        case stringLike    // OSC / DCS / SOS / PM / APC — until BEL or ST
        case stringEscape  // saw ESC inside stringLike (maybe the start of ST)
        case charset       // ESC ( ) * + — consume one designation byte
    }

    private var state: State = .normal
    private var line: [UInt8] = []
    private var lastWasCR = false

    public init() {}

    /// Feed a chunk of output bytes; returns any lines completed by this chunk.
    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [String] {
        var lines: [String] = []
        for b in bytes { process(b, into: &lines) }
        return lines
    }

    /// Flush a trailing partial line (output with no terminating newline). Any
    /// in-progress escape sequence is discarded — it was being stripped anyway.
    public mutating func finish() -> [String] {
        state = .normal
        lastWasCR = false
        guard !line.isEmpty else { return [] }
        defer { line.removeAll(keepingCapacity: false) }
        return [decode(line)]
    }

    private mutating func process(_ b: UInt8, into lines: inout [String]) {
        // A newline or carriage return can't appear in a valid escape sequence.
        // If one shows up, the program abandoned the sequence (e.g. it was
        // killed mid-escape — which this app does on Stop), so abort and let the
        // byte be the line boundary it is, instead of swallowing real output.
        if state != .normal, b == 0x0A || b == 0x0D {
            state = .normal
            processNormal(b, into: &lines)
            return
        }
        switch state {
        case .normal:
            processNormal(b, into: &lines)

        case .escape:
            switch b {
            case 0x5B: state = .csi                                    // [
            case 0x5D, 0x50, 0x58, 0x5E, 0x5F: state = .stringLike     // ] P X ^ _
            case 0x28, 0x29, 0x2A, 0x2B: state = .charset             // ( ) * +
            case 0x1B: state = .escape                                 // ESC ESC — decide on the new one
            default: state = .normal                                   // 2-byte escape, consumed
            }

        case .csi:
            if b == 0x1B { state = .escape }                           // a new sequence aborts this one
            else if (0x40...0x7E).contains(b) { state = .normal }      // final byte ends CSI

        case .stringLike:
            if b == 0x07 { state = .normal }                          // BEL terminator
            else if b == 0x1B { state = .stringEscape }

        case .stringEscape:
            if b == 0x5C { state = .normal }                          // ST = ESC \
            else if b == 0x1B { state = .stringEscape }
            else { state = .stringLike }                              // not ST; keep consuming the string

        case .charset:
            state = .normal                                           // the one designation byte
        }
    }

    private mutating func processNormal(_ b: UInt8, into lines: inout [String]) {
        if b == 0x0A {  // \n
            if lastWasCR { lastWasCR = false }                        // collapse \r\n (line emitted on \r)
            else { emitLine(into: &lines) }
            return
        }
        // `lastWasCR` is cleared only by actual text/tab below — escapes and
        // dropped controls are transparent to the \r/\n collapse, so the common
        // spinner-finalize pattern `\r` + `ESC[K` + `\n` collapses to one line
        // instead of leaving a spurious empty one.
        switch b {
        case 0x0D:                 // \r — boundary (progress-bar overwrite)
            emitLine(into: &lines)
            lastWasCR = true
        case 0x1B:                 // ESC — transparent
            state = .escape
        case 0x09:                 // \t — keep
            line.append(b)
            lastWasCR = false
        case 0x00...0x1F, 0x7F:    // other C0 controls + DEL — drop (BEL, BS, etc.), transparent
            break
        default:
            line.append(b)
            lastWasCR = false
        }
    }

    private mutating func emitLine(into lines: inout [String]) {
        lines.append(decode(line))
        line.removeAll(keepingCapacity: true)
    }

    private func decode(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}
