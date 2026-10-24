import AppKit
import SwiftUI

struct MapCanvas: NSViewRepresentable {
  let image: NSImage
  let mapID: Int
  let sizeFactor: Int?
  let tracksPointer: Bool
  let markers: [GameMapMarker]
  let icons: IconStore
  let layers: MapLayers
  let command: MapViewportCommand
  let zoomChanged: (Double) -> Void
  let pointerChanged: (GameMapCoordinates?) -> Void
  let select: (GameMapMarker?) -> Void

  func makeNSView(context: Context) -> MapScrollView {
    let scroll = MapScrollView()
    scroll.acknowledge(command)
    return scroll
  }
  func updateNSView(_ scroll: MapScrollView, context: Context) {
    scroll.zoomChanged = zoomChanged
    scroll.pointerChanged = pointerChanged
    scroll.tracksPointer = tracksPointer
    scroll.mapDocument.select = select
    scroll.apply(
      image: image, mapID: mapID, markers: markers, icons: icons, layers: layers,
      sizeFactor: sizeFactor)
    scroll.perform(command)
  }
  static func dismantleNSView(_ scroll: MapScrollView, coordinator: ()) {
    scroll.mapDocument.cancelDownloads()
    scroll.tracksPointer = false
    Task { @MainActor [pointerChanged = scroll.pointerChanged] in pointerChanged?(nil) }
  }
}

struct MapViewportCommand: Equatable {
  enum Action { case fit, zoomIn, zoomOut }
  var sequence = 0
  var action: Action = .fit
  mutating func send(_ action: Action) {
    self.action = action
    sequence += 1
  }
}

/// AppKit owns the camera so trackpad scrolling, pinch zoom and accessibility remain native.
@MainActor final class MapScrollView: NSScrollView {
  let mapDocument = MapDocumentView(frame: NSRect(x: 0, y: 0, width: 2048, height: 2048))
  var zoomChanged: ((Double) -> Void)?
  var pointerChanged: ((GameMapCoordinates?) -> Void)?
  var tracksPointer = true {
    didSet {
      guard tracksPointer != oldValue else { return }
      if !tracksPointer { pointerWindowLocation = nil }
      updateTrackingAreas()
      publishViewport()
    }
  }
  private var mapID: Int?
  private var sizeFactor: Int?
  private var pointerArea: NSTrackingArea?
  private var pointerWindowLocation: NSPoint?
  private var publishedCoordinates: GameMapCoordinates?
  private var publishedZoom: Double?
  private var lastCommand = 0
  private var fitting = true
  private var notifying = false
  private(set) var fitScale: CGFloat = 1
  private var relativeZoom: Double {
    // Keep display rounding and layer thresholds stable across native layout passes.
    (Double(magnification / max(0.01, fitScale)) * 10_000).rounded() / 10_000
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    contentView = CenteredMapClipView()
    documentView = mapDocument
    allowsMagnification = true
    minMagnification = 0.05
    maxMagnification = 4
    hasHorizontalScroller = true
    hasVerticalScroller = true
    autohidesScrollers = true
    scrollerStyle = .overlay
    drawsBackground = true
    backgroundColor = .underPageBackgroundColor
    borderType = .noBorder
    setAccessibilityIdentifier("mapCanvas")
    setAccessibilityLabel("Interactive game map")
    mapDocument.camera = self
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.acceptsMouseMovedEvents = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerArea { removeTrackingArea(pointerArea) }
    pointerArea = nil
    guard tracksPointer else { return }
    let area = NSTrackingArea(
      rect: .zero,
      options: [
        .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
        .enabledDuringMouseDrag,
      ], owner: self, userInfo: nil)
    addTrackingArea(area)
    pointerArea = area
  }

  override func mouseMoved(with event: NSEvent) { trackPointer(event.locationInWindow) }
  override func mouseEntered(with event: NSEvent) { trackPointer(event.locationInWindow) }
  override func mouseExited(with event: NSEvent) { trackPointer(nil) }

  func trackPointer(_ windowLocation: NSPoint?) {
    pointerWindowLocation = tracksPointer ? windowLocation : nil
    publishViewport()
  }

  func coordinates(at windowLocation: NSPoint) -> GameMapCoordinates? {
    guard tracksPointer, mapID != nil,
      contentView.bounds.contains(contentView.convert(windowLocation, from: nil))
    else { return nil }
    let point = mapDocument.convert(windowLocation, from: nil)
    return GameMapCoordinates(
      normalizedX: point.x / mapDocument.bounds.width,
      normalizedY: point.y / mapDocument.bounds.height, sizeFactor: sizeFactor)
  }

  func apply(
    image: NSImage, mapID: Int, markers: [GameMapMarker], icons: IconStore, layers: MapLayers,
    sizeFactor: Int? = nil
  ) {
    let changed = self.mapID != mapID
    self.mapID = mapID
    self.sizeFactor = sizeFactor
    mapDocument.apply(image: image, markers: markers, icons: icons, layers: layers, reset: changed)
    if changed {
      fitting = true
      needsLayout = true
    }
    updateOverlays()
  }

  override func layout() {
    super.layout()
    guard bounds.width > 0, bounds.height > 0 else { return }
    // Scrollbar visibility must not redefine the camera's fit baseline.
    fitScale = max(0.01, min(bounds.width / 2048, bounds.height / 2048))
    minMagnification = fitScale
    maxMagnification = max(4, fitScale * 8)
    if fitting && abs(magnification - fitScale) > 0.0001 {
      setMagnification(fitScale, centeredAt: NSPoint(x: 1024, y: 1024))
    }
    updateOverlays()
  }

  func perform(_ command: MapViewportCommand) {
    guard command.sequence != lastCommand else { return }
    lastCommand = command.sequence
    switch command.action {
    case .fit: fit()
    case .zoomIn: zoom(by: 1.5)
    case .zoomOut: zoom(by: 1 / 1.5)
    }
  }

  func fit() {
    fitting = true
    setMagnification(fitScale, centeredAt: NSPoint(x: 1024, y: 1024))
    updateOverlays()
  }

  func acknowledge(_ command: MapViewportCommand) { lastCommand = command.sequence }

  func zoom(by factor: CGFloat, centeredAt point: NSPoint? = nil) {
    fitting = false
    let center = point ?? NSPoint(x: documentVisibleRect.midX, y: documentVisibleRect.midY)
    setMagnification(
      min(maxMagnification, max(minMagnification, magnification * factor)), centeredAt: center)
    updateOverlays()
  }

  override func scrollWheel(with event: NSEvent) {
    trackPointer(event.locationInWindow)
    super.scrollWheel(with: event)
  }

  override func magnify(with event: NSEvent) {
    trackPointer(event.locationInWindow)
    fitting = false
    super.magnify(with: event)
    updateOverlays()
  }

  override func reflectScrolledClipView(_ clipView: NSClipView) {
    super.reflectScrolledClipView(clipView)
    updateOverlays()
  }

  private func updateOverlays() {
    let scale = max(0.01, magnification)
    mapDocument.updateCamera(scale: scale, relativeZoom: CGFloat(relativeZoom))
    publishViewport()
  }

  private func publishViewport() {
    // Clip-view notifications can arrive during SwiftUI layout; coalesce publication.
    guard !notifying else { return }
    notifying = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      notifying = false
      if publishedZoom != relativeZoom {
        publishedZoom = relativeZoom
        zoomChanged?(relativeZoom)
      }
      let coordinates = pointerWindowLocation.flatMap { self.coordinates(at: $0) }
      if publishedCoordinates != coordinates {
        publishedCoordinates = coordinates
        pointerChanged?(coordinates)
      }
    }
  }

  override func keyDown(with event: NSEvent) {
    let text = event.charactersIgnoringModifiers ?? ""
    if text == "+" || text == "=" {
      zoom(by: 1.5)
      return
    }
    if text == "-" {
      zoom(by: 1 / 1.5)
      return
    }
    if text == "0" {
      fit()
      return
    }
    var origin = contentView.bounds.origin
    let step = 80 / max(0.01, magnification)
    switch event.keyCode {
    case 123: origin.x -= step
    case 124: origin.x += step
    case 125: origin.y += step
    case 126: origin.y -= step
    default:
      super.keyDown(with: event)
      return
    }
    contentView.scroll(
      to: contentView.constrainBoundsRect(NSRect(origin: origin, size: contentView.bounds.size))
        .origin)
    reflectScrolledClipView(contentView)
  }
}

@MainActor private final class CenteredMapClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var bounds = super.constrainBoundsRect(proposedBounds)
    if let documentView {
      if bounds.width > documentView.frame.width {
        bounds.origin.x = (documentView.frame.width - bounds.width) / 2
      }
      if bounds.height > documentView.frame.height {
        bounds.origin.y = (documentView.frame.height - bounds.height) / 2
      }
    }
    return bounds
  }
}

@MainActor final class MapDocumentView: NSView {
  weak var camera: MapScrollView?
  var select: ((GameMapMarker?) -> Void)?
  private var image: NSImage?
  private var markers: [GameMapMarker] = []
  private var buttons: [String: MapMarkerButton] = [:]
  private var layers = MapLayers()
  private var scale: CGFloat = 1
  private var relativeZoom: CGFloat = 1
  private var dragOrigin = NSPoint.zero
  private(set) var selectedID: String?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func keyDown(with event: NSEvent) { camera?.keyDown(with: event) }

  override init(frame: NSRect) {
    super.init(frame: frame)
    let pan = NSPanGestureRecognizer(target: self, action: #selector(pan(_:)))
    pan.buttonMask = 0x1
    addGestureRecognizer(pan)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(
    image: NSImage, markers: [GameMapMarker], icons: IconStore, layers: MapLayers, reset: Bool
  ) {
    if self.image !== image {
      self.image = image
      needsDisplay = true
    }
    self.layers = layers
    if self.markers != markers || reset {
      for button in buttons.values {
        button.cancel()
        button.caption.removeFromSuperview()
        button.removeFromSuperview()
      }
      buttons.removeAll()
      self.markers = markers
      selectedID = nil
      for marker in markers {
        let button = MapMarkerButton(marker: marker, icons: icons)
        button.activate = { [weak self] in
          guard let self else { return }
          selectedID = marker.id
          updateCamera(scale: scale, relativeZoom: relativeZoom)
          select?(marker)
        }
        addSubview(button)
        addSubview(button.caption)
        buttons[marker.id] = button
      }
    }
    updateCamera(scale: scale, relativeZoom: relativeZoom)
  }

  func cancelDownloads() { for button in buttons.values { button.cancel() } }

  func updateCamera(scale: CGFloat, relativeZoom: CGFloat) {
    self.scale = scale
    self.relativeZoom = relativeZoom
    for marker in markers {
      guard let button = buttons[marker.id] else { continue }
      button.isHidden = !layers.shows(marker, zoom: Double(relativeZoom))
      button.frame = NSRect(
        x: marker.x * bounds.width - 14 / scale,
        y: marker.y * bounds.height - 14 / scale, width: 28 / scale, height: 28 / scale)
      button.updateLabel(
        visible: layers.labels && marker.isNamed
          && (layers.showsLabel(marker, zoom: Double(relativeZoom)) || selectedID == marker.id),
        scale: scale,
        selected: selectedID == marker.id)
    }
    // Preserve the game's label anchors. Suppress collisions instead of moving
    // names away from their pins; selected names take priority.
    let visible = camera?.documentVisibleRect ?? bounds
    var occupied: [NSRect] = []
    let ordered = markers.sorted { lhs, rhs in
      if (lhs.id == selectedID) != (rhs.id == selectedID) { return lhs.id == selectedID }
      return lhs.id < rhs.id
    }
    for marker in ordered {
      guard let button = buttons[marker.id], !button.caption.isHidden else { continue }
      let rect = button.caption.frame
      if !visible.intersects(rect) || occupied.contains(where: { $0.intersects(rect) }) {
        button.caption.isHidden = true
      } else {
        occupied.append(rect.insetBy(dx: -2 / scale, dy: -1 / scale))
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    image?.draw(
      in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    if event.clickCount == 2 {
      camera?.zoom(by: 2, centeredAt: convert(event.locationInWindow, from: nil))
    } else {
      selectedID = nil
      select?(nil)
      updateCamera(scale: scale, relativeZoom: relativeZoom)
    }
  }

  @objc private func pan(_ recognizer: NSPanGestureRecognizer) {
    guard let camera else { return }
    if recognizer.state == .began {
      dragOrigin = camera.contentView.bounds.origin
      window?.makeFirstResponder(self)
    }
    camera.trackPointer(convert(recognizer.location(in: self), to: nil))
    let movement = recognizer.translation(in: self)
    let rect = NSRect(
      x: dragOrigin.x - movement.x, y: dragOrigin.y - movement.y,
      width: camera.contentView.bounds.width, height: camera.contentView.bounds.height)
    camera.contentView.scroll(to: camera.contentView.constrainBoundsRect(rect).origin)
    camera.reflectScrolledClipView(camera.contentView)
  }
}

@MainActor final class MapMarkerButton: NSButton {
  let caption = MapMarkerCaption(labelWithString: "")
  let marker: GameMapMarker
  private var download: Task<Void, Never>?
  private var displayScale: CGFloat = 1
  var activate: (() -> Void)?
  override var isFlipped: Bool { true }

  init(marker: GameMapMarker, icons: IconStore) {
    self.marker = marker
    super.init(frame: .zero)
    title = ""
    isBordered = false
    imagePosition = .imageOnly
    imageScaling = .scaleProportionallyUpOrDown
    image = nil
    alternateImage = nil
    toolTip = marker.title
    setAccessibilityLabel(marker.title)
    setAccessibilityIdentifier("mapMarker-\(marker.id)")
    target = self
    action = #selector(openMarker)
    caption.owner = self
    caption.stringValue = marker.name
    caption.isBordered = false
    caption.drawsBackground = false
    caption.maximumNumberOfLines = 0
    caption.lineBreakMode = .byWordWrapping
    caption.setAccessibilityElement(false)
    if let path = marker.iconPath {
      download = Task { [weak self] in
        let artwork = try? await icons.image(path: path)
        guard !Task.isCancelled else { return }
        self?.image = artwork
        self?.needsDisplay = true
      }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func cancel() { download?.cancel() }

  // Draw in the icon's full canvas, independent of NSButton cell/bezel layout.
  // A zero icon is a text-only game marker, not a request for a generic pin.
  override func draw(_ dirtyRect: NSRect) {
    guard marker.iconPath != nil else { return }
    if let image {
      image.draw(
        in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    } else {
      let dot = NSBezierPath(
        ovalIn: bounds.insetBy(dx: bounds.width * 0.34, dy: bounds.height * 0.30))
      NSColor.systemOrange.setFill()
      dot.fill()
      NSColor.black.withAlphaComponent(0.8).setStroke()
      dot.lineWidth = 1 / displayScale
      dot.stroke()
    }
  }

  func updateLabel(visible: Bool, scale: CGFloat, selected: Bool) {
    displayScale = scale
    needsDisplay = true
    caption.isHidden = !visible || isHidden || marker.labelPlacement == .hidden
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
    shadow.shadowBlurRadius = 1 / scale
    shadow.shadowOffset = NSSize(width: 0, height: -0.5 / scale)
    caption.padding = 3 / scale
    let font = NSFont.systemFont(ofSize: 12 / scale, weight: selected ? .medium : .regular)
    let color =
      marker.isMapLink
      ? NSColor(red: 0.40, green: 0.88, blue: 0.96, alpha: 1) : NSColor.white
    caption.textColor = color
    let text = NSAttributedString(
      string: marker.name,
      attributes: [
        .font: font, .foregroundColor: color,
        .strokeColor: NSColor.black.withAlphaComponent(0.92), .strokeWidth: 8,
        .shadow: shadow, .paragraphStyle: paragraph,
      ])
    caption.attributedStringValue = text
    caption.renderedText = text
    let naturalWidth =
      marker.name.components(separatedBy: "\n").map {
        ($0 as NSString).size(withAttributes: [.font: font]).width
      }.max() ?? 0
    let width = min(230 / scale, naturalWidth + 1 / scale)
    let measured = text.boundingRect(
      with: NSSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading])
    let size = NSSize(
      width: ceil(width) + 6 / scale, height: ceil(measured.height) + 6 / scale)
    let anchor = NSPoint(x: frame.midX, y: frame.midY)
    let gap = 1 / scale
    let origin: NSPoint
    if marker.iconPath == nil {
      origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2)
    } else {
      switch marker.labelPlacement {
      case .left: origin = NSPoint(x: frame.minX - gap - size.width, y: anchor.y - size.height / 2)
      case .right, .hidden: origin = NSPoint(x: frame.maxX + gap, y: anchor.y - size.height / 2)
      case .above: origin = NSPoint(x: anchor.x - size.width / 2, y: frame.minY - gap - size.height)
      case .below: origin = NSPoint(x: anchor.x - size.width / 2, y: frame.maxY + gap)
      }
    }
    caption.frame = NSRect(origin: origin, size: size)
    if marker.iconPath == nil { frame = caption.frame }
    caption.needsDisplay = true
  }
  @objc private func openMarker() {
    window?.makeFirstResponder(superview as? MapDocumentView)
    activate?()
  }
}

@MainActor final class MapMarkerCaption: NSTextField {
  weak var owner: MapMarkerButton?
  var padding: CGFloat = 0
  var renderedText = NSAttributedString(string: "")
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: padding, dy: padding)
    let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    renderedText.draw(with: rect, options: options)
    // Fill after stroking so the outline never consumes thin white glyph stems.
    let fill = NSMutableAttributedString(attributedString: renderedText)
    let range = NSRange(location: 0, length: fill.length)
    for key in [NSAttributedString.Key.strokeWidth, .strokeColor, .shadow] {
      fill.removeAttribute(key, range: range)
    }
    fill.draw(with: rect, options: options)
  }
  override func mouseDown(with event: NSEvent) { owner?.performClick(nil) }
}
