import Testing
@testable import OSCFoundation

@Suite("OSCPatternMatch")
struct OSCPatternMatchTests {

    @Test("Exact match")
    func exactMatch() {
        #expect(OSCPatternMatch.matches(pattern: "/foo/bar", address: "/foo/bar"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/bar", address: "/foo/baz"))
    }

    @Test("Star matches any characters within a part")
    func starMatch() {
        #expect(OSCPatternMatch.matches(pattern: "/foo/*", address: "/foo/bar"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/*", address: "/foo/anything"))
        #expect(OSCPatternMatch.matches(pattern: "/*/bar", address: "/foo/bar"))
        #expect(OSCPatternMatch.matches(pattern: "/*", address: "/anything"))
    }

    @Test("Star does not cross slash boundaries")
    func starDoesNotCrossSlash() {
        #expect(!OSCPatternMatch.matches(pattern: "/*", address: "/foo/bar"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/*", address: "/foo/bar/baz"))
    }

    @Test("Star with partial prefix/suffix")
    func starPartial() {
        #expect(OSCPatternMatch.matches(pattern: "/foo/b*", address: "/foo/bar"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/*r", address: "/foo/bar"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/b*r", address: "/foo/bar"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/b*z", address: "/foo/bar"))
    }

    @Test("Question mark matches one character")
    func questionMark() {
        #expect(OSCPatternMatch.matches(pattern: "/foo/ba?", address: "/foo/bar"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/ba?", address: "/foo/baz"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/ba?", address: "/foo/ba"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/ba?", address: "/foo/barr"))
    }

    @Test("Bracket character set")
    func bracketSet() {
        #expect(OSCPatternMatch.matches(pattern: "/foo/[abc]", address: "/foo/a"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/[abc]", address: "/foo/b"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/[abc]", address: "/foo/c"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/[abc]", address: "/foo/d"))
    }

    @Test("Bracket character range")
    func bracketRange() {
        #expect(OSCPatternMatch.matches(pattern: "/ch/[0-9]", address: "/ch/5"))
        #expect(OSCPatternMatch.matches(pattern: "/ch/[a-z]", address: "/ch/m"))
        #expect(!OSCPatternMatch.matches(pattern: "/ch/[a-z]", address: "/ch/A"))
    }

    @Test("Bracket negation")
    func bracketNegation() {
        #expect(OSCPatternMatch.matches(pattern: "/foo/[!abc]", address: "/foo/d"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/[!abc]", address: "/foo/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/[!abc]", address: "/foo/b"))
    }

    @Test("Brace alternatives")
    func braceAlternatives() {
        #expect(OSCPatternMatch.matches(pattern: "/foo/{bar,baz}", address: "/foo/bar"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/{bar,baz}", address: "/foo/baz"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/{bar,baz}", address: "/foo/qux"))
    }

    @Test("Brace alternatives with more options")
    func braceMultipleAlternatives() {
        #expect(OSCPatternMatch.matches(pattern: "/{a,b,c}/d", address: "/a/d"))
        #expect(OSCPatternMatch.matches(pattern: "/{a,b,c}/d", address: "/b/d"))
        #expect(OSCPatternMatch.matches(pattern: "/{a,b,c}/d", address: "/c/d"))
        #expect(!OSCPatternMatch.matches(pattern: "/{a,b,c}/d", address: "/d/d"))
    }

    @Test("Combined patterns")
    func combinedPatterns() {
        #expect(OSCPatternMatch.matches(pattern: "/eos/*/[0-9]", address: "/eos/out/5"))
        #expect(OSCPatternMatch.matches(pattern: "/eos/out/param/?", address: "/eos/out/param/x"))
        #expect(OSCPatternMatch.matches(pattern: "/eos/{cmd,newcmd}", address: "/eos/cmd"))
        #expect(OSCPatternMatch.matches(pattern: "/eos/{cmd,newcmd}", address: "/eos/newcmd"))
    }

    @Test("Part count mismatch returns false")
    func partCountMismatch() {
        #expect(!OSCPatternMatch.matches(pattern: "/foo", address: "/foo/bar"))
        #expect(!OSCPatternMatch.matches(pattern: "/foo/bar", address: "/foo"))
        #expect(!OSCPatternMatch.matches(pattern: "/a/b/c", address: "/a/b"))
    }

    @Test("Root address")
    func rootAddress() {
        #expect(OSCPatternMatch.matches(pattern: "/", address: "/"))
        #expect(!OSCPatternMatch.matches(pattern: "/", address: "/foo"))
    }

    @Test("Multiple stars")
    func multipleStars() {
        #expect(OSCPatternMatch.matches(pattern: "/*/*", address: "/foo/bar"))
        #expect(OSCPatternMatch.matches(pattern: "/*/*", address: "/a/b"))
        #expect(!OSCPatternMatch.matches(pattern: "/*/*", address: "/foo"))
    }

    @Test("Empty alternative in braces")
    func emptyBraceAlternative() {
        // {,bar} should match empty string or "bar"
        #expect(OSCPatternMatch.matches(pattern: "/foo/{,bar}", address: "/foo/"))
        #expect(OSCPatternMatch.matches(pattern: "/foo/{,bar}", address: "/foo/bar"))
    }

    // MARK: - Bracket Edge Cases

    @Test("Bracket at end of address with address too short")
    func bracketAddressTooShort() {
        // Pattern "/test[a]" vs address "/test" -- address is shorter than pattern expects
        #expect(!OSCPatternMatch.matches(pattern: "/test[a]", address: "/test"))
    }

    @Test("Malformed bracket with no closing bracket")
    func malformedBracketNoClose() {
        // Pattern "/[abc" has no closing ']' -- should not match
        #expect(!OSCPatternMatch.matches(pattern: "/[abc", address: "/a"))
    }

    @Test("Empty bracket expression")
    func emptyBracket() {
        // Pattern "/[]" -- empty bracket set should not match anything
        #expect(!OSCPatternMatch.matches(pattern: "/[]", address: "/a"))
    }

    @Test("Unclosed bracket reaching end of pattern")
    func unclosedBracketEndOfPattern() {
        // Pattern "/[ab" -- no closing ']', reaches end of pattern
        #expect(!OSCPatternMatch.matches(pattern: "/[ab", address: "/a"))
    }

    @Test("Nested braces")
    func nestedBraces() {
        // Pattern "/{a{b,c},d}" -- nested brace alternatives
        // "ab" -> matches inner alternative "a" + "b" from {b,c}
        #expect(OSCPatternMatch.matches(pattern: "/{a{b,c},d}", address: "/ab"))
        #expect(OSCPatternMatch.matches(pattern: "/{a{b,c},d}", address: "/ac"))
        #expect(OSCPatternMatch.matches(pattern: "/{a{b,c},d}", address: "/d"))
        #expect(!OSCPatternMatch.matches(pattern: "/{a{b,c},d}", address: "/a"))
    }
}
