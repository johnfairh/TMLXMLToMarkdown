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
                strings.append(string[range])
            } else {
                // capture group was optional and not matched
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

// Stuff that doesn't work in Xcode 8.3 markup although it is documented:
// 1. Backslash at end of line causes hard linebreak.
// 2. Smart ordered list items, ie. start with '4.' and it follows.
// 3. 4-space indent to indent hrs + headings (!)
//
// Stuff hinted at https://github.com/apple/swift/blob/master/include/swift/Markup/ASTNodes.def
// that isn't documented:
// 1. BlockQuote

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
    private var inside = Inside.nothing

    /// Control whitespace at the start of each markdown line
    struct Whitespace {
        private var indentLevel = 0
        mutating func indent()  { indentLevel += 1 }
        mutating func outdent() { indentLevel -= 1 }

        // sometimes we have to skip whatever whitespace would normally apply next
        private var skip = false
        mutating func skipNext()         { skip = true }
        mutating func doSkip() -> String { skip = false; return "" }

        // initial state includes skip to avoid leading newlines
        mutating func reset() { indentLevel = 0; skip = true }

        private static let INDENT_WIDTH = 4

        mutating func prefix() -> String {
            if !skip {
                return String(repeating: " ", count: Whitespace.INDENT_WIDTH * indentLevel)
            }
            return doSkip()
        }

        mutating func listItemPrefix() -> String {
            outdent(); defer { indent() }
            return prefix()
        }

        mutating func newlineAndPrefix() -> String {
            if !skip {
                return "\n" + prefix()
            }
            return doSkip()
        }

        mutating func newline() -> String {
            if !skip {
                return "\n"
            }
            return doSkip()
        }
    }
    private var whitespace = Whitespace()

    /// Currently accumulated markdown
    private var markdown = ""

    /// Reset parser state for new input
    private func reset() {
        markdown = ""
        whitespace.reset()
        inside = .nothing
        elementDoneStack = []
    }

    /// Problem reporting
    public typealias ErrorHandler = (String) -> Void
    private let errorHandler: ErrorHandler?

    /// Create a new SourceKit XML converter.
    public init(errorHandler: ErrorHandler? = nil) {
        self.errorHandler = errorHandler
        super.init()
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
                if let parserError = parser.parserError {
                    errorHandler?("XMLParser.parse failed, parserError \(parserError))")
                } else {
                    errorHandler?("XMLParser.parser failed, no parserError")
                }
                errorHandler?("XML was \(xml), current markdown is \(markdown)")
                errorHandler?("Current line is \(parser.lineNumber) column is \(parser.columnNumber)")
            }
        }

        return markdown
    }

    /// Stack of work to do as elements close
    private typealias ElementDone = () -> Void
    private var elementDoneStack: [ElementDone?] = []

    /// Spot interesting elements, do something + schedule more work for when the element ends.
    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String : String]) {
        guard let element = Element(rawValue: elementName) else {
            elementDoneStack.append(nil)
            return
        }

        var elementDone: ElementDone? = nil

        switch element {
        case .discussion:
            elementDone = {
                self.markdown = self.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break

        case .emphasis:
            markdown += "*"
            elementDone = { self.markdown += "*" }
        case .strong:
            markdown += "**"
            elementDone = { self.markdown += "**" }
        case .codeVoice:
            markdown += "`"
            elementDone = { self.markdown += "`" }

        case .link:
            markdown += "["
            elementDone = {
                let href = attributeDict["href"] ?? ""
                self.markdown += "](\(href))"
            }

        case .para:
            markdown += whitespace.newlineAndPrefix()
            inside.insert(.para)
            elementDone = {
                self.markdown += "\n"
                self.inside.remove(.para)
            }

        case .codeListing:
            markdown += whitespace.newlineAndPrefix() + "```" + (attributeDict["language"] ?? "") + "\n"
            inside.insert(.codeListing)
            elementDone = {
                self.markdown += self.whitespace.prefix() + "```\n"
                self.inside.remove(.codeListing)
            }
        case .zCodeLineNumbered:
            break

        case .rawHTML:
            // Can be block or inline :(  If block then have to do indent + paragraphing.
            if !inside.contains(.para) {
                markdown += whitespace.newlineAndPrefix()
                elementDone = {
                    if !self.inside.contains(.htmlHeading) {
                        self.markdown += "\n"
                    }
                    self.inside.remove(.htmlHeading)
                }
            }

        case .listBullet, .listNumber:
            // note new bullet type, restore current type after element
            let currentList = inside.intersection(.allLists)
            inside.remove(.allLists)
            inside.insert(element == .listBullet ? .listBullet : .listNumber)

            // redcarpet 'hmm', must have blank line iff not currently inside a list
            if currentList == .nothing {
                markdown += whitespace.newline()
            }
            whitespace.indent()
            elementDone = {
                self.inside.remove(.allLists)
                self.inside.insert(currentList)
                self.whitespace.outdent()
            }

        case .item:
            markdown += whitespace.listItemPrefix()
            if inside.contains(.listBullet) {
                markdown += "- "
            } else {
                markdown += "1. " // thankfully we can cheat here :)
            }
            // no indent for whatever is next, follows bullet directly
            whitespace.skipNext()
        }

        elementDoneStack.append(elementDone)
    }

    /// End of element - just process whatever was saved when the element opened.
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let elementDone = elementDoneStack.removeLast()
        elementDone?()
    }
    
    /// Text to pass through.  Stop redcarpet from interpreting any stuff as markdown formatting.
    private static let markdownCharsRegex: NSRegularExpression = {
        let markdownChars = "-_*+`.#"
        let escapedChars = NSRegularExpression.escapedPattern(for: markdownChars)
        return try! NSRegularExpression(pattern: "[\(escapedChars)]")
    }()

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        let regex = XMLToMarkdown.markdownCharsRegex
        markdown += regex.stringByReplacingMatches(in: string, range: string.nsRange, withTemplate: "\\\\$0")
    }

    /// CDATA.  Used for html, stuff that looks like html, each line of a code block.
    /// Headings and HR in markdown end up as HTML rather than tags.
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let cdataString = String(data: CDATABlock, encoding: .utf8) else {
            errorHandler?("Can't decode CDATA to UTF8 \(CDATABlock as NSData)")
            return
        }

        if inside.contains(.codeListing) {
            markdown += whitespace.prefix() + cdataString + "\n"
        } else if let imageLink = parseImageLink(html: cdataString) {
            markdown += imageLink
        } else if cdataString == "<hr/>" {
            markdown += "---"
        } else if let heading = parseHeading(html: cdataString) {
            markdown += heading
        } else {
            markdown += cdataString
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
    private static let headingTagRegex: NSRegularExpression =
        try! NSRegularExpression(pattern: "<(/)?h(\\d)>")

    private func parseHeading(html: String) -> String? {
        guard let matchedStrings = XMLToMarkdown.headingTagRegex.matches(in: html),
              let headingLevelString = matchedStrings[2],
              let headingLevel = Int(headingLevelString) else {
            return nil
        }

        // no newline after this html, kind of becomes inline...
        inside.insert(.htmlHeading)

        if matchedStrings[1] != nil {
            return ""
        } else {
            return String(repeating: "#", count: headingLevel) + " "
        }
    }
    
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        errorHandler?("XMLParserDelegate.parseErrorOccurred - \(parseError)")
    }
}
