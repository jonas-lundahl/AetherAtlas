import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  @testable import AetherAtlas
#endif

@Test(arguments: GameLanguage.allCases)
func gameLanguageFormatsGroupedIntegers(language: GameLanguage) {
  let expected: String
  let maximum: String
  switch language {
  case .english, .japanese:
    expected = "1,234,567"
    maximum = "9,223,372,036,854,775,807"
  case .german:
    expected = "1.234.567"
    maximum = "9.223.372.036.854.775.807"
  case .french:
    expected = "1\u{202F}234\u{202F}567"
    maximum = "9\u{202F}223\u{202F}372\u{202F}036\u{202F}854\u{202F}775\u{202F}807"
  }
  #expect(language.formatNumber(1_234_567) == expected)
  #expect(language.formatNumber(-1_234_567) == "-" + expected)
  #expect(language.formatNumber(Int.max) == maximum)
  #expect(language.formatNumber(0) == "0")
  #expect(language.formatNumber(100) == "100")
}

@Test(arguments: GameLanguage.allCases)
func gameLanguageFormatsDecimalTimingsWithFixedPrecision(language: GameLanguage) {
  let decimal = language == .french || language == .german ? "," : "."
  let grouped: String
  switch language {
  case .english, .japanese: grouped = "1,234.5"
  case .german: grouped = "1.234,5"
  case .french: grouped = "1\u{202F}234,5"
  }
  #expect(language.formatNumber(1_234.5, fractionDigits: 1) == grouped)
  #expect(language.formatNumber(2.5, fractionDigits: 1) == "2\(decimal)5")
  #expect(language.formatNumber(60.0, fractionDigits: 1) == "60\(decimal)0")
  #expect(language.formatNumber(0.0, fractionDigits: 1) == "0\(decimal)0")
  #expect(language.formatNumber(-12.34, fractionDigits: 1) == "-12\(decimal)3")
  #expect(language.formatNumber(0.5, fractionDigits: 2) == "0\(decimal)50")
}
