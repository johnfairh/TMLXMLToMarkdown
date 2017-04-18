//
//  XmlToMarkdown.swift
//  XmlToMarkdown
//
//  Distributed under the ISC license, see LICENSE.
//
import Foundation

// MARK: XMLToMarkdownClient

public protocol XMLToMarkdownClient {
    /// Called at the start of an element not handled by the markdown parser.
    /// Any closure returned is called at the end of the element
    func didStartElement(_ name: String,
                         attributes: [String : String],
                         parser: XMLToMarkdown) -> XMLToMarkdown.ElementDone?
}

// MARK: XMLToMarkdown

public class XMLToMarkdown: NSObject, XMLParserDelegate {
    /// XML element names we recognize
    enum Element: String {
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
        static let plainText   = Inside(rawValue: 1<<5)

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

        mutating func reset() { indentLevel = 0; skip = false }

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

    /// Currently accumulated markdown/text
    private var output = ""

    /// Called by client to indicate a new markdown document is starting
    public func startMarkdown() {
        output = ""
        whitespace.reset()
        inside = .nothing
    }

    /// Called by client to retrieve the current parsed markdown
    public func endMarkdown() -> String {
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Called by client to start accumulating unadulterated text
    public func startText() {
        output = ""
        whitespace.reset()
        inside = .plainText
    }

    /// Called by client to retrieve current plain text
    public func endText() -> String {
        return output
    }

    /// Client element handler
    private var client: XMLToMarkdownClient? = nil

    /// Problem reporting
    public typealias ErrorHandler = (String) -> Void
    private let errorHandler: ErrorHandler?

    /// Create a new SourceKit XML parser.
    public init(errorHandler: ErrorHandler? = nil) {
        self.errorHandler = errorHandler
        super.init()
    }

    /// The actual foundation parser that does the work
    private var xmlParser: XMLParser?

    /// Convert SourceKit XML to Redcarpet markdown
    public func parse(xml: String, client: XMLToMarkdownClient? = nil) {
        elementDoneStack = []
        self.client = client

        if let xmlData = xml.data(using: .utf8) {
            let parser = XMLParser(data: xmlData)
            parser.delegate = self
            xmlParser = parser
            let success = parser.parse()
            if !success {
                if let parserError = parser.parserError {
                    errorHandler?("XMLParser.parse failed, parserError \(parserError))")
                } else {
                    errorHandler?("XMLParser.parser failed, no parserError")
                }
                errorHandler?("XML was \(xml), current output is \(output)")
                errorHandler?("Current line is \(parser.lineNumber) column is \(parser.columnNumber)")
            }
            xmlParser = nil
        }
        self.client = nil
    }

    /// Stop parsing elements immediately
    public func abort() {
        xmlParser?.abortParsing()
    }

    /// Stack of work to do as elements close
    public typealias ElementDone = () -> Void
    private var elementDoneStack: [ElementDone?] = []

    /// Spot interesting elements, do something + schedule more work for when the element ends.
    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String : String]) {

        guard let element = Element(rawValue: elementName) else {
            // Not a markdown element, let client handle it
            let clientElementDone = client?.didStartElement(elementName,
                                                            attributes: attributeDict,
                                                            parser: self) ?? nil
            elementDoneStack.append(clientElementDone)
            return
        }

        var elementDone: ElementDone? = nil

        switch element {
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
                self.output += "](\(href))" // apple markdown doesn't support a 'title' here...
            }

        case .para:
            output += whitespace.newlineAndPrefix()
            inside.insert(.para)
            elementDone = {
                self.output += "\n"
                self.inside.remove(.para)
            }

        case .codeListing:
            output += whitespace.newlineAndPrefix() + "```" + (attributeDict["language"] ?? "") + "\n"
            inside.insert(.codeListing)
            elementDone = {
                self.output += self.whitespace.prefix() + "```\n"
                self.inside.remove(.codeListing)
            }
        case .zCodeLineNumbered:
            break

        case .rawHTML:
            // Can be block or inline :(  If block then have to do indent + paragraphing.
            if !inside.contains(.para) {
                output += whitespace.newlineAndPrefix()
                elementDone = {
                    if !self.inside.contains(.htmlHeading) {
                        self.output += "\n"
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
                output += whitespace.newline()
            }
            whitespace.indent()
            elementDone = {
                self.inside.remove(.allLists)
                self.inside.insert(currentList)
                self.whitespace.outdent()
            }

        case .item:
            output += whitespace.listItemPrefix()
            if inside.contains(.listBullet) {
                output += "- "
            } else {
                output += "1. " // thankfully we can cheat here :)
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
        if inside.contains(.plainText) {
            output += string
        } else {
            let regex = XMLToMarkdown.markdownCharsRegex
            output += regex.stringByReplacingMatches(in: string, range: string.nsRange, withTemplate: "\\\\$0")
        }
    }

    /// CDATA.  Used for html, stuff that looks like html, each line of a code block.
    /// Headings and HR in markdown end up as HTML rather than tags.
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let cdataString = String(data: CDATABlock, encoding: .utf8) else {
            errorHandler?("Can't decode CDATA to UTF8 \(CDATABlock as NSData)")
            return
        }

        if inside.contains(.codeListing) {
            output += whitespace.prefix() + cdataString + "\n"
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
