import SwiftUI

struct ObjectLanguageHeader: View {
  @Binding var selection: GameLanguage
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Object language")
        Spacer()
        Text(selection.title).accessibilityIdentifier("objectLanguageName")
      }.font(.caption).foregroundStyle(.secondary)
      GameLanguagePicker(
        label: "Object language", selection: $selection,
        identifier: "objectLanguagePicker"
      ).fixedSize()
    }
  }
}

/// AppKit provides a native tooltip for each segment, including emoji-only labels.
struct GameLanguagePicker: NSViewRepresentable {
  let label: String
  @Binding var selection: GameLanguage
  let identifier: String

  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

  func makeNSView(context: Context) -> GameLanguageControl {
    let control = GameLanguageControl()
    control.target = context.coordinator
    control.action = #selector(Coordinator.selectLanguage(_:))
    control.setAccessibilityLabel(label)
    control.setAccessibilityIdentifier(identifier)
    return control
  }

  func updateNSView(_ control: GameLanguageControl, context: Context) {
    context.coordinator.selection = $selection
    control.selectedSegment = GameLanguage.allCases.firstIndex(of: selection) ?? 0
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: GameLanguageControl, context: Context)
    -> CGSize?
  {
    nsView.intrinsicContentSize
  }

  @MainActor final class Coordinator: NSObject {
    var selection: Binding<GameLanguage>
    init(selection: Binding<GameLanguage>) { self.selection = selection }
    @objc func selectLanguage(_ control: NSSegmentedControl) {
      guard GameLanguage.allCases.indices.contains(control.selectedSegment) else { return }
      selection.wrappedValue = GameLanguage.allCases[control.selectedSegment]
    }
  }
}

final class GameLanguageControl: NSSegmentedControl {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    segmentCount = GameLanguage.allCases.count
    trackingMode = .selectOne
    segmentStyle = .rounded
    segmentDistribution = .fit
    selectedSegment = 0
    setContentHuggingPriority(.required, for: .horizontal)
    for (index, language) in GameLanguage.allCases.enumerated() {
      setLabel(language.flag, forSegment: index)
      setToolTip(language.title, forSegment: index)
    }
  }

}
