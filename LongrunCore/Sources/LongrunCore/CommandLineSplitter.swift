/// Splits an exec-mode command string into an argv array using POSIX-shell
/// quoting rules — but performs NO expansion (no `$VAR`, globbing, `~`, or
/// command substitution). Those belong to the shell launch modes; exec mode is
/// deliberately literal so a config's command can't accidentally invoke shell
/// behavior.
///
/// Iterates Unicode scalars, not `Character`s, so a `\r\n` can't cluster into a
/// single grapheme and slip past word splitting. CR is treated as a word
/// separator (like newline) — a deliberate, pragmatic divergence from `/bin/sh`
/// (which keeps a lone CR literal): line-ending noise from a paste or a
/// Windows-edited config file should split words, never embed control bytes in
/// argv.
public enum CommandLineSplitter {
    public enum SplitError: Error, Equatable {
        case unterminatedQuote
    }

    public static func split(_ command: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var hasWord = false  // tracks whether the current word exists (quotes can make it empty)

        let scalars = Array(command.unicodeScalars)
        let n = scalars.count
        var i = 0

        while i < n {
            let c = scalars[i]
            switch c {
            case " ", "\t", "\n", "\r":
                if hasWord {
                    args.append(current)
                    current = ""
                    hasWord = false
                }
                i += 1

            case "'":
                hasWord = true
                i += 1
                var closed = false
                while i < n {
                    if scalars[i] == "'" { closed = true; i += 1; break }
                    current.unicodeScalars.append(scalars[i]); i += 1
                }
                if !closed { throw SplitError.unterminatedQuote }

            case "\"":
                hasWord = true
                i += 1
                var closed = false
                while i < n {
                    let ch = scalars[i]
                    if ch == "\"" { closed = true; i += 1; break }
                    if ch == "\\", i + 1 < n {
                        let escaped = scalars[i + 1]
                        switch escaped {
                        case "\"", "\\", "$", "`": current.unicodeScalars.append(escaped); i += 2
                        case "\n": i += 2                                          // line continuation
                        default:
                            current.unicodeScalars.append("\\")
                            current.unicodeScalars.append(escaped)
                            i += 2
                        }
                    } else {
                        current.unicodeScalars.append(ch); i += 1
                    }
                }
                if !closed { throw SplitError.unterminatedQuote }

            case "\\":
                if i + 1 < n {
                    let escaped = scalars[i + 1]
                    if escaped == "\n" {
                        i += 2                                                    // line continuation, no output
                    } else {
                        current.unicodeScalars.append(escaped); hasWord = true; i += 2
                    }
                } else {
                    current.unicodeScalars.append("\\"); hasWord = true; i += 1   // trailing backslash, literal
                }

            default:
                current.unicodeScalars.append(c); hasWord = true; i += 1
            }
        }
        if hasWord { args.append(current) }
        return args
    }
}
