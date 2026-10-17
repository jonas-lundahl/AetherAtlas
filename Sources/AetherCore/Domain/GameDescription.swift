import Foundation

/// Native, sendable text runs derived from XIVAPI's formatted descriptions.
/// No HTML engine, resource loading, or phrase-based highlighting is involved.
public struct GameDescription: Sendable, Equatable {
  public struct RGBA: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
  }
  public struct Style: Sendable, Equatable {
    public var color: RGBA?
    public var bold = false
    public var italic = false
    public var underline = false
    public var strikethrough = false
  }
  public struct Run: Sendable, Equatable {
    public var text: String
    public let style: Style
  }
  public let runs: [Run]
  public var plainText: String { runs.map(\.text).joined() }
  public var isEmpty: Bool { runs.isEmpty }

  public init(plainText: String?, html: String?) {
    if let html, !html.isEmpty, let formatted = DescriptionParser.parse(html),
      !formatted.isEmpty
    {
      runs = formatted
    } else if let plainText, !plainText.isEmpty {
      runs = [Run(text: plainText, style: Style())]
    } else {
      runs = []
    }
  }
}

/// XIVAPI emits HTML fragments, so normalize its void line-break elements before
/// using the system XML parser. Unsupported/malformed markup uses the API's plain fallback.
private final class DescriptionParser: NSObject, XMLParserDelegate {
  private var styles = [GameDescription.Style()]
  private var runs: [GameDescription.Run] = []

  static func parse(_ html: String) -> [GameDescription.Run]? {
    guard html.utf8.count <= 65_536,
      !html.localizedCaseInsensitiveContains("<!DOCTYPE"),
      !html.localizedCaseInsensitiveContains("<!ENTITY")
    else { return nil }
    let normalized =
      html
      .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "<br/>", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: "&#160;")
    let parser = XMLParser(data: Data("<description>\(normalized)</description>".utf8))
    let delegate = DescriptionParser()
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else { return nil }
    return delegate.runs
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    guard styles.count < 32 else {
      parser.abortParsing()
      return
    }
    var style = styles.last ?? GameDescription.Style()
    switch elementName.lowercased() {
    case "description": break
    case "br": append("\n")
    case "span":
      if let declaration = attributeDict["style"] {
        for part in declaration.split(separator: ";") {
          let pair = part.split(separator: ":", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          }
          guard pair.count == 2 else { continue }
          switch pair[0] {
          case "color":
            guard let color = Self.color(pair[1]) else {
              parser.abortParsing()
              return
            }
            style.color = color
          case "font-weight": style.bold = pair[1] == "bold" || pair[1] == "700"
          case "font-style": style.italic = pair[1] == "italic"
          case "text-decoration":
            style.underline = pair[1].contains("underline")
            style.strikethrough = pair[1].contains("line-through")
          default: break
          }
        }
      }
    case "b", "strong": style.bold = true
    case "i", "em": style.italic = true
    case "u": style.underline = true
    case "s", "strike", "del": style.strikethrough = true
    default:
      parser.abortParsing()
      return
    }
    styles.append(style)
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if styles.count > 1 { styles.removeLast() }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }

  func parser(_ parser: XMLParser, foundCDATA _: Data) { parser.abortParsing() }

  private func append(_ text: String) {
    guard !text.isEmpty else { return }
    let style = styles.last ?? GameDescription.Style()
    if let last = runs.last, last.style == style {
      runs[runs.count - 1].text += text
    } else {
      runs.append(GameDescription.Run(text: text, style: style))
    }
  }

  private static func color(_ input: String) -> GameDescription.RGBA? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#"), value.count == 7, let hex = UInt32(value.dropFirst(), radix: 16) {
      return GameDescription.RGBA(
        red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
        blue: Double(hex & 255) / 255, alpha: 1)
    }
    let rgba = value.hasPrefix("rgba(")
    guard rgba || value.hasPrefix("rgb("), value.hasSuffix(")") else { return nil }
    let parts = value.dropFirst(rgba ? 5 : 4).dropLast().split(
      separator: ",", omittingEmptySubsequences: false)
    let numbers = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == (rgba ? 4 : 3), numbers.count == parts.count,
      numbers.allSatisfy(\.isFinite),
      numbers.prefix(3).allSatisfy({ (0...255).contains($0) }),
      !rgba || (0...1).contains(numbers[3])
    else { return nil }
    return GameDescription.RGBA(
      red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255,
      alpha: rgba ? numbers[3] : 1)
  }
}
