//
//  XMLDeclarationTests.swift
//  XMLToMarkdown
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
@testable import XMLToMarkdown

// Very quick + dirty.  Emphasis is on pulling out the xml pieces not formatting markdown.

extension XMLDeclaration.Parameter: Equatable {
    public static func ==(lhs: XMLDeclaration.Parameter, rhs: XMLDeclaration.Parameter) -> Bool {
        return lhs.name == rhs.name && lhs.discussion == rhs.discussion
    }
}

extension XMLDeclaration: Equatable {
    public static func ==(lhs: XMLDeclaration, rhs: XMLDeclaration) -> Bool {
        return lhs.file == rhs.file &&
        lhs.line == rhs.line &&
        lhs.column == rhs.column &&
        lhs.type == rhs.type &&
        lhs.name == rhs.name &&
        lhs.usr == rhs.usr &&
        lhs.declaration == rhs.declaration &&
        lhs.resultDiscussion == rhs.resultDiscussion &&
        lhs.parameters == rhs.parameters
    }
}

class XMLDeclarationTests: XCTestCase {

    static let decls = [ "class AClass",
                         "let property: String",
                         "func func1()",
                         "func func2(name param: Int)",
                         "func func2a(name param: Int, param2: String)",
                         "func func3() -> Int",
                         "func func4(param: Int) -> Int"]

    static let xmls = ["<Class file=\"/Users/johnf/project/BJ/BJ/BJ.swift\" line=\"14\" column=\"7\"><Name>AClass</Name><USR>s:C10BJ6AClass</USR><Declaration>class AClass</Declaration><Abstract><Para>This is a class</Para></Abstract><Discussion><Para>It has some description</Para><Attention><Para>don’t get distracted</Para></Attention></Discussion></Class>",
    "<Other file=\"/Users/johnf/project/BJ/BJ/BJ.swift\" line=\"17\" column=\"9\"><Name>property</Name><USR>s:vC10BJ6AClass8propertySS</USR><Declaration>let property: String</Declaration><Abstract><Para>A property</Para></Abstract></Other>",
    "<Function file=\"/Users/johnf/project/BJ/BJ/BJ.swift\" line=\"20\" column=\"10\"><Name>func1()</Name><USR>s:FC10BJ6AClass5func1FT_T_</USR><Declaration>func func1()</Declaration><Abstract><Para>A function with no parameters or return</Para></Abstract></Function>",
    "<Function file=\"/Users/johnf/project/BJ/BJ/BJ.swift\" line=\"26\" column=\"10\"><Name>func2(name:)</Name><USR>s:FC10BJ6AClass5func2FT4nameSi_T_</USR><Declaration>func func2(name param: Int)</Declaration><Abstract><Para>A function with one parameter</Para></Abstract><Parameters><Parameter><Name>param</Name><Direction isExplicit=\"0\">in</Direction><Discussion><Para>The first parameter</Para></Discussion></Parameter></Parameters></Function>",
    "<Function file=\"/Users/johnf/project/BJ/BJ/BJ.swift\" line=\"34\" column=\"10\"><Name>func2a(name:param2:)</Name><USR>s:FC10BJ6AClass6func2aFT4nameSi6param2SS_T_</USR><Declaration>func func2a(name param: Int, param2: String)</Declaration><Abstract><Para>A function with multiple parameters</Para></Abstract><Parameters><Parameter><Name>param</Name><Direction isExplicit=\"0\">in</Direction><Discussion><Para>first param</Para></Discussion></Parameter><Parameter><Name>param2</Name><Direction isExplicit=\"0\">in</Direction><Discussion><Para>second param</Para></Discussion></Parameter></Parameters></Function>",
    "<Function file=\"/Users/johnf/project/BJ/BJ/BJ.swift\" line=\"40\" column=\"10\"><Name>func3()</Name><USR>s:FC10BJ6AClass5func3FT_Si</USR><Declaration>func func3() -&gt; Int</Declaration><Abstract><Para>A function with a return value</Para></Abstract><ResultDiscussion><Para>Something exciting</Para></ResultDiscussion></Function>",
    "<Function file=\"/Users/johnf/project/BJ/BJ/BJ.swift\" line=\"51\" column=\"10\"><Name>func4(param:)</Name><USR>s:FC10BJ6AClass5func4FT5paramSi_Si</USR><Declaration>func func4(param: Int) -&gt; Int</Declaration><Abstract><Para>Function with parameter and return</Para></Abstract><Parameters><Parameter><Name>param</Name><Direction isExplicit=\"0\">in</Direction><Discussion><Para>a value</Para></Discussion></Parameter></Parameters><ResultDiscussion><Para>Some text with <emphasis>formatting</emphasis> and</Para><List-Bullet><Item><Para>A sublist of explanations</Para></Item><Item><Para>More things.</Para></Item></List-Bullet></ResultDiscussion></Function>"]

    func testCanExtractDecls() {
        for (expectedDeclaration, xml) in zip(XMLDeclarationTests.decls, XMLDeclarationTests.xmls) {
            guard let actualDeclaration = XMLDeclaration.getDeclarationOnly(from: xml) else {
                XCTFail("Declaration extract failed for \(xml)")
                continue
            }
            XCTAssertEqual(actualDeclaration, expectedDeclaration)
        }
    }

    static let classDecl = XMLDeclaration(file: "/Users/johnf/project/BJ/BJ/BJ.swift", line: 14, column: 7,
                                          type: "Class", name: "AClass", usr: "s:C10BJ6AClass",
                                          declaration: "class AClass",
                                          resultDiscussion: nil,
                                          parameters: [])

    static let propertyDecl = XMLDeclaration(file: "/Users/johnf/project/BJ/BJ/BJ.swift", line: 17, column: 9,
                                             type: "Other", name: "property", usr: "s:vC10BJ6AClass8propertySS",
                                             declaration: "let property: String",
                                             resultDiscussion: nil,
                                             parameters: [])

    static let func1Decl = XMLDeclaration(file: "/Users/johnf/project/BJ/BJ/BJ.swift", line: 20, column: 10,
                                          type: "Function", name: "func1()", usr: "s:FC10BJ6AClass5func1FT_T_",
                                          declaration: "func func1()",
                                          resultDiscussion: nil,
                                          parameters: [])

    static let func2Decl = XMLDeclaration(file: "/Users/johnf/project/BJ/BJ/BJ.swift", line: 26, column: 10,
                                          type: "Function", name: "func2(name:)", usr: "s:FC10BJ6AClass5func2FT4nameSi_T_",
                                          declaration: "func func2(name param: Int)",
                                          resultDiscussion: nil,
                                          parameters: [ XMLDeclaration.Parameter(name: "param", discussion: "The first parameter")])

    static let func2aDecl = XMLDeclaration(file: "/Users/johnf/project/BJ/BJ/BJ.swift", line: 34, column: 10,
                                           type: "Function", name: "func2a(name:param2:)", usr: "s:FC10BJ6AClass6func2aFT4nameSi6param2SS_T_",
                                           declaration: "func func2a(name param: Int, param2: String)",
                                           resultDiscussion: nil,
                                           parameters: [ XMLDeclaration.Parameter(name: "param", discussion: "first param"),
                                                         XMLDeclaration.Parameter(name: "param2", discussion: "second param")])

    static let func3Decl = XMLDeclaration(file: "/Users/johnf/project/BJ/BJ/BJ.swift", line: 40, column: 10,
                                          type: "Function", name: "func3()", usr: "s:FC10BJ6AClass5func3FT_Si",
                                          declaration: "func func3() -> Int",
                                          resultDiscussion: "Something exciting",
                                          parameters: [])

    static let func4Decl = XMLDeclaration(file: "/Users/johnf/project/BJ/BJ/BJ.swift", line: 51, column: 10,
                                          type: "Function", name: "func4(param:)", usr: "s:FC10BJ6AClass5func4FT5paramSi_Si",
                                          declaration: "func func4(param: Int) -> Int",
                                          resultDiscussion: "Some text with *formatting* and\n" +
                                                            "\n" +
                                                            "- A sublist of explanations\n" +
                                                            "- More things\\.",
                                          parameters: [ XMLDeclaration.Parameter(name: "param", discussion: "a value")])

    static let allDecls = [ classDecl,
                            propertyDecl,
                            func1Decl,
                            func2Decl,
                            func2aDecl,
                            func3Decl,
                            func4Decl]

    func testCanParseDecls() {
        for (expectedDeclaration, xml) in zip(XMLDeclarationTests.allDecls, XMLDeclarationTests.xmls) {
            let actualDeclaration = XMLDeclaration.build(from: xml)
            XCTAssertEqual(actualDeclaration, expectedDeclaration)
        }
    }
}
