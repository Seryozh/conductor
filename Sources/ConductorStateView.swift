import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

/// A local, silent illustration of an existing engine state. This view owns no task state.
/// How a pose fills its view: the whole poster, or the command panel's stage, where every pose is
/// cropped to the same head height and scale so the figure does not jump between states.
enum ConductorFraming { case poster, stage }

struct ConductorStateView: View {
    let state: VoiceState
    var animates = true
    var framing: ConductorFraming = .poster
    var bundle: Bundle = .main
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ConductorStateRepresentable(state: state, animates: animates && !reduceMotion, framing: framing, bundle: bundle)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct ConductorStateRepresentable: NSViewRepresentable {
    let state: VoiceState
    let animates: Bool
    let framing: ConductorFraming
    let bundle: Bundle

    func makeNSView(context: Context) -> ConductorStatePlayerView {
        let view = ConductorStatePlayerView()
        view.configure(state: state, animates: animates, framing: framing, bundle: bundle)
        return view
    }
    func updateNSView(_ view: ConductorStatePlayerView, context: Context) {
        view.configure(state: state, animates: animates, framing: framing, bundle: bundle)
    }
    static func dismantleNSView(_ view: ConductorStatePlayerView, coordinator: ()) {
        view.dispose()
    }
}

/// Keeps at most the current decoder and one retiring decoder during a 220 ms fade.
/// Visibility belongs to the window, not app activation: the command panel is nonactivating.
final class ConductorStatePlayerView: NSView {
    private var current: ConductorPose?
    private var retiring: ConductorPose?
    private var allowsMotion = true
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var fadeCompletion: DispatchWorkItem?
    private var transitionGeneration = 0
    private var screensAsleep = false
    private var framing: ConductorFraming = .poster
    private static let fadeDuration: TimeInterval = 0.22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification)
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification)
        watch(.default, NSApplication.didHideNotification)
        watch(.default, NSApplication.didUnhideNotification)
        watch(.default, NSWindow.didChangeOcclusionStateNotification)
        watch(.default, NSWindow.didExposeNotification)
        watch(.default, NSWindow.didMiniaturizeNotification)
        watch(.default, NSWindow.didDeminiaturizeNotification)
        watch(.default, NSWindow.willCloseNotification)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Read-only presentation diagnostics for isolated UI fixtures.
    var activePlayerCount: Int { (current?.hasPlayer == true ? 1 : 0) + (retiring?.hasPlayer == true ? 1 : 0) }
    var displayedState: VoiceState? { current?.state }

    private var shouldAnimate: Bool {
        guard allowsMotion, !screensAsleep, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window, window.isVisible, !window.isMiniaturized, window.isOnActiveSpace,
              window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor else { return false }
        return true
    }
    private func watch(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            if let notifiedWindow = notification.object as? NSWindow, notifiedWindow !== self.window { return }
            if name == NSWorkspace.screensDidSleepNotification { self.screensAsleep = true }
            if name == NSWorkspace.screensDidWakeNotification { self.screensAsleep = false }
            if name == NSWindow.willCloseNotification { self.stopMotion() }
            else { self.refreshPlayback() }
        }
        observers.append((center, token))
    }
    func configure(state: VoiceState, animates: Bool, framing: ConductorFraming = .poster, bundle: Bundle) {
        allowsMotion = animates
        if self.framing != framing {
            self.framing = framing
            current?.framing = framing; retiring?.framing = framing
            current?.resize(to: bounds, scale: window?.backingScaleFactor ?? 2)
        }
        if current?.state == state && current?.bundleURL == bundle.bundleURL {
            refreshPlayback()
            return
        }
        finishFade()
        let next = ConductorPose(state: state, bundle: bundle)
        next.framing = framing
        next.resize(to: bounds, scale: window?.backingScaleFactor ?? 2)
        layer?.addSublayer(next.layer)
        let previous = current
        current = next
        guard shouldAnimate, let previous else {
            previous?.dispose()
            refreshPlayback()
            return
        }
        retiring = previous
        next.startPlayback()
        fade(next.layer, from: 0, to: 1)
        fade(previous.layer, from: previous.layer.presentation()?.opacity ?? 1, to: 0)
        let generation = transitionGeneration
        let completion = DispatchWorkItem { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            self.finishFade()
        }
        fadeCompletion = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration, execute: completion)
    }
    private func fade(_ layer: CALayer, from: Float, to: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = to
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Self.fadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "stateCrossfade")
    }
    private func finishFade() {
        transitionGeneration += 1
        fadeCompletion?.cancel()
        fadeCompletion = nil
        retiring?.dispose()
        retiring = nil
        current?.layer.removeAnimation(forKey: "stateCrossfade")
        current?.layer.opacity = 1
    }
    private func stopMotion() {
        finishFade()
        current?.stopPlayback()
    }
    private func refreshPlayback() {
        if shouldAnimate { current?.startPlayback() }
        else { stopMotion() }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshPlayback() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); refreshPlayback() }
    override func viewDidHide() { super.viewDidHide(); refreshPlayback() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshPlayback() }
    override func layout() {
        super.layout()
        current?.resize(to: bounds, scale: window?.backingScaleFactor ?? 2)
        retiring?.resize(to: bounds, scale: window?.backingScaleFactor ?? 2)
        refreshPlayback()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func dispose() {
        stopMotion()
        current?.dispose()
        current = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
    deinit {
        fadeCompletion?.cancel()
        for (center, observer) in observers { center.removeObserver(observer) }
        current?.dispose()
        retiring?.dispose()
    }
}

private final class ConductorPose {
    let state: VoiceState
    let bundleURL: URL
    var framing: ConductorFraming = .poster
    let layer = CALayer()
    private let poster = CALayer()
    private let video = AVPlayerLayer()
    private let verticalEdgeMask = CAGradientLayer()
    private let horizontalEdgeMask = CAGradientLayer()
    private let videoURL: URL?
    private let hasPoster: Bool
    private let fallbackImage: NSImage?
    private var fallbackScale: CGFloat = 0
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var looperObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var failed = false
    var hasPlayer: Bool { player != nil }

    init(state: VoiceState, bundle: Bundle) {
        self.state = state
        bundleURL = bundle.bundleURL
        videoURL = bundle.url(forResource: state.rawValue, withExtension: "mp4", subdirectory: "ConductorStates")
        let imageURL = bundle.url(forResource: state.rawValue, withExtension: "png", subdirectory: "ConductorStates")
        let image = imageURL.flatMap { NSImage(contentsOf: $0) }
        hasPoster = image != nil
        let configuration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
            .applying(.init(paletteColors: [NSColor(state.color)]))
        fallbackImage = NSImage(systemSymbolName: state.icon, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        poster.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        poster.contentsGravity = .resizeAspect
        layer.addSublayer(poster)
        video.videoGravity = .resizeAspect
        video.opacity = 0
        layer.addSublayer(video)
        // A shared alpha edge blends both the poster and encoded video into the panel.
        // Most of the 12 pt blend is opaque so hands and baton near the edge stay legible.
        let edgeColors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.94).cgColor,
                          NSColor.black.cgColor, NSColor.black.cgColor,
                          NSColor.black.withAlphaComponent(0.94).cgColor, NSColor.clear.cgColor]
        verticalEdgeMask.colors = edgeColors
        horizontalEdgeMask.colors = edgeColors
        horizontalEdgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        horizontalEdgeMask.endPoint = CGPoint(x: 1, y: 0.5)
        verticalEdgeMask.mask = horizontalEdgeMask
        layer.mask = verticalEdgeMask
    }
    func resize(to bounds: CGRect, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.contentsScale = scale
        let artwork = framing == .stage && hasPoster ? stageFrame(in: bounds) : layer.bounds
        poster.frame = hasPoster ? artwork : CGRect(x: (bounds.width - 28) / 2, y: (bounds.height - 28) / 2, width: 28, height: 28)
        poster.contentsScale = scale
        if !hasPoster && fallbackScale != scale {
            poster.contents = rasterizedFallback(scale: scale)
            fallbackScale = scale
        }
        video.frame = artwork
        video.contentsScale = scale
        verticalEdgeMask.frame = layer.bounds
        horizontalEdgeMask.frame = layer.bounds
        func stops(_ length: CGFloat) -> [NSNumber] {
            let edge = min(0.25, (framing == .stage ? 5 : 12) / max(1, length))
            return [0, edge * 2 / 3, edge, 1 - edge, 1 - edge * 2 / 3, 1].map { NSNumber(value: Double($0)) }
        }
        verticalEdgeMask.locations = stops(bounds.height)
        horizontalEdgeMask.locations = stops(bounds.width)
        CATransaction.commit()
    }
    /// Poster pixels (360 × 264, top-left origin) that fill the stage: 273 × 220 around each figure,
    /// with the head the same distance from the top in every pose.
    private static let stageCrops: [VoiceState: CGPoint] = [
        .ready: CGPoint(x: 40, y: 0), .listening: CGPoint(x: 43, y: 19), .recognizing: CGPoint(x: 43, y: 8),
        .thinking: CGPoint(x: 44, y: 15), .acting: CGPoint(x: 44, y: 0), .checking: CGPoint(x: 40, y: 24),
        .attention: CGPoint(x: 56, y: 10),
    ]
    private func stageFrame(in bounds: CGRect) -> CGRect {
        let poster = CGSize(width: 360, height: 264), crop = CGSize(width: 273, height: 220)
        let origin = Self.stageCrops[state] ?? CGPoint(x: 43, y: 22)
        let scale = max(bounds.width / crop.width, bounds.height / crop.height)
        let x = -origin.x * scale - (crop.width * scale - bounds.width) / 2
        let top = bounds.maxY + origin.y * scale + (crop.height * scale - bounds.height) / 2
        return CGRect(x: x, y: top - poster.height * scale, width: poster.width * scale, height: poster.height * scale)
    }
    private func rasterizedFallback(scale: CGFloat) -> CGImage? {
        guard let fallbackImage else { return nil }
        let pixels = Int(ceil(28 * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let factor = CGFloat(pixels) / max(fallbackImage.size.width, fallbackImage.size.height)
        let size = NSSize(width: fallbackImage.size.width * factor, height: fallbackImage.size.height * factor)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        fallbackImage.draw(in: NSRect(x: (CGFloat(pixels) - size.width) / 2, y: (CGFloat(pixels) - size.height) / 2,
                                     width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
    func startPlayback() {
        guard !failed, let videoURL else { return }
        if let player { if player.rate == 0 { player.play() }; return }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.allowsExternalPlayback = false
        queue.preventsDisplaySleepDuringVideoPlayback = false
        let item = AVPlayerItem(url: videoURL)
        player = queue
        video.player = queue
        let loop = AVPlayerLooper(player: queue, templateItem: item)
        looper = loop
        readyObservation = video.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak queue] _, _ in
            DispatchQueue.main.async {
                guard let self, let queue, self.player === queue else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.video.opacity = self.video.isReadyForDisplay ? 1 : 0
                CATransaction.commit()
            }
        }
        statusObservation = queue.observe(\.status, options: [.initial, .new]) { [weak self, weak queue] _, _ in
            DispatchQueue.main.async {
                guard let self, let queue, self.player === queue, queue.status == .failed else { return }
                self.failPlayback()
            }
        }
        looperObservation = loop.observe(\.status, options: [.initial, .new]) { [weak self, weak queue, weak loop] _, _ in
            DispatchQueue.main.async {
                guard let self, let queue, let loop, self.player === queue, loop.status == .failed else { return }
                self.failPlayback()
            }
        }
        // AVPlayerLooper inserts copies of the template, so watch the actual current item.
        currentItemObservation = queue.observe(\.currentItem, options: [.initial, .new]) { [weak self, weak queue] _, _ in
            DispatchQueue.main.async {
                guard let self, let queue, self.player === queue else { return }
                self.observeCurrentItem(of: queue)
            }
        }
        queue.play()
    }
    private func observeCurrentItem(of queue: AVQueuePlayer) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        guard let item = queue.currentItem else { return }
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak queue, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let queue, let item, self.player === queue, item.status == .failed else { return }
                self.failPlayback()
            }
        }
    }
    private func failPlayback() { failed = true; stopPlayback() }
    func stopPlayback() {
        readyObservation?.invalidate(); readyObservation = nil
        statusObservation?.invalidate(); statusObservation = nil
        looperObservation?.invalidate(); looperObservation = nil
        currentItemObservation?.invalidate(); currentItemObservation = nil
        itemStatusObservation?.invalidate(); itemStatusObservation = nil
        player?.pause()
        looper?.disableLooping(); looper = nil
        player?.removeAllItems()
        video.player = nil
        player = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        video.opacity = 0
        CATransaction.commit()
    }
    func dispose() { stopPlayback(); layer.removeFromSuperlayer() }
    deinit { stopPlayback() }
}
