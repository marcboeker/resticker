import Foundation

/// Turns a free-form argument list into one editable line of text, and back. Settings
/// shows arguments this way rather than as a growable list of text fields, so the split
/// and join must round trip: `split(join(x)) == x` for any `x`.
public enum ShellWords {
    /// Splits on whitespace, honouring single quotes, double quotes, and backslash
    /// escapes. An unterminated quote just takes the rest of the text as its content,
    /// rather than throwing, since this only ever edits a value the user is still typing.
    public static func split(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var hasCurrent = false
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                if hasCurrent {
                    words.append(current)
                    current = ""
                    hasCurrent = false
                }
                i += 1
                continue
            }

            hasCurrent = true
            switch c {
            case "'":
                i += 1
                while i < chars.count, chars[i] != "'" {
                    current.append(chars[i])
                    i += 1
                }
                i += 1 // skip the closing quote, or step past the end if there was none
            case "\"":
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "\"" || chars[i + 1] == "\\" {
                        current.append(chars[i + 1])
                        i += 2
                    } else {
                        current.append(chars[i])
                        i += 1
                    }
                }
                i += 1
            case "\\":
                if i + 1 < chars.count {
                    current.append(chars[i + 1])
                    i += 2
                } else {
                    i += 1
                }
            default:
                current.append(c)
                i += 1
            }
        }

        if hasCurrent { words.append(current) }
        return words
    }

    /// Quotes an argument only when `split` would otherwise misread it: when it contains
    /// whitespace, a quote character, a backslash, or when it is empty.
    public static func join(_ args: [String]) -> String {
        args.map(quoted).joined(separator: " ")
    }

    private static func quoted(_ arg: String) -> String {
        let needsQuoting = arg.isEmpty || arg.contains { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" }
        guard needsQuoting else { return arg }
        var escaped = ""
        for c in arg {
            if c == "\"" || c == "\\" { escaped.append("\\") }
            escaped.append(c)
        }
        return "\"\(escaped)\""
    }
}
