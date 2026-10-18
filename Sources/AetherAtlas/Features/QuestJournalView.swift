import AppKit
import SwiftUI

/// The journal's level/title, banner, rewards, description and objectives keep the
/// same reading order as the game. Supplemental database metadata lives below it.
struct QuestJournalView: View {
  let detail: EntityDetail
  let icons: IconStore
  let open: (EntitySummary) -> Void
  @Environment(\.colorScheme) private var colorScheme

  private let headingIconSize: CGFloat = 18
  private var contentInset: CGFloat { headingIconSize * 2 }
  private var gold: Color { Color(red: 0.65, green: 0.49, blue: 0.24) }
  private var paper: Color {
    colorScheme == .dark
      ? Color(red: 0.17, green: 0.165, blue: 0.15)
      : Color(red: 0.95, green: 0.925, blue: 0.86)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 16) {
        Text("Lv. \(detail.entity.level.map(String.init) ?? "—")")
          .font(.title2.weight(.medium).monospacedDigit())
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .frame(width: 44, height: 44)
          .background(.primary.opacity(0.07), in: Circle())
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Level \(detail.entity.level.map(String.init) ?? "unknown")")
        Text(detail.entity.displayName)
          .font(.system(size: 26, weight: .medium, design: .serif))
          .multilineTextAlignment(.center)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("entityDetailName")
        Color.clear.frame(width: 44, height: 1).accessibilityHidden(true)
      }
      .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)

      Rectangle().fill(gold.opacity(0.45)).frame(height: 1)

      VStack(alignment: .leading, spacing: 20) {
        if let path = detail.row["Icon"].iconPath {
          QuestBanner(path: path, icons: icons)
        }
        journalSection("Reward", symbol: "shippingbox.circle.fill") {
          rewards
        }
        journalSection("Description", symbol: "book.circle.fill") {
          if let journal = detail.questJournal, !journal.description.isEmpty {
            GameDescriptionText(description: journal.description)
          } else {
            Text("No journal description available.").foregroundStyle(.secondary)
          }
        }
        journalSection("Objectives", symbol: "exclamationmark.circle.fill") {
          if let journal = detail.questJournal, !journal.objectives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(Array(journal.objectives.enumerated()), id: \.offset) { index, objective in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                  if journal.objectives.count > 1 {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                      .frame(minWidth: 18, alignment: .trailing)
                  }
                  GameDescriptionText(description: objective)
                }
              }
            }
          } else {
            Text("No objectives available.").foregroundStyle(.secondary)
          }
        }
      }
      .padding(.horizontal, contentInset).padding(.vertical, 24)
    }
    .background(paper, in: RoundedRectangle(cornerRadius: 12))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12).strokeBorder(gold.opacity(0.7), lineWidth: 1)
    }
    .overlay(alignment: .top) {
      GameIcon(path: detail.entity.iconPath, kind: .quest, icons: icons, size: 52, framed: false)
        .background(paper, in: Circle())
        .offset(y: -26)
    }
    .padding(.top, 26)
    .accessibilityElement(children: .contain)
  }

  private func journalSection<Content: View>(
    _ title: String, symbol: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.title3.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
          // Center icons in the left margin, outside the content column.
          Image(systemName: symbol).font(.system(size: headingIconSize))
            .frame(width: headingIconSize, height: headingIconSize)
            .offset(x: -(contentInset + headingIconSize) / 2)
            .accessibilityHidden(true)
        }
        .accessibilityAddTraits(.isHeader)
      content()
    }
  }

  private var rewards: some View {
    VStack(alignment: .leading, spacing: 12) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 28) { rewardAmounts }
        VStack(alignment: .leading, spacing: 12) { rewardAmounts }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16).padding(.vertical, 8)
      .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))

      rewardItems("Reward", counts: "ItemCountReward")
      rewardItems("OptionalItemReward", counts: "OptionalItemCountReward", optional: true)
      if let other = detail.row["OtherReward"].referenceName, !other.isEmpty {
        Text(other).textSelection(.enabled)
      }
      if let other = detail.row["QuestRewardOtherDisplay"].referenceName, !other.isEmpty,
        other != detail.row["OtherReward"].referenceName
      {
        Text(other).textSelection(.enabled)
      }
    }
  }

  @ViewBuilder private var rewardAmounts: some View {
    rewardAmount(
      "EXP", value: detail.questExperience?.formatted() ?? "—", icon: 65_001)
    rewardAmount(
      "Gil", value: detail.row["GilReward"].integer?.formatted() ?? "—", icon: 65_002)
  }

  private func rewardAmount(_ label: String, value: String, icon: Int) -> some View {
    HStack(spacing: 10) {
      GameIcon(
        path: QuestPresentation.iconPath(icon), kind: .item, icons: icons, size: 36, framed: false,
        showsFallback: false)
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.title2.weight(.medium).monospacedDigit()).textSelection(.enabled)
      }
    }.accessibilityElement(children: .combine)
  }

  @ViewBuilder private func rewardItems(_ field: String, counts: String, optional: Bool = false)
    -> some View
  {
    let amounts = detail.row[counts].array
    let entries = detail.row[field].array.enumerated().compactMap {
      index, value -> (Int, EntitySummary, Int)? in
      guard value["sheet"].string == "Item", let row = value["row_id"].integer, row > 0,
        amounts.indices.contains(index), let count = amounts[index].integer, count > 0
      else { return nil }
      return (
        index, SheetRow(rowID: row, fields: value["fields"].object).summary(kind: .item), count
      )
    }
    if !entries.isEmpty {
      if optional { Text("Choose one").font(.subheadline.weight(.medium)) }
      ForEach(entries, id: \.0) { index, entity, count in
        Button {
          open(entity)
        } label: {
          HStack(spacing: 10) {
            GameIcon(path: entity.iconPath, kind: .item, icons: icons, size: 32)
            Text(entity.displayName)
            if optional, detail.row["OptionalItemIsHQReward"].array.indices.contains(index),
              detail.row["OptionalItemIsHQReward"].array[index].boolean == true
            {
              Text("HQ").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("×\(count)").monospacedDigit()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
          }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(entity.displayName), Item")
      }
    }
  }
}

private struct QuestBanner: View {
  let path: String
  let icons: IconStore
  @State private var image: NSImage?
  @State private var failed = false

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
          .frame(maxHeight: 180)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      } else if !failed {
        Rectangle().fill(.primary.opacity(0.04)).aspectRatio(3.2, contentMode: .fit)
          .frame(maxHeight: 180)
          .overlay { ProgressView().controlSize(.small) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
    .task(id: path) {
      image = nil
      failed = false
      do {
        let result = try await icons.image(path: path)
        try Task.checkCancellation()
        image = result
        failed = result == nil
      } catch {
        if !Task.isCancelled { failed = true }
      }
    }
  }
}
