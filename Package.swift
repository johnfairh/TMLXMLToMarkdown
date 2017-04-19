// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "TMLXMLToMarkdown",
    targets: [
        Target(name: "xmltoredcarpet", dependencies: ["TMLXMLToMarkdown"])
    ]
)
