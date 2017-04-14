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

public class XMLToMarkdown: NSObject, XMLParserDelegate {

    /// Keep track of indent from left margin to content-start
    /// This is not good enough wrt the width of the bullet-indents... will need a stack...
    enum Indent {
        case none
        case some(Int)

        private static let INDENT_WIDTH = 4

        func prefix() -> String {
            switch self {
            case .none: return ""
            case .some(let level): return String(repeating: " ", count: Indent.INDENT_WIDTH * level)
            }
        }

        mutating func inc() {
            switch self {
            case .none: self = .some(1)
            case .some(let level): self = .some(level + 1)
            }
        }

        mutating func dec() {
            switch self {
            case .none: break
            case .some(1): self = .none
            case .some(let level): self = .some(level - 1)
            }
        }
    }

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
    }

    // Stuff that doesn't work in Xcode 8.1 markup although it is documented:
    // 1. Backslash at end of line causes hard linebreak.
    // 2. Smart ordered list items, ie. start with '4.' and it follows.
    //
    // Stuff hinted at https://github.com/apple/swift/blob/master/include/swift/Markup/ASTNodes.def
    // that isn't documented:
    // 1. BlockQuote

    /// Accumulated markdown
    private var output = ""

    /// Indent level (from lists)
    private var indent = Indent.none

    /// Are we in a CodeListing?
    private var inCodeListing = false

    /// Are we in a Para?
    private var inPara = false

    private func reset() {
        output = ""
        indent = .none
        inCodeListing = false
        inPara = false
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
        // Discussion - nop
        // Para - indent
        // emphasis - *
        // strong - **
        // CodeVoice - `
        // rawHTML - if inside para just skip else indent ready for stuff (can be block + inline element, grr)
        // CodeListing - ```(language) newline rules?, set flag, spaces for indent
        // zCodeLineNumbered - ignore, will do indent in cdata, see an extra set of these
        // Link - remember href and wait for end
        // List-Bullet - indent++, remember ul - extra newline if indent0 to avoid redcarpet confusion [more
        // List-Number - indent++, remember ol and ffs have to keep a stack of the counter...
        // Item - emit bullet, spaces for indent

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
            break
        case .emphasis:
            output += "*"
            elementDone = { self.output += "*" }
            break
        case .strong:
            output += "**"
            elementDone = { self.output += "**" }
            break
        case .codeVoice:
            output += "`"
            elementDone = { self.output += "`" }
            break
        case .para:
            output += indent.prefix()
            inPara = true
            elementDone = {
                self.output += "\n\n"
                self.inPara = false
            }
            break
        case .codeListing:
            output += indent.prefix() + "```" + (attributeDict["language"] ?? "") + "\n"
            inCodeListing = true
            elementDone = {
                self.output += self.indent.prefix() + "```\n\n"
                self.inCodeListing = false
            }
            break
        case .zCodeLineNumbered:
            break
        case .link:
            output += "["
            elementDone = {
                let href = attributeDict["href"] ?? ""
                self.output += "](\(href))"
            }
            break
        case .rawHTML:
            // Can be block or inline :(  If block then have to do indent + paragraphing.
            if !inPara {
                output += indent.prefix()
                elementDone = { self.output += "\n\n" }
            }
        }

        elementDoneStack.append(elementDone)
    }

    /// End of element - just process whatever was saved when the element opened.
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let elementDone = elementDoneStack.removeLast()
        elementDone?()
    }
    
    /// Text to pass through.
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        // TODO: regex help
        let markdownChars = "*+-_`.#"
        output += string.replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "`", with: "\\`")
    }
    
    /// CDATA.  Used for html, stuff that looks like html, each line of a code block.
    /// Headings and HR in markdown end up as HTML rather than tags.
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let cdataString = String(data: CDATABlock, encoding: .utf8) else {
            // TODO: error
            fatalError("CDATA is not utf8 \(CDATABlock as NSData)")
        }
        
        if inCodeListing {
            output += indent.prefix() + cdataString + "\n"
        } /* else if regex to catch <img src= alt= title=\> {
             }    else if "<hr/>" then "---"
             }    else if "<hx>" then some #
             }    else if "</hx>" then drop
         } */ else {
            output += cdataString
        }
    }
    
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // TODO: report
    }
}
