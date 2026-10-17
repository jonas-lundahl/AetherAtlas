import SwiftUI

struct GameDescriptionText: View {
  let description: GameDescription
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Text(Self.attributed(description, colorScheme: colorScheme))
      .font(.body)
      .lineSpacing(5)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("gameDescription")
  }

  static func attributed(_ description: GameDescription, colorScheme: ColorScheme)
    -> AttributedString
  {
    var content = AttributedString()
    for run in description.runs {
      var segment = AttributedString(run.text)
      if let color = run.style.color {
        let rgb = readable(color, colorScheme: colorScheme)
        segment.foregroundColor = Color(
          .sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
      }
      var intent = InlinePresentationIntent()
      if run.style.bold { intent.insert(.stronglyEmphasized) }
      if run.style.italic { intent.insert(.emphasized) }
      if run.style.strikethrough { intent.insert(.strikethrough) }
      if !intent.isEmpty { segment.inlinePresentationIntent = intent }
      if run.style.underline { segment.underlineStyle = Text.LineStyle(pattern: .solid) }
      content.append(segment)
    }
    return content
  }

  /// Keep the game's colors in dark appearance. Darken luminous colors on light
  /// surfaces while preserving their hue, so highlights remain readable there too.
  static func readable(_ color: GameDescription.RGBA, colorScheme: ColorScheme)
    -> GameDescription.RGBA
  {
    guard colorScheme == .light else { return color }
    func luminance(_ scale: Double) -> Double {
      func linear(_ channel: Double) -> Double {
        let value = channel * scale
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
    guard luminance(1) > 0.14 else { return color }
    var low = 0.0
    var high = 1.0
    for _ in 0..<16 {
      let scale = (low + high) / 2
      if luminance(scale) > 0.14 { high = scale } else { low = scale }
    }
    return GameDescription.RGBA(
      red: color.red * low, green: color.green * low, blue: color.blue * low, alpha: color.alpha)
  }
}
