This framework provides an APIs for converting an XML document created by
SourceKit that describes the documentation comment of a Swift declaration to
markdown that is correctly parsed by redcarpet.

It seemed like a good idea at the time in order to improve Jazzy -- but then I
learnt about Objective C and how irretreivably incompatible its doc comments
are.

Maybe it will be useful one day!

### Usage

```swift
import TMLXMLToMarkdown

let markdown = XMLDeclaration.build(from: xml)
```

### Installation

Swift package manager:

    .Package(url: "https://github.com/johnfairh/TMLXMLToMarkdown", majorVersion: 1)

### License

Distributed under the MIT license.
