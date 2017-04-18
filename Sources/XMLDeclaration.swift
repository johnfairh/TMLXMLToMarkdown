//
//  XMLDeclaration.swift
//  XMLToMarkdown
//
//  Distributed under the ISC license, see LICENSE.
//

import Foundation

/// The contents of SourceKit XML for a declaration.
/// 'Discussion' fields are markdown; others are not.
///
/// Picking out only the fields currently needed in sourcekitten.
public struct XMLDeclaration {
    var file: String?
    var line: Int64?
    var column: Int64?
    var type: String?
    var name: String?
    var usr: String?
    var declaration: String?
    var resultDiscussion: String?
    var parameters: [Parameter] = []

    struct Parameter {
        var name: String
        var discussion: String?
    }
}

// MARK: XMLDeclarationBuilder

/// Class to manage + direct parsing of a declaration XML to produce
/// an entire `XMLDeclaration`.  Sits on top of an `XMLToMarkdown` which
/// does the lower-level text processing.
/// Understands the structure of the XML document.
final class XMLDeclarationBuilder: XMLToMarkdownClient {

    /// XML element names we recognize
    enum Element: String {
        case name             = "Name"
        case usr              = "USR"
        case declaration      = "Declaration"
        case discussion       = "Discussion"
        case parameter        = "Parameter"
        case resultDiscussion = "ResultDiscussion"
    }

    /// The declaration being filled in
    var declaration = XMLDeclaration()

    /// Parameter handling
    var parameter: XMLDeclaration.Parameter?

    /// Notification from the parser of a structural element
    func didStartElement(_ name: String,
                         attributes: [String : String],
                         parser: XMLToMarkdown) -> XMLToMarkdown.ElementDone? {

        // Use the outer element as the 'type' whatever that happens to be (eg. "Function")
        if declaration.type == nil {
            declaration.type   = name
            declaration.file   = attributes["file"]
            declaration.line   = attributes["line"].flatMap { Int64($0) }
            declaration.column = attributes["column"].flatMap { Int64($0) }
        }

        guard let element = Element(rawValue: name) else {
            return nil
        }

        let elementDone: XMLToMarkdown.ElementDone?

        switch element {
        case .usr:
            parser.startText()
            elementDone = { self.declaration.usr = parser.endText() }

        case .declaration:
            parser.startText()
            elementDone = { self.declaration.declaration = parser.endText() }

        case .parameter:
            parameter = XMLDeclaration.Parameter(name: "", discussion: nil)
            elementDone = {
                self.declaration.parameters.append(self.parameter!)
                self.parameter = nil
            }

        case .name:
            parser.startText()
            elementDone = {
                let text = parser.endText()
                if self.parameter != nil {
                    self.parameter?.name = text
                } else {
                    self.declaration.name = text
                }
            }

        case .discussion:
            if self.parameter != nil {
                parser.startMarkdown()
                elementDone = {
                    let markdown = parser.endMarkdown()
                    self.parameter?.discussion = markdown
                }
            } else {
                // currently ignoring main 'discussion'
                elementDone = nil
            }

        case .resultDiscussion:
            parser.startMarkdown()
            elementDone = { self.declaration.resultDiscussion = parser.endMarkdown() }
        }

        return elementDone
    }
}

// MARK: XMLDeclarationExtracter

/// Class to manage + direct parsing of a declaration XML in order to
/// fish out just the 'declaration' element.
final class XMLDeclarationExtracter: XMLToMarkdownClient {

    /// The declaration being sought
    var declaration: String?

    /// Notification from the parser of a structural element
    func didStartElement(_ name: String,
                         attributes: [String : String],
                         parser: XMLToMarkdown) -> XMLToMarkdown.ElementDone? {

        guard name != XMLDeclarationBuilder.Element.declaration.rawValue else {
            return nil
        }

        parser.startText()
        return {
            self.declaration = parser.endText()
            parser.abort()
        }
    }
}

// MARK: Public APIs

extension XMLDeclaration {

    /// Take a SourceKit/Clang declaration XML document and extract its contents
    public static func build(from xml: String) -> XMLDeclaration {
        let builder = XMLDeclarationBuilder()
        let parser  = XMLToMarkdown()
        parser.parse(xml: xml, client: builder)
        return builder.declaration
    }

    /// Take a SourceKit/Clang declaration XML document and extract the 'Declaration' text
    public static func getDeclarationOnly(from xml: String) -> String? {
        let extracter = XMLDeclarationExtracter()
        let parser    = XMLToMarkdown()
        parser.parse(xml: xml, client: extracter)
        return extracter.declaration
    }
}
