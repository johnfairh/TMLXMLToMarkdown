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

	/// Accumulated markdown
	private var output = ""

	/// Indent level (from lists)
	private var indent = Indent.none

	/// Are we in a CodeListing?
	private var inCodeListing = false

	/// Are we in a Para?
	private var inPara = false

	/// Current Link href
	private var inLinkWithHRef: String? = nil

	private func reset() {
		output = ""
		indent = .none
		inCodeListing = false
		inLinkWithHRef = nil
		inPara = false
	}

	/// Create a new SourceKit XML converter.
	public override init() {
	}

	/// Convert SourceKit XML to Redcarpet markdown
	///
	/// - Parameter xml: SourceKit XML
	/// - Returns: Markdown version of the XML.  Empty string on any failure.
	public func convert(xml: String) -> String {
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

		return output.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
		// Discussion - nop
		// Para - indent
		// emphasis - *
		// strong - **
		// CodeVoice - `
		// rawHTML - if inside para just skip else indent ready for stuff (can be block + inline element, grr)
		// CodeListing - ```(language) newline rules?, set flag, spaces for indent
		// zCodeLineNumbered - ignore, will do indent in cdata, see an extra set of these
		// Link - remember href and wait for end?
		// List-Bullet - indent++, remember ul - extra newline if indent0 to avoid redcarpet confusion [more
		// List-Number - indent++, remember ol and ffs have to keep a stack of the counter...
		// Item - emit bullet, spaces for indent

		guard let element = Element(rawValue: elementName) else {
			// TODO: warning unknown element
			return
		}

		switch element {
		case .discussion:
			// OK
			break
		case .emphasis:
			output += "*"
			break
		case .strong:
			output += "**"
			break
		case .codeVoice:
			output += "`"
			break
		case .para:
			output += indent.prefix()
			inPara = true
			break
		case .codeListing:
			output += indent.prefix() + "```" + (attributeDict["language"] ?? "") + "\n"
			inCodeListing = true
			break
		case .zCodeLineNumbered:
			break
		case .link:
			output += "["
			inLinkWithHRef = attributeDict["href"] ?? ""
			break
		case .rawHTML:
			if !inPara { // this can be both block + inline.  If block then we have to do the indent.
				output += indent.prefix()
			}
		}
	}

	public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
		guard let element = Element(rawValue: elementName) else {
			// TODO: warning unknown element
			return
		}

		switch element {
		case .discussion:
			// OK
			break
		case .emphasis:
			output += "*"
			break
		case .strong:
			output += "**"
			break
		case .codeVoice:
			output += "`"
			break
		case .para:
			output += "\n\n"
			inPara = false
			break
		case .codeListing:
			output += indent.prefix() + "```" + "\n\n"
			inCodeListing = false
			break
		case .zCodeLineNumbered:
			break
		case .link:
			output += "](\(inLinkWithHRef!))"
			inLinkWithHRef = nil
			break
		case .rawHTML:
			if !inPara { // as above, if we are block we have to end the block.
				output += "\n\n"
			}
		}
	}

	/// Text to pass through.
	public func parser(_ parser: XMLParser, foundCharacters string: String) {
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
	}
}
