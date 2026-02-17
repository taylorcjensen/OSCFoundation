import Foundation

/// Pattern matching for OSC address patterns per the OSC 1.0 specification.
///
/// Supports the following wildcards within a single address part (between `/` delimiters):
/// - `*` matches any sequence of characters (but not `/`)
/// - `?` matches any single character
/// - `[abc]` matches any character in the set
/// - `[a-z]` matches any character in the range
/// - `[!abc]` matches any character NOT in the set
/// - `{foo,bar}` matches any of the comma-separated alternatives
public enum OSCPatternMatch {

    /// Tests whether an OSC address pattern matches a concrete address.
    ///
    /// Both pattern and address are split on `/` and each part is matched
    /// independently. The number of parts must be equal.
    ///
    /// - Parameters:
    ///   - pattern: The OSC pattern (may contain wildcards).
    ///   - address: The concrete OSC address (no wildcards).
    /// - Returns: `true` if the pattern matches the address.
    public static func matches(pattern: String, address: String) -> Bool {
        let patternParts = pattern.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        let addressParts = address.split(separator: "/", omittingEmptySubsequences: false).dropFirst()

        guard patternParts.count == addressParts.count else { return false }

        for (pat, addr) in zip(patternParts, addressParts) {
            if !matchPart(pattern: Array(pat), address: Array(addr)) {
                return false
            }
        }
        return true
    }

    // MARK: - Internal

    /// Matches a single address part (no `/` characters) against a pattern part.
    static func matchPart(pattern: [Character], address: [Character]) -> Bool {
        matchPart(pattern: pattern, pi: 0, address: address, ai: 0)
    }

    /// Recursive pattern matcher for a single part.
    private static func matchPart(
        pattern: [Character], pi: Int,
        address: [Character], ai: Int
    ) -> Bool {
        var pi = pi
        var ai = ai

        while pi < pattern.count {
            let p = pattern[pi]

            switch p {
            case "*":
                // Try matching zero or more characters
                pi += 1
                // If * is at end of pattern, it matches everything remaining
                if pi == pattern.count { return true }
                // Try each possible length for the wildcard
                for tryAi in ai ... address.count {
                    if matchPart(pattern: pattern, pi: pi, address: address, ai: tryAi) {
                        return true
                    }
                }
                return false

            case "?":
                guard ai < address.count else { return false }
                pi += 1
                ai += 1

            case "[":
                guard ai < address.count else { return false }
                let ch = address[ai]
                guard let result = matchBracket(pattern: pattern, pi: pi, char: ch) else {
                    return false
                }
                if !result.matched { return false }
                pi = result.nextIndex
                ai += 1

            case "{":
                if let result = matchBrace(pattern: pattern, pi: pi, address: address, ai: ai) {
                    return result
                }
                // Malformed brace (no matching '}') - treat '{' as literal
                guard ai < address.count, p == address[ai] else { return false }
                pi += 1
                ai += 1

            default:
                guard ai < address.count, p == address[ai] else { return false }
                pi += 1
                ai += 1
            }
        }

        return ai == address.count
    }

    /// Matches a `[...]` character set/range expression.
    ///
    /// - Returns: A tuple of (matched, nextIndex past the `]`), or `nil` if malformed.
    private static func matchBracket(
        pattern: [Character], pi: Int, char: Character
    ) -> (matched: Bool, nextIndex: Int)? {
        var i = pi + 1 // skip '['
        guard i < pattern.count else { return nil }

        let negate = pattern[i] == "!"
        if negate { i += 1 }

        var matched = false

        while i < pattern.count, pattern[i] != "]" {
            if i + 2 < pattern.count, pattern[i + 1] == "-", pattern[i + 2] != "]" {
                // Range: [a-z]
                let lo = pattern[i]
                let hi = pattern[i + 2]
                if char >= lo, char <= hi { matched = true }
                i += 3
            } else {
                if pattern[i] == char { matched = true }
                i += 1
            }
        }

        guard i < pattern.count else { return nil } // no closing ']'

        if negate { matched = !matched }
        return (matched, i + 1) // skip past ']'
    }

    /// Matches a `{foo,bar,...}` alternative expression with literal string matching.
    ///
    /// Per the OSC 1.0 spec, brace alternatives are a "list of strings" --
    /// each alternative is matched literally, not as a pattern. Wildcards
    /// (`*`, `?`) inside braces have no special meaning.
    ///
    /// - Returns: Match result, or `nil` if the brace expression is malformed
    ///   (no matching `}`), signaling the caller to treat `{` as literal.
    private static func matchBrace(
        pattern: [Character], pi: Int,
        address: [Character], ai: Int
    ) -> Bool? {
        var i = pi + 1 // skip '{'
        var depth = 1

        // Find the closing '}' and extract alternatives
        var alternatives: [[Character]] = [[]]
        while i < pattern.count, depth > 0 {
            if pattern[i] == "{" {
                depth += 1
                alternatives[alternatives.count - 1].append(pattern[i])
            } else if pattern[i] == "}" {
                depth -= 1
                if depth > 0 {
                    alternatives[alternatives.count - 1].append(pattern[i])
                }
            } else if pattern[i] == "," && depth == 1 {
                alternatives.append([])
            } else {
                alternatives[alternatives.count - 1].append(pattern[i])
            }
            i += 1
        }

        // Malformed: no matching closing brace
        guard depth == 0 else { return nil }

        // i is now past the closing '}'
        let restPattern = Array(pattern[i...])

        for alt in alternatives {
            // Skip empty alternatives
            if alt.isEmpty { continue }

            // Match alternative literally (not as a pattern)
            let end = ai + alt.count
            guard end <= address.count else { continue }
            if Array(address[ai ..< end]) == alt {
                if matchPart(pattern: restPattern, pi: 0, address: address, ai: end) {
                    return true
                }
            }
        }

        return false
    }
}
