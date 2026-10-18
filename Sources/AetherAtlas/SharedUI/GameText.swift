import CoreText
import Observation
import SwiftUI

/// A private font descriptor keeps the font inside this app without installing it
/// or exposing it in system font pickers.
struct GameSymbolFont: Sendable {
  static let name = "XIVAXISStdATK-Regular"
  private let base: Font
  let characters: Set<UInt32>

  private static func nativeFont(_ data: Data) -> CTFont? {
    let descriptors =
      CTFontManagerCreateFontDescriptorsFromData(data as CFData)
      as! [CTFontDescriptor]
    guard descriptors.count == 1, let descriptor = descriptors.first else { return nil }
    let font = CTFontCreateWithFontDescriptor(descriptor, 13, nil)
    guard CTFontCopyPostScriptName(font) as String == name else { return nil }
    var character: UniChar = 0xE0BF
    var glyph: CGGlyph = 0
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), glyph != 0 else { return nil }
    return font
  }

  static func validate(_ data: Data) -> Bool { nativeFont(data) != nil }

  init?(_ data: Data) {
    guard let native = Self.nativeFont(data) else { return nil }
    base = Font(native)
    let characters = Array(UInt16(0xE000)...UInt16(0xF8FF))
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    _ = CTFontGetGlyphsForCharacters(native, characters, &glyphs, characters.count)
    self.characters = Set(zip(characters, glyphs).compactMap { $1 == 0 ? nil : UInt32($0) })
  }

  func font(size: CGFloat, context: Font.Context) -> Font {
    Font(CTFontCreateCopyWithAttributes(base.resolve(in: context).ctFont, size, nil, nil))
  }
}

@MainActor @Observable final class GameSymbolFontStore {
  private let cache: SymbolFontCache
  private var started = false
  private(set) var font: GameSymbolFont?

  init(cache: SymbolFontCache) { self.cache = cache }

  func load() async {
    guard !started else { return }
    started = true
    if let data = await cache.data() { font = GameSymbolFont(data) }
  }
}

private struct GameSymbolFontKey: EnvironmentKey {
  static let defaultValue: GameSymbolFont? = nil
}

extension EnvironmentValues {
  var gameSymbolFont: GameSymbolFont? {
    get { self[GameSymbolFontKey.self] }
    set { self[GameSymbolFontKey.self] = newValue }
  }
}

/// Overrides only glyphs the downloaded font actually supports. Everything else
/// keeps its existing native font, language, color, emphasis, and selectable text.
struct GameText: View {
  private let content: AttributedString
  @Environment(\.font) private var font
  @Environment(\.fontResolutionContext) private var fontContext
  @Environment(\.gameSymbolFont) private var symbolFont

  init(_ text: String) { content = AttributedString(text) }
  init(_ text: AttributedString) { content = text }

  var body: some View {
    if let symbolFont {
      Text(
        Self.attributed(
          content, characters: symbolFont.characters,
          font: symbolFont.font(
            size: (font ?? .body).resolve(in: fontContext).pointSize, context: fontContext)))
    } else {
      Text(content)
    }
  }

  static func attributed(_ source: AttributedString, characters: Set<UInt32>, font: Font)
    -> AttributedString
  {
    guard !characters.isEmpty else { return source }
    var result = source
    for index in source.unicodeScalars.indices {
      let scalar = source.unicodeScalars[index]
      guard characters.contains(scalar.value) else { continue }
      let end = source.unicodeScalars.index(after: index)
      result[index..<end].font = font
    }
    return result
  }
}
