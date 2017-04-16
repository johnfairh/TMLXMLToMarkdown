//
//  XmlToMarkdown.swift
//  XmlToMarkdown
//
//  Distributed under the ISC license, see LICENSE.
//

//
// indexer["Discussion"].element!.description
//

import Foundation

// MARK: Additions to help with regular expressions

extension String {

    /// An NSRange corresponding to the entire string
    var nsRange: NSRange {
        return NSMakeRange(0, utf16.count)
    }

    /// The substring corresponding to an NSRange, or empty if none
    subscript(nsRange: NSRange) -> String {
        let strLower = String.UTF16Index(nsRange.location)
        let strUpper = String.UTF16Index(nsRange.location + nsRange.length)

        return String(utf16[strLower..<strUpper]) ?? ""
    }
}

extension NSTextCheckingResult {
    /// The substrings corresponding to the matches
    func rangesToStrings(from string: String) -> [String?] {
        var strings: [String?] = []
        for rangeIdx in 0..<numberOfRanges {
            let range = rangeAt(rangeIdx)
            if range.location != NSNotFound {
                // capture group was optional and not matched
                strings.append(string[range])
            } else {
                strings.append(nil)
            }
        }
        return strings
    }
}

extension NSRegularExpression {
    // The substrings corresponding to matches, or nil if no match
    func matches(in string: String) -> [String?]? {
        let results = matches(in: string, range: string.nsRange)

        guard results.count > 0 else {
            return nil
        }

        return results[0].rangesToStrings(from: string)
    }
}

// MARK: XMLToMarkdown

public class XMLToMarkdown: NSObject, XMLParserDelegate {

    /// XML element names we recognize
    enum Element: String {
        case discussion        = "Discussion"
        case para              = "Para"
        case strong            = "strong"
        case emphasis          = "emphasis"
        case codeVoice         = "codeVoice"
        case codeListing       = "CodeListing"
        case zCodeLineNumbered = "zCodeLineNumbered"
        case link              = "Link"
        case rawHTML           = "rawHTML"
        case listBullet        = "List-Bullet"
        case listNumber        = "List-Number"
        case item              = "Item"
    }

    /// Elements we can be inside that affect child-element formatting
    struct Inside: OptionSet {
        let rawValue: Int

        static let nothing     = Inside(rawValue: 0)
        static let para        = Inside(rawValue: 1<<0)
        static let codeListing = Inside(rawValue: 1<<1)
        static let htmlHeading = Inside(rawValue: 1<<2)
        static let listBullet  = Inside(rawValue: 1<<3)
        static let listNumber  = Inside(rawValue: 1<<4)

        static let allLists: Inside = [.listBullet, .listNumber]
    }
    private var inside: Inside = .nothing

    // Stuff that doesn't work in Xcode 8.3 markup although it is documented:
    // 1. Backslash at end of line causes hard linebreak.
    // 2. Smart ordered list items, ie. start with '4.' and it follows.
    // 3. 4-space indent to indent hrs + headings (!)
    //
    // Stuff hinted at https://github.com/apple/swift/blob/master/include/swift/Markup/ASTNodes.def
    // that isn't documented:
    // 1. BlockQuote

    /// Accumulated markdown
    private var output = ""

    /// Indentation level caused by nested lists
    struct Indent {
        private var level = 0
        private var skip  = false

        mutating func reset()    { level = 0; skip = false }
        mutating func inc()      { level += 1 }
        mutating func dec()      { level -= 1 }
        mutating func skipNext() { skip = true }

        private static let WIDTH = 4

        mutating func prefix() -> String {
            if skip {
                skip = false
                return ""
            }
            return String(repeating: " ", count: Indent.WIDTH * level)
        }
    }
    private var indent = Indent()

    private func reset() {
        output = ""
        indent.reset()
        inside = .nothing
        elementDoneStack = []
    }

    /// Create a new SourceKit XML converter.
    public override init() {
    }

    /// Convert SourceKit XML to Redcarpet markdown
    ///
    /// - Parameter xml: SourceKit XML
    /// - Returns: Markdown version of the XML.  Empty string on any failure.
    public func parseDiscussion(xml: String) -> String {
        reset()

        if let xmlData = xml.data(using: .utf8) {
            let parser  = XMLParser(data: xmlData)
            parser.delegate = self
            let success = parser.parse()
            if !success {
                // TODO: error
                fatalError("Failed??")
            }
        }

        return output
    }

    /// Stack of work to do as elements close
    private typealias ElementDone = () -> Void
    private var elementDoneStack: [ElementDone?] = []

    /// Main formatter - spot interesting tags, do something + schedule more work for when the element ends.
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        guard let element = Element(rawValue: elementName) else {
            // TODO: warning unknown element
            elementDoneStack.append(nil)
            return
        }

        var elementDone: ElementDone? = nil

        switch element {
        case .discussion:
            // When discussion ends trim off the likely dangling newlines from the last para.
            elementDone = {
                self.output = self.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }

        case .emphasis:
            output += "*"
            elementDone = { self.output += "*" }
        case .strong:
            output += "**"
            elementDone = { self.output += "**" }
        case .codeVoice:
            output += "`"
            elementDone = { self.output += "`" }

        case .link:
            output += "["
            elementDone = {
                let href = attributeDict["href"] ?? ""
                self.output += "](\(href))"
            }

        case .para:
            output += indent.prefix()
            inside.insert(.para)
            elementDone = {
                self.output += "\n\n"
                self.inside.remove(.para)
            }

        case .codeListing:
            output += indent.prefix() + "```" + (attributeDict["language"] ?? "") + "\n"
            inside.insert(.codeListing)
            elementDone = {
                self.output += self.indent.prefix() + "```\n\n"
                self.inside.remove(.codeListing)
            }
        case .zCodeLineNumbered:
            break

        case .rawHTML:
            // Can be block or inline :(  If block then have to do indent + paragraphing.
            if !inside.contains(.para) {
                output += indent.prefix()
                elementDone = {
                    if !self.inside.contains(.htmlHeading) {
                        self.output += "\n\n"
                    }
                    self.inside.remove(.htmlHeading)
                }
            }

        case .listBullet, .listNumber:
            output += indent.prefix()
            indent.inc()
            // must remember what type of bullet to make and store what we're doing now for later.
            let currentList = inside.remove(.allLists) ?? .nothing
            inside.insert(element == .listBullet ? .listBullet : .listNumber)
            elementDone = {
                self.indent.dec()
                self.inside.remove(.allLists)
                self.inside.insert(currentList)
            }

        case .item:
            if inside.contains(.listBullet) {
                output += "- "
            } else {
                output += "1. " // thankfully we can cheat here :)
            }
            // no indent for next <para> - follows bullet directly
            indent.skipNext()
        }

        elementDoneStack.append(elementDone)
    }

    /// End of element - just process whatever was saved when the element opened.
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let elementDone = elementDoneStack.removeLast()
        elementDone?()
    }
    
    /// Text to pass through.  Stop redcarpet from interpreting any stuff as markdown formatting.
    static let markdownCharsRegex: NSRegularExpression = {
        let markdownChars = "-_*+`.#"
        let escapedChars = NSRegularExpression.escapedPattern(for: markdownChars)
        return try! NSRegularExpression(pattern: "[\(escapedChars)]")
    }()

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        let regex = XMLToMarkdown.markdownCharsRegex
        output += regex.stringByReplacingMatches(in: string, range: string.nsRange, withTemplate: "\\\\$0")
    }

    /// CDATA.  Used for html, stuff that looks like html, each line of a code block.
    /// Headings and HR in markdown end up as HTML rather than tags.
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let cdataString = String(data: CDATABlock, encoding: .utf8) else {
            // TODO: error
            fatalError("CDATA is not utf8 \(CDATABlock as NSData)")
        }

        if inside.contains(.codeListing) {
            output += indent.prefix() + cdataString + "\n"
        } else if let imageLink = parseImageLink(html: cdataString) {
            output += imageLink
        } else if cdataString == "<hr/>" {
            output += "---"
        } else if let heading = parseHeading(html: cdataString) {
            output += heading
        } else {
            output += cdataString
        }
    }

    /// Painful <img> roundtripping.  Relies on SourceKit's attrib ordering.
    static let imgTagRegex: NSRegularExpression =
        try! NSRegularExpression(pattern: "<img src=\"(.*?)\"(?: title=\"(.*?)\")?(?: alt=\"(.*?)\")?/>")

    private func parseImageLink(html: String) -> String? {
        guard let matchedStrings = XMLToMarkdown.imgTagRegex.matches(in: html) else {
            return nil
        }

        var imgMarkdown = "!["

        if let altText = matchedStrings[3] {
            imgMarkdown += altText
        }

        imgMarkdown += "](\(matchedStrings[1]!)"

        if let title = matchedStrings[2] {
            imgMarkdown += " \"\(title)\""
        }

        imgMarkdown += ")"

        return imgMarkdown
    }

    /// Headings
    static let headingTagRegex: NSRegularExpression =
        try! NSRegularExpression(pattern: "<(/)?h(\\d)>")

    private func parseHeading(html: String) -> String? {
        guard let matchedStrings = XMLToMarkdown.headingTagRegex.matches(in: html) else {
            return nil
        }

        if matchedStrings[1] != nil {
            return ""
        } else if let level = Int(matchedStrings[2]!) {
            // need to NOT have a newline after this html...
            inside.insert(.htmlHeading)
            return String(repeating: "#", count: level) + " "
        } else {
            return nil
        }
    }
    
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // TODO: report
    }
}
