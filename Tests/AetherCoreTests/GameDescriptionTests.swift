import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  import SwiftUI
  @testable import AetherAtlas
#endif

@Test func sprintFixturePreservesTextAndGameColors() throws {
  let envelope = try XIVAPIClient.decode(DetailEnvelope.self, from: fixture("sprint"))
  let detail = EntityDetail(
    entity: envelope.row.summary(kind: .action), row: envelope.row,
    schema: envelope.schema, version: envelope.version, isStale: false)
  let description = detail.description
  #expect(description.plainText == envelope.transient?["Description"]?.string)
  let green = GameDescription.RGBA(red: 0, green: 0.8, blue: 34.0 / 255, alpha: 1)
  let yellow = GameDescription.RGBA(red: 1, green: 1, blue: 102.0 / 255, alpha: 1)
  #expect(
    description.runs.filter { $0.style.color == green }.map(\.text) == [
      "Duration:", "Additional Effect:", "Jog Effect:",
    ])
  #expect(description.runs.filter { $0.style.color == yellow }.map(\.text) == ["Jog"])
  #expect(description.runs.first?.style.color == nil)
  #expect(description.runs.last?.style.color == nil)
}

@Test func formattedDescriptionPreservesBreaksEntitiesAndUnicode() {
  let description = GameDescription(
    plainText: nil,
    html: "A &amp; B<br>C &lt; D<BR />&#9733;&nbsp;\u{e070}<br/>last")
  #expect(description.plainText == "A & B\nC < D\n★\u{a0}\u{e070}\nlast")
  #expect(!description.plainText.contains("<br"))
}

@Test func nestedStylesRestoreOuterColorAndEmphasis() throws {
  let description = GameDescription(
    plainText: nil,
    html:
      #"<span style="color:rgba(0,204,34,1)">green <b>bold <i>both</i></b><span style="color:#ffff66">yellow</span> green</span> plain <u>under</u><s>strike</s>"#
  )
  let both = try #require(description.runs.first { $0.text == "both" })
  #expect(both.style.bold && both.style.italic)
  #expect(both.style.color?.green == 0.8)
  let afterNested = try #require(description.runs.first { $0.text == " green" })
  #expect(afterNested.style.color?.red == 0)
  #expect(!afterNested.style.bold && !afterNested.style.italic)
  #expect(description.runs.first { $0.text == " plain " }?.style.color == nil)
  #expect(description.runs.first { $0.text == "under" }?.style.underline == true)
  #expect(description.runs.first { $0.text == "strike" }?.style.strikethrough == true)
}

@Test func rgbaAlphaAndCSSStylesArePreserved() throws {
  let description = GameDescription(
    plainText: nil,
    html:
      #"<span style="color:rgba(12,34,56,0.5);font-weight:bold;font-style:italic;text-decoration:underline line-through">effect</span>"#
  )
  let style = try #require(description.runs.first?.style)
  #expect(style.color?.alpha == 0.5)
  #expect(style.color?.red == 12.0 / 255)
  #expect(style.bold && style.italic && style.underline && style.strikethrough)
  #expect(
    GameDescription(plainText: nil, html: #"<span style="color:rgb(12,34,56)">rgb</span>"#).runs
      .first?.style.color?.alpha == 1)
}

@Test(arguments: [
  #"<span style="color:rgba(0,204,34,1)">unfinished"#,
  #"<span style="color:rgba(999,0,0,1)">bad color</span>"#,
  #"<span style="color:rgba(0,204,34,1,garbage)">bad color</span>"#,
  #"<span style="color:rgba(nan,0,0,1)">bad color</span>"#,
  #"<img src="https://fixture.invalid/image.png"/>"#,
  #"<script>bad()</script>"#,
  "before<![CDATA[unsupported]]>after",
  #"<!DOCTYPE description [<!ENTITY test SYSTEM "https://fixture.invalid/data">]>&test;"#,
  String(repeating: "<span>", count: 40) + "deep" + String(repeating: "</span>", count: 40),
  String(repeating: "x", count: 65_537),
]) func unsupportedOrMalformedHTMLUsesPlainFallback(html: String) {
  let description = GameDescription(plainText: "Safe original text", html: html)
  #expect(description.plainText == "Safe original text")
  #expect(description.runs.count == 1)
  #expect(description.runs.first?.style == GameDescription.Style())
}

@Test func missingHTMLAndEmptyDescriptionsRemainUsable() {
  #expect(
    GameDescription(plainText: "Cached plain text", html: nil).plainText == "Cached plain text")
  #expect(GameDescription(plainText: "Fallback", html: "").plainText == "Fallback")
  #expect(GameDescription(plainText: "Fallback", html: "<span></span>").plainText == "Fallback")
  #expect(GameDescription(plainText: nil, html: nil).isEmpty)
  #expect(GameDescription(plainText: nil, html: "<broken>").isEmpty)
}

@Test func detailRequestsIncludeBothFormattedAndFallbackFields() throws {
  let action = try APIRequest.detail(EntityID(kind: .action, row: 3)).url()
  let parameters = try #require(
    URLComponents(url: action, resolvingAgainstBaseURL: false)?.queryItems)
  #expect(parameters.first { $0.name == "transient" }?.value == "Description,Description@as(html)")
  let item = try APIRequest.detail(EntityID(kind: .item, row: 44104)).url()
  let fields = try #require(
    URLComponents(url: item, resolvingAgainstBaseURL: false)?.queryItems?.first {
      $0.name == "fields"
    }?.value)
  #expect(fields.split(separator: ",").contains("Description"))
  #expect(fields.split(separator: ",").contains("Description@as(html)"))
}

@Test func itemDescriptionUsesTheSameNativeRichTextModel() {
  let row = SheetRow(
    rowID: 1,
    fields: [
      "Description": .string("EXP Bonus: +3%"),
      "Description@as(html)": .string(
        #"<span style="color:rgba(0,204,34,1)">EXP Bonus:</span> +3%"#),
    ])
  let detail = EntityDetail(
    entity: EntitySummary(id: EntityID(kind: .item, row: 1), name: "Food"), row: row,
    schema: nil, version: nil, isStale: true)
  #expect(detail.description.plainText == "EXP Bonus: +3%")
  #expect(detail.description.runs.first?.style.color?.green == 0.8)
}

#if !SWIFT_PACKAGE
  @Test @MainActor func nativeAttributedTextPreservesAPIStyling() throws {
    let description = GameDescription(
      plainText: nil,
      html: #"<span style="color:rgba(0,204,34,1)"><b><i><u>Effect</u></i></b></span> plain"#)
    let attributed = GameDescriptionText.attributed(description, colorScheme: .dark)
    #expect(String(attributed.characters) == "Effect plain")
    let first = try #require(attributed.runs.first)
    #expect(first.foregroundColor == Color(.sRGB, red: 0, green: 0.8, blue: 34.0 / 255, opacity: 1))
    #expect(first.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    #expect(first.inlinePresentationIntent?.contains(.emphasized) == true)
    #expect(first.underlineStyle != nil)
    #expect(attributed.runs.last?.foregroundColor == nil)
  }

  @Test @MainActor func gameHighlightColorsRemainReadableInLightAppearance() {
    let original = GameDescription.RGBA(red: 1, green: 1, blue: 0.4, alpha: 1)
    let light = GameDescriptionText.readable(original, colorScheme: .light)
    #expect(light.red < original.red && light.green < original.green)
    #expect(abs(light.blue / light.red - 0.4) < 0.0001)
    #expect(GameDescriptionText.readable(original, colorScheme: .dark) == original)
  }
#endif
