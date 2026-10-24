import AppKit
import SwiftUI

struct MapDetailView: View {
  private enum DetailTab: String, CaseIterable {
    case map = "Map"
    case artwork = "Loading Screen"
  }
  @Bindable var model: MapDetailModel
  let entity: EntitySummary
  let language: GameLanguage
  let refresh: () -> Void
  let icons: IconStore
  @State private var image: NSImage?
  @State private var zoom = 1.0
  @State private var command = MapViewportCommand()
  @State private var selectedMarker: GameMapMarker?
  @State private var pointerCoordinates: GameMapCoordinates?
  @State private var tab = DetailTab.map

  var body: some View {
    VStack(spacing: 0) {
      if let map = model.map, map.id == entity.id.row {
        VStack(alignment: .leading, spacing: 12) {
          GameText(map.title).font(.title2.weight(.semibold)).accessibilityIdentifier(
            "mapDetailName")
          Text(map.region).font(.caption).foregroundStyle(.secondary)
          Picker("Map detail", selection: $tab) {
            ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented).labelsHidden().frame(width: 250)
          .accessibilityIdentifier("mapDetailTabs")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        Divider()
        ZStack {
          mapPane(map)
            .opacity(tab == .map ? 1 : 0)
            .allowsHitTesting(tab == .map)
            .accessibilityHidden(tab != .map)
          if tab == .artwork {
            MapLoadingArtworkView(path: map.loadingImagePath, name: map.title, icons: icons)
              .id(map.loadingImagePath)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = model.error {
        failure(error)
      } else {
        ProgressView("Opening \(entity.displayName)…").frame(
          maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: model.content?.image, initial: true) {
      image = model.content.flatMap { NSImage(data: $0.image) }
      selectedMarker = nil
      zoom = 1
    }
    .onChange(of: entity.id) {
      selectedMarker = nil
      pointerCoordinates = nil
    }
    .onChange(of: tab) { if tab != .map { pointerCoordinates = nil } }
    .onChange(of: language) { selectedMarker = nil }
  }

  private func mapPane(_ map: GameMap) -> some View {
    VStack(spacing: 0) {
      HStack {
        Menu {
          Toggle("Named places", isOn: $model.layers.landmarks)
          Toggle("Other icons", isOn: $model.layers.otherIcons)
          Toggle("Place labels", isOn: $model.layers.labels)
        } label: {
          Label("Layers", systemImage: "square.3.layers.3d")
        }
        .accessibilityIdentifier("mapLayers")
        Text(pointerCoordinates?.formatted() ?? "X: —  Y: —")
          .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
          .lineLimit(1).minimumScaleFactor(0.85).layoutPriority(1)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("mapCoordinates")
        if model.isLoading { ProgressView().controlSize(.small) }
        Button("Zoom Out", systemImage: "minus.magnifyingglass") { command.send(.zoomOut) }
          .labelStyle(.iconOnly).disabled(image == nil || zoom <= 1.001)
        Text("\(language.formatNumber(zoom, fractionDigits: 1))×")
          .font(.caption.monospacedDigit()).frame(width: 44).accessibilityIdentifier("mapZoom")
        Button("Zoom In", systemImage: "plus.magnifyingglass") { command.send(.zoomIn) }
          .labelStyle(.iconOnly).disabled(image == nil)
        Button("Fit") { command.send(.fit) }.disabled(image == nil).accessibilityLabel("Fit Map")
      }.controlSize(.small).padding(.horizontal, 16).padding(.vertical, 10)
      Divider()
      if model.isLoading && model.content == nil {
        ProgressView("Unfolding the map…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = model.error {
        failure(error)
      } else if let image, let content = model.content {
        MapCanvas(
          image: image, mapID: map.id, sizeFactor: map.sizeFactor,
          tracksPointer: tab == .map, markers: content.markers, icons: icons,
          layers: model.layers, command: command, zoomChanged: { zoom = $0 },
          pointerChanged: { pointerCoordinates = $0 },
          select: { selectedMarker = $0 })
        if content.isStale {
          Label("Cached map · connection unavailable", systemImage: "wifi.slash")
            .font(.caption).foregroundStyle(.secondary).padding(8)
        }
        if let error = content.markerError {
          HStack {
            Text(error).font(.caption)
            Button("Retry") { refresh() }
          }.padding(8)
        }
      } else if model.content != nil {
        failure("The map image couldn’t be read.")
      } else {
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      HStack {
        Text(selectedMarker?.title ?? "").font(.caption).lineLimit(2).textSelection(.enabled)
          .accessibilityIdentifier("mapSelection")
        Spacer()
        Text(
          "\(language.formatNumber(visibleMarkerCount)) \(visibleMarkerCount == 1 ? "marker" : "markers")"
        )
        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("mapMarkerCount")
      }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }
  }

  private var visibleMarkerCount: Int {
    model.content?.markers.filter { model.layers.shows($0, zoom: zoom) }.count ?? 0
  }

  private func failure(_ error: String) -> some View {
    ContentUnavailableView {
      Label("Couldn’t open this map", systemImage: "map")
    } description: {
      Text(error)
    } actions: {
      Button("Try Again") { refresh() }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct MapLoadingArtworkView: View {
  let path: String?
  let name: String
  let icons: IconStore
  @State private var image: NSImage?
  @State private var loading = true
  @State private var retry = 0

  var body: some View {
    Group {
      if let image {
        GeometryReader { geometry in
          let ratio = image.size.width / max(1, image.size.height)
          let width = min(geometry.size.width, geometry.size.height * ratio)
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .frame(width: width, height: width / ratio)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .accessibilityLabel("\(name) loading screen").accessibilityIdentifier(
              "mapLoadingArtwork")
        }.padding(20)
      } else if loading, path != nil {
        ProgressView("Loading artwork…")
      } else {
        ContentUnavailableView {
          Label("Loading screen unavailable", systemImage: "photo")
        } description: {
          Text(
            path == nil
              ? "This area has no loading image reference." : "The artwork couldn’t be loaded.")
        } actions: {
          if path != nil { Button("Try Again") { retry += 1 } }
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .underPageBackgroundColor))
      .task(id: "\(path ?? ""):\(retry)") {
        image = nil
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        guard let path else { return }
        do {
          let value = try await icons.image(path: path)
          try Task.checkCancellation()
          image = value
        } catch {}
      }
  }
}
