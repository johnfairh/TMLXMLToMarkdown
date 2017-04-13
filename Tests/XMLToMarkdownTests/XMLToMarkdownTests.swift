//
//  XMLToMarkdownTests.swift
//  XMLToMarkdownTests
//
//  Distributed under the ISC license, see LICENSE.
//

import XCTest

class XMLToMarkdownTests: XCTestCase {

	private func issueTest(_ xml: String, _ expectMarkdown: String) {
		let parser = XMLToMarkdown()
		let actualMarkdown = parser.convert(xml: xml)
		XCTAssertEqual(actualMarkdown, expectMarkdown)
	}
    
	func testSimplePara() {
		let str = "Some text"
		issueTest("<Para>\(str)</Para>", str)
	}

	func testMultiplePara() {
		let str1 = "Some text"
		let str2 = "Some more text"
		issueTest("<Discussion><Para>\(str1)</Para><Para>\(str2)</Para></Discussion>", "\(str1)\n\n\(str2)")
	}

	func testEmphasis() {
		let str = "Emphasised"
		issueTest("<Para><emphasis>\(str)</emphasis></Para>", "*\(str)*")
	}

	func testStrong() {
		let str = "Strong"
		issueTest("<Para><strong>\(str)</strong></Para>", "**\(str)**")
	}

	func testFixed() {
		let str = "Fixed"
		issueTest("<Para><codeVoice>\(str)</codeVoice></Para>", "`\(str)`")
	}

	func testEscapes() {
		let xmlStr = "`Str` __with__ *inside* it"
		let mdStr  = "\\`Str\\` \\_\\_with\\_\\_ \\*inside\\* it"
		issueTest("<Para>\(xmlStr)</Para>", mdStr)
	}

	func testSimpleCodeBlock() {
		let code = "   This is code"
		issueTest("<CodeListing><![CDATA[\(code)]]></CodeListing>", "```\n\(code)\n```")
	}

	func testLingualCodeBlock() {
		let code = "   This is code"
		let language = "esperanto"
		issueTest("<CodeListing language=\"\(language)\"><![CDATA[\(code)]]></CodeListing>", "```\(language)\n\(code)\n```")
	}

	func testActualCodeBlock() {
	    let code1 = "   This is code"
		let code2 = "This is line2"
		let language = "swift"

		issueTest(
			"<Document><CodeListing language=\"\(language)\">" +
			"<zCodeLineNumbered><![CDATA[\(code1)]]></zCodeLineNumbered>" +
			"<zCodeLineNumbered><![CDATA[\(code2)]]></zCodeLineNumbered>" +
			"</CodeListing></Document>",
			"```\(language)\n" +
			"\(code1)\n" +
			"\(code2)\n" +
			"```")
	}

	func testInlineHTML() {
		let text1 = "I like "
		let html1 = "<span style=\"fishy\">"
		let text2 = "plaice"
		let html2 = "</span>"

		issueTest(
			"<Para>\(text1)" +
			"<rawHTML><![CDATA[\(html1)]]></rawHTML>" +
			"\(text2)" +
			"<rawHTML><![CDATA[\(html2)]]></rawHTML>" +
			"</Para>",
			"\(text1)\(html1)\(text2)\(html2)")
	}

	func testBlockHTML() {
		let para1 = "Normal text"
		let html  = "<div>Unusual area</div>"
		let para2 = "More normal text"

		issueTest(
			"<Discussion>" +
			"<Para>\(para1)</Para>" +
			"<rawHTML><![CDATA[\(html)]]></rawHTML>" +
			"<Para>\(para2)</Para>" +
			"</Discussion>",
			"\(para1)\n" +
			"\n" +
			"\(html)\n" +
			"\n" +
			"\(para2)")
	}

	func testLink() {
		let text = "This is text"
		let link = "http://example.com"
		issueTest(
			"<Link href=\"\(link)\">\(text)</Link>",
			"[\(text)](\(link))")
	}

	func testSimpleBullets() { // custom list numbering, change lists on bullet type
		XCTFail()
	}

	func testNestedBullets() {
		XCTFail()
	}

	func testNestedParas() {
		XCTFail()
	}

	func testNestedCodeBlock() {
		XCTFail()
	}

	func testUnknownElement() {
		XCTFail()
	}

	// blockquote, header, hrule, escape of emph chars in straight text
}
