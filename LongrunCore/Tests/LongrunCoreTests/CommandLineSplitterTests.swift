import Testing
@testable import LongrunCore

@Suite struct CommandLineSplitterTests {

    private func split(_ s: String) throws -> [String] {
        try CommandLineSplitter.split(s)
    }

    @Test func splitsOnWhitespaceAndCollapsesRuns() throws {
        #expect(try split("a b c") == ["a", "b", "c"])
        #expect(try split("  a   b\tc\n d ") == ["a", "b", "c", "d"])
    }

    @Test func emptyAndWhitespaceOnly() throws {
        #expect(try split("") == [])
        #expect(try split("   \t \n ") == [])
    }

    @Test func singleQuotesAreLiteral() throws {
        #expect(try split("'a b'") == ["a b"])
        #expect(try split(#"'$HOME and \n stay literal'"#) == [#"$HOME and \n stay literal"#])
    }

    @Test func doubleQuotesGroupAndEscape() throws {
        #expect(try split(#""a b""#) == ["a b"])
        #expect(try split(#""a\"b""#) == [#"a"b"#])         // \" -> "
        #expect(try split(#""a\\b""#) == [#"a\b"#])          // \\ -> \
        #expect(try split(#""a\$b""#) == ["a$b"])            // \$ -> $
        #expect(try split(#""a\nb""#) == [#"a\nb"#])         // \n not special -> literal backslash-n
        #expect(try split(#""it's""#) == ["it's"])           // single quote literal inside double quotes
    }

    @Test func unquotedBackslashEscapes() throws {
        #expect(try split(#"a\ b"#) == ["a b"])              // escaped space joins
        #expect(try split(#"a\\b"#) == [#"a\b"#])            // \\ -> \
        #expect(try split(#"don\'t"#) == ["don't"])
        #expect(try split(#"a\"b"#) == [#"a"b"#])            // escaped quote joins the word
        #expect(try split(#"trailing\"#) == [#"trailing\"#]) // trailing backslash literal
    }

    @Test func carriageReturnsActAsSeparators() throws {
        // \r\n must not cluster into one grapheme and slip past splitting; both
        // CRLF and a lone CR separate words (pragmatic for line-ending noise).
        #expect(try split("alpha\r\nbeta") == ["alpha", "beta"])
        #expect(try split("a\rb") == ["a", "b"])
    }

    @Test func emptyQuotesProduceEmptyArgument() throws {
        #expect(try split("''") == [""])
        #expect(try split(#""""#) == [""])
        #expect(try split("a '' b") == ["a", "", "b"])
    }

    @Test func adjacentRunsConcatenate() throws {
        #expect(try split(#""a"'b'c"#) == ["abc"])
        #expect(try split("a'b'c") == ["abc"])
    }

    @Test func performsNoExpansion() throws {
        #expect(try split("$HOME") == ["$HOME"])
        #expect(try split("a*b") == ["a*b"])
        #expect(try split("~/dir") == ["~/dir"])
        #expect(try split("`whoami`") == ["`whoami`"])
    }

    @Test func lineContinuation() throws {
        #expect(try split("a\\\nb") == ["ab"])              // backslash-newline joins
        #expect(try split("\\\n") == [])                     // lone continuation produces nothing
    }

    @Test func unterminatedQuotesThrow() {
        #expect(throws: CommandLineSplitter.SplitError.unterminatedQuote) { try split("'abc") }
        #expect(throws: CommandLineSplitter.SplitError.unterminatedQuote) { try split(#""abc"#) }
    }

    @Test func realWorldCommands() throws {
        #expect(try split("ssh -MN host") == ["ssh", "-MN", "host"])
        #expect(try split("go run ./cmd/lifebase") == ["go", "run", "./cmd/lifebase"])
        #expect(try split("ngrok http 8080") == ["ngrok", "http", "8080"])
        #expect(try split("tool --flag='a b c'") == ["tool", "--flag=a b c"])
    }
}
