//
//  main.swift
//  XmlToMarkdown
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation

//
// CLI driver
//

let xmlToMarkdown = XMLToMarkdown() { str in
    print("ERROR: \(str)")
}

func doParse(xml: String) {
    xmlToMarkdown.startMarkdown()
    xmlToMarkdown.parse(xml: xml)
    print(xmlToMarkdown.endMarkdown())
}

if CommandLine.arguments.count > 1 {
    CommandLine.arguments.suffix(from: 1).forEach { file in
        guard let data = FileManager.default.contents(atPath: file) else {
            print("Can't open file \(file)")
            return
        }

        guard let xml = String(bytes: data, encoding: .utf8) else {
            print("Can't get contents straight for \(file)")
            return
        }

        doParse(xml: xml)
    }
} else {
    var xml = ""
    while let line = readLine() {
        xml += line
    }
    doParse(xml: xml)
}
