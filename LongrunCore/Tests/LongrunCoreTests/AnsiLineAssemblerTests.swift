import Foundation
import Testing
@testable import LongrunCore

@Suite struct AnsiLineAssemblerTests {

    /// Feed a string's UTF-8 bytes through the assembler in one shot.
    private func lines(_ s: String) -> [String] {
        var a = AnsiLineAssembler()
        var out = a.feed(Array(s.utf8))
        out += a.finish()
        return out
    }

    // MARK: line boundaries

    @Test func splitsOnNewlines() {
        #expect(lines("a\nb\nc\n") == ["a", "b", "c"])
    }

    @Test func blankLinesArePreserved() {
        #expect(lines("a\n\nb\n") == ["a", "", "b"])
    }

    @Test func trailingPartialLineFlushedByFinish() {
        var a = AnsiLineAssembler()
        #expect(a.feed(Array("abc".utf8)) == [])
        #expect(a.finish() == ["abc"])
    }

    @Test func collapsesCRLF() {
        #expect(lines("a\r\nb\r\n") == ["a", "b"])
    }

    @Test func loneCarriageReturnIsABoundary() {
        #expect(lines("abc\rdef\n") == ["abc", "def"])
    }

    @Test func progressBarOverwritesBecomeLines() {
        #expect(lines("p 0%\rp 50%\rp 100%\n") == ["p 0%", "p 50%", "p 100%"])
    }

    @Test func crlfSplitAcrossChunksStillCollapses() {
        var a = AnsiLineAssembler()
        #expect(a.feed(Array("a\r".utf8)) == ["a"])   // \r emits the line
        #expect(a.feed(Array("\nb\n".utf8)) == ["b"]) // the \n collapses, no extra empty line
    }

    @Test func spinnerFinalizeDoesNotEmitSpuriousEmptyLine() {
        // The near-universal progress finalize: frame, \r, clear-to-EOL, \n.
        // The stripped ESC[K must stay transparent so \r\n still collapses.
        #expect(lines("done\r\u{1B}[K\n") == ["done"])
        #expect(lines("working\rdone\r\u{1B}[K\n") == ["working", "done"])
    }

    @Test func loneCRBeforeFinishHasNoTrailingEmptyLine() {
        var a = AnsiLineAssembler()
        #expect(a.feed(Array("abc\r".utf8)) == ["abc"])
        #expect(a.finish() == [])
    }

    // MARK: escape sequences

    @Test func stripsCSIColors() {
        #expect(lines("\u{1B}[31mred\u{1B}[0m\n") == ["red"])
        #expect(lines("a\u{1B}[1mb\u{1B}[0mc\n") == ["abc"])
    }

    @Test func stripsOSCTitleTerminatedByBEL() {
        #expect(lines("\u{1B}]0;the title\u{07}body\n") == ["body"])
    }

    @Test func stripsOSCTitleTerminatedByST() {
        #expect(lines("\u{1B}]0;the title\u{1B}\\body\n") == ["body"])
    }

    @Test func stripsOSC8Hyperlink() {
        let s = "\u{1B}]8;;https://example.com\u{1B}\\a link\u{1B}]8;;\u{1B}\\\n"
        #expect(lines(s) == ["a link"])
    }

    @Test func stripsCharsetDesignation() {
        #expect(lines("\u{1B}(Babc\n") == ["abc"])
    }

    @Test func stripsTwoByteEscapes() {
        #expect(lines("\u{1B}=abc\n") == ["abc"])
        #expect(lines("\u{1B}cabc\n") == ["abc"])
    }

    // MARK: control bytes

    @Test func dropsBELandBSandDEL() {
        #expect(lines("a\u{07}b\u{08}c\u{7F}d\n") == ["abcd"])
    }

    @Test func keepsTabs() {
        #expect(lines("a\tb\n") == ["a\tb"])
    }

    @Test func keepsMultibyteUTF8() {
        #expect(lines("café ☕\n") == ["café ☕"])
    }

    // MARK: cross-chunk robustness

    @Test func danglingEscapeAbortsOnNewlineInsteadOfSwallowingLines() {
        // A program killed mid-escape (or buggy) leaves a dangling sequence; a
        // bare \n must abort it, not merge the next line into it.
        #expect(lines("oops\u{1B}[\nnext\n") == ["oops", "next"])
        #expect(lines("title\u{1B}]0;unterminated\nreal line\n") == ["title", "real line"])
    }

    @Test func finishDropsAnIncompleteSequence() {
        var a = AnsiLineAssembler()
        #expect(a.feed(Array("pre\u{1B}[".utf8)) == [])   // dangling CSI
        #expect(a.finish() == ["pre"])                    // sequence dropped, buffer flushed
    }

    @Test func emptyFeedProducesNothing() {
        var a = AnsiLineAssembler()
        #expect(a.feed([UInt8]()) == [])
        #expect(a.finish() == [])
    }

    @Test func oscTerminatorSplitAcrossChunks() {
        var a = AnsiLineAssembler()
        #expect(a.feed(Array("\u{1B}]0;t\u{1B}".utf8)) == [])   // ST split: ESC in one chunk
        #expect(a.feed(Array("\\body\n".utf8)) == ["body"])     // the \\ completing ST in the next
    }

    @Test func escapeSplitAcrossChunks() {
        var a = AnsiLineAssembler()
        #expect(a.feed([0x1B]) == [])                          // ESC alone
        #expect(a.feed([0x5B, 0x31, 0x6D]) == [])              // [1m
        #expect(a.feed(Array("x\n".utf8)) == ["x"])
    }

    @Test func utf8RuneSplitAcrossChunks() {
        // "é" is 0xC3 0xA9 — split it across two feeds.
        var a = AnsiLineAssembler()
        #expect(a.feed([0x63, 0x61, 0x66, 0xC3]) == [])        // "caf" + first byte of é
        #expect(a.feed([0xA9, 0x0A]) == ["café"])
    }

    /// The centerpiece: a torture stream must yield identical lines no matter
    /// how the bytes are chunked.
    @Test func tortureStreamIsChunkSizeInvariant() {
        let stream =
            "\u{1B}[32mgreen\u{1B}[0m line one\n" +
            "progress: 0%\rprogress: 50%\rprogress: 100%\n" +
            "\u{1B}]0;window title\u{07}after title\n" +
            "\u{1B}]8;;https://example.com\u{1B}\\a link\u{1B}]8;;\u{1B}\\\n" +
            "café ☕\n" +
            "tab\there\n" +
            "no newline at end"
        let bytes = Array(stream.utf8)
        let expected = [
            "green line one",
            "progress: 0%", "progress: 50%", "progress: 100%",
            "after title",
            "a link",
            "café ☕",
            "tab\there",
            "no newline at end",
        ]
        for chunkSize in [1, 2, 3, 5, 7, bytes.count] {
            #expect(assemble(bytes, chunkSize: chunkSize) == expected, "chunkSize=\(chunkSize)")
        }
    }

    private func assemble(_ bytes: [UInt8], chunkSize: Int) -> [String] {
        var a = AnsiLineAssembler()
        var out: [String] = []
        var i = 0
        while i < bytes.count {
            let end = min(i + chunkSize, bytes.count)
            out += a.feed(bytes[i..<end])
            i = end
        }
        out += a.finish()
        return out
    }
}
