//
//  LiquidGlassTabBar.swift
//  liquid-ui-effect-test
//
//  Created by Egor Butyrin on 15/12/2025.
//

import UIKit
import MetalKit

private final class LiquidGlassTabBarKnobTouchDelegate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: ((UIGestureRecognizer) -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldBegin?(gestureRecognizer) ?? true
    }
}

public final class LiquidGlassTabBar: MTKView, LiquidGlassBackground {
    // MARK: - Public Properties

    public var tabViews: [UIView] = [] {
        didSet {
            rebuildTabs()
        }
    }

    /// Padding inside the view bounds used for laying out the visible tab bar content (tabs + pill background).
    /// The full view bounds are still used for background capture so the knob can sample extra surrounding pixels.
    public var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard contentInsets != oldValue else { return }
            updateContentInsetsConstraints()
            overlayTextureNeedsUpdate = true
            setNeedsLayout()
        }
    }

    public var selectedIndex: Int = 0 {
        didSet {
            guard selectedIndex >= 0, selectedIndex < tabViews.count else {
                assertionFailure("selectedIndex out of bounds")
                return
            }
            if case .resting = knobController.selectorState {
                layoutKnobLayerForResting()
                syncKnobToSelection()
                requestRedraw()
            }
        }
    }

    public var onTabSelected: ((Int) -> Void)?

    public weak var captureView: UIView? {
        didSet {
            lastCapturedBackgroundTexture = nil
            backgroundCaptureNeedsUpdate = true
            requestRedraw()
        }
    }

    public var roiProvider: (() -> CGRect)?

    public var pillColor: UIColor = UIColor(red: 228 / 255, green: 238 / 255, blue: 250 / 255, alpha: 0.7) {
        didSet {
            knobLayer.backgroundColor = pillColor.cgColor
        }
    }

    public var cornerRadius: CGFloat {
        get {
            CGFloat(renderConfig.cornerRadius)
        }
        set {
            renderConfig = renderConfig.copyWith(cornerRadius: Float(newValue))
            backgroundRenderer.updateSettings(config: renderConfig)
            requestRedraw()
        }
    }

    public var spacing: CGFloat {
        get {
            stackView.spacing
        }
        set {
            stackView.spacing = newValue
            overlayTextureNeedsUpdate = true
            setNeedsLayout()
        }
    }

    func applyBackgroundConfig(_ config: LiquidGlassConfig) {
        renderConfig = config
        backgroundRenderer.updateSettings(config: renderConfig)
        requestRedraw()
    }

    func applyKnobMotionSettings(_ settings: LiquidGlassKnobMotionSettings) {
        knob.engine.applyMotionSettings(settings)
    }

    func applyKnobVisualConfig(_ config: LiquidGlassConfig) {
        applyKnobVisualConfigInternal(config)
    }

    public func invalidateBackgroundCapture() {
        backgroundCaptureNeedsUpdate = true
        requestRedraw()
    }

    public func invalidateOverlayTexture() {
        overlayTextureNeedsUpdate = true
        requestRedraw()
    }

    public func frameForTab(at index: Int) -> CGRect? {
        guard tabButtons.indices.contains(index) else { return nil }
        return tabButtons[index].convert(tabButtons[index].bounds, to: self)
    }

    // MARK: - LiquidGlassBackground

    var backgroundView: UIView? { self }

    var backgroundTexture: MTLTexture? { renderedTexture }

    let knobLayer = CALayer()

    func setLiquidGlassKnobSink(_ sink: LiquidGlassKnobSink) {
        knobSink = sink
    }

    // MARK: - Private Properties

    private var renderConfig: LiquidGlassConfig
    private var knobVisualConfig: LiquidGlassConfig
    private var knobAppliedConfig: LiquidGlassConfig
    private let metalContext: MetalContext
    private let backgroundRenderer: LiquidGlassRenderer
    private var glassTexture: MTLTexture?
    private var renderedTexture: MTLTexture?
    private var lastCapturedBackgroundTexture: MTLTexture?
    private let textureLoader: MTKTextureLoader
    private let viewCapture: ViewCapture

    private var backgroundCaptureNeedsUpdate: Bool = true

    private let knob: LiquidGlassKnob
    private let knobController: LiquidGlassTabSelectorController
    private let stackView: UIStackView = {
        let tabStack = UIStackView()
        tabStack.axis = .horizontal
        tabStack.spacing = 12
        tabStack.distribution = .fillEqually
        return tabStack
    }()
    private var tabButtons: [UIButton] = []

    private var stackViewTopConstraint: NSLayoutConstraint?
    private var stackViewLeadingConstraint: NSLayoutConstraint?
    private var stackViewTrailingConstraint: NSLayoutConstraint?
    private var stackViewBottomConstraint: NSLayoutConstraint?

    private var dragStartTouchX: CGFloat?
    private var dragStartKnobCenterX: CGFloat?

    private weak var knobSink: LiquidGlassKnobSink?
    private let knobTouchDelegate = LiquidGlassTabBarKnobTouchDelegate()
    private lazy var knobTouchRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleKnobTouch(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = knobTouchDelegate
        return recognizer
    }()

    /// Resting geometry (parameter1). If `nil`, uses the selected tab's frame.
    public var restingKnobSize: CGSize?

    /// Liquid geometry (parameter2). If `nil`, uses an expanded tab frame.
    public var liquidKnobSize: CGSize?

    private lazy var copyPipelineState: MTLRenderPipelineState = {
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.vertexFunction = metalContext.library.makeFunction(name: "liquidGlassVertex")
        desc.fragmentFunction = metalContext.library.makeFunction(name: "liquidGlassCopyFlipYFragment")
        do {
            return try metalContext.device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to build copy pipeline: \(error)")
        }
    }()

    private lazy var premultipliedCompositePipelineState: MTLRenderPipelineState = {
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        desc.vertexFunction = metalContext.library.makeFunction(name: "liquidGlassVertex")
        desc.fragmentFunction = metalContext.library.makeFunction(name: "liquidGlassCopyFlipYFragment")
        do {
            return try metalContext.device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to build premultiplied composite pipeline: \(error)")
        }
    }()

    private lazy var overlaySamplerState: MTLSamplerState = {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .notMipmapped
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        return metalContext.device.makeSamplerState(descriptor: desc)!
    }()

    private var overlayTexture: MTLTexture?
    private var overlayTextureSize: CGSize = .zero
    private var overlayTextureNeedsUpdate = true
    private let compositePassDescriptor = MTLRenderPassDescriptor()
    private let glassPassDescriptor = MTLRenderPassDescriptor()

    // MARK: - Initialization

    public init(metalContext: MetalContext) {
        self.metalContext = metalContext
        let config = LiquidGlassConfig.tabBarBackground
        renderConfig = config
        backgroundRenderer = LiquidGlassRenderer(config: config, metalContext: metalContext)
        textureLoader = MTKTextureLoader(device: metalContext.device)
        viewCapture = ViewCapture(device: metalContext.device, renderingMethod: .layerRender, maxScale: 2)
        knobVisualConfig = .tabBarKnob
        knobAppliedConfig = knobVisualConfig
        knob = LiquidGlassKnob(config: knobAppliedConfig, metalContext: metalContext)
        knobController = LiquidGlassTabSelectorController(engine: knob.engine)
        knob.isUserInteractionEnabled = false
        super.init(frame: .zero, device: metalContext.device)

        isOpaque = false
        enableSetNeedsDisplay = true
        isPaused = true
        preferredFramesPerSecond = 60
        framebufferOnly = true
        backgroundColor = .clear
        clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

        compositePassDescriptor.colorAttachments[0].loadAction = .clear
        compositePassDescriptor.colorAttachments[0].storeAction = .store
        compositePassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        glassPassDescriptor.colorAttachments[0].loadAction = .clear
        glassPassDescriptor.colorAttachments[0].storeAction = .store
        glassPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        setupViews()
        applyKnobMotionSettings(.tabBarKnobMotion)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
    }

    func handleDidBecomeActive() {
        overlayTexture = nil
        overlayTextureNeedsUpdate = true
        backgroundCaptureNeedsUpdate = true
        lastCapturedBackgroundTexture = nil
        requestRedraw()
    }

    // MARK: - Lifecycle

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        backgroundCaptureNeedsUpdate = true
        overlayTextureNeedsUpdate = true
        requestRedraw()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.backgroundCaptureNeedsUpdate = true
            self.overlayTextureNeedsUpdate = true
            self.requestRedraw()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        stackView.layoutIfNeeded()
        overlayTextureNeedsUpdate = true

        layoutKnobLayerForResting()
        if case .resting = knobController.selectorState {
            syncKnobToSelection()
        }

        backgroundCaptureNeedsUpdate = true
        requestRedraw()
    }

    // MARK: - MTKView Drawing

    public override func draw(_ _: CGRect) {
        guard
            let currentDrawable,
            let passDescriptor = currentRenderPassDescriptor,
            let commandBuffer = metalContext.commandQueue.makeCommandBuffer(),
            drawableSize != .zero,
            let captureView,
            let roi = roiProvider?(),
            roi != .zero
        else { return }

        let shouldRecaptureBackground = lastCapturedBackgroundTexture == nil
        || backgroundCaptureNeedsUpdate

        if shouldRecaptureBackground,
           let captured = viewCapture.textureFrom(view: captureView, roi: roi, commandBuffer: commandBuffer) {
            lastCapturedBackgroundTexture = captured
        }

        guard let bgTexture = lastCapturedBackgroundTexture else {
            return
        }

        let contentRect = resolvedContentRect()
        let cornerRadius = min(CGFloat(renderConfig.cornerRadius), min(contentRect.width, contentRect.height) / 2)
        let shape = LiquidGlassShapeState(
            center: CGPoint(x: contentRect.midX, y: contentRect.midY),
            size: contentRect.size,
            cornerRadius: cornerRadius
        )

        createGlassTextureIfNeeded(size: drawableSize)
        guard let glassTexture else { return }
        glassPassDescriptor.colorAttachments[0].texture = glassTexture
        backgroundRenderer.encode(
            in: self,
            commandBuffer: commandBuffer,
            backgroundTexture: bgTexture,
            shape: shape,
            motion: .zero,
            targetRenderPassDescriptor: glassPassDescriptor
        )

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setFragmentSamplerState(overlaySamplerState, index: 0)
            encoder.setRenderPipelineState(copyPipelineState)
            encoder.setFragmentTexture(glassTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        createRenderedTextureIfNeeded(size: drawableSize)
        if let renderedTexture {
            compositePassDescriptor.colorAttachments[0].texture = renderedTexture

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: compositePassDescriptor) {
                encoder.setFragmentSamplerState(overlaySamplerState, index: 0)

                // 1) Start with the captured background so areas outside the pill still contain valid pixels
                // for the knob lens.
                encoder.setRenderPipelineState(copyPipelineState)
                encoder.setFragmentTexture(bgTexture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

                // 2) Composite the rendered tab bar glass (premultiplied alpha) over it.
                encoder.setRenderPipelineState(premultipliedCompositePipelineState)
                encoder.setFragmentTexture(glassTexture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

                // 3) Composite the UIKit overlay (tabs) so the knob can refract/magnify them.
                if let overlayTexture = overlayTextureIfNeeded() {
                    encoder.setRenderPipelineState(premultipliedCompositePipelineState)
                    encoder.setFragmentTexture(overlayTexture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }

                encoder.endEncoding()
            }

            knob.backgroundTexture = renderedTexture
        }

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}

// MARK: - Setup

private extension LiquidGlassTabBar {
    func requestRedraw() {
        guard window != nil else { return }
        setNeedsDisplay()
    }

    func resolvedContentRect() -> CGRect {
        let rect = bounds.inset(by: contentInsets)
        if rect.width <= 0.0 || rect.height <= 0.0 {
            return bounds
        }
        return rect
    }

    func updateContentInsetsConstraints() {
        stackViewTopConstraint?.constant = contentInsets.top
        stackViewLeadingConstraint?.constant = contentInsets.left
        stackViewTrailingConstraint?.constant = -contentInsets.right
        stackViewBottomConstraint?.constant = -contentInsets.bottom
    }

    func setupViews() {
        knob.translatesAutoresizingMaskIntoConstraints = false
        addSubview(knob)
        NSLayoutConstraint.activate([
            knob.topAnchor.constraint(equalTo: topAnchor),
            knob.leadingAnchor.constraint(equalTo: leadingAnchor),
            knob.trailingAnchor.constraint(equalTo: trailingAnchor),
            knob.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        knob.isHidden = true

        // Stack view for tabs at the top
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        let topConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top)
        let leadingConstraint = stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left)
        let trailingConstraint = stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right)
        let bottomConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom)
        stackViewTopConstraint = topConstraint
        stackViewLeadingConstraint = leadingConstraint
        stackViewTrailingConstraint = trailingConstraint
        stackViewBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            topConstraint,
            leadingConstraint,
            trailingConstraint,
            bottomConstraint
        ])

        // The knob lens must render above the tabs so it can refract them (otherwise labels show twice).
        bringSubviewToFront(knob)

        addGestureRecognizer(knobTouchRecognizer)

        knobTouchDelegate.shouldBegin = { [weak self] recognizer in
            guard let self, case .resting = self.knobController.selectorState else { return false }
            let location = recognizer.location(in: self)
            let knobFrame = self.knobLayer.presentation()?.frame ?? self.knobLayer.frame
            return knobFrame.contains(location)
        }

        knobLayer.backgroundColor = pillColor.cgColor
        knobLayer.opacity = 1
        layer.insertSublayer(knobLayer, below: stackView.layer)

        knobController.restingFrameForIndex = { [weak self] index in
            self?.knobFrame(for: index, mode: .resting) ?? .zero
        }
        knobController.liquidFrameForIndex = { [weak self] index in
            self?.knobFrame(for: index, mode: .liquid) ?? .zero
        }
        knobController.staticKnobLayer = knobLayer
        knobController.onSelectionCommit = { [weak self] finalIndex in
            self?.commitSelection(finalIndex)
        }
        knobController.onResting = { [weak self] in
            self?.setInteractionsEnabled(true)
            self?.layoutKnobLayerForResting()
            DispatchQueue.main.async { [weak self] in
                self?.invalidateOverlayTexture()
            }
        }

        setLiquidGlassKnobSink(knobController)
    }

    func rebuildTabs() {
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, tabView) in tabViews.enumerated() {
            let button = UIButton(type: .custom)
            button.backgroundColor = .clear
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)

            tabView.isUserInteractionEnabled = false
            tabView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(tabView)

            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: button.topAnchor),
                tabView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                tabView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                tabView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])

            stackView.addArrangedSubview(button)
            tabButtons.append(button)
        }

        overlayTextureNeedsUpdate = true
        setNeedsLayout()
        if window != nil {
            layoutIfNeeded()
        }
        requestRedraw()
    }

    @objc func tabTapped(_ sender: UIButton) {
        let toIndex = sender.tag
        guard toIndex != selectedIndex, case .resting = knobController.selectorState else { return }
        setInteractionsEnabled(false)
        knobSink?.beginAnimation(fromIndex: selectedIndex, mode: .tap(toIndex: toIndex))
    }

    func layoutKnobLayerForResting() {
        guard selectedIndex >= 0, selectedIndex < tabButtons.count else {
            knobLayer.isHidden = true
            return
        }
        guard case .resting = knobController.selectorState else { return }

        let frame = knobFrame(for: selectedIndex, mode: .resting)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knobLayer.frame = frame
        knobLayer.cornerRadius = frame.height / 2
        knobLayer.opacity = 1
        knobLayer.isHidden = false
        CATransaction.commit()
    }

    func syncKnobToSelection() {
        guard selectedIndex >= 0, selectedIndex < tabButtons.count else { return }
        let liquidFrame = knobFrame(for: selectedIndex, mode: .liquid)
        guard liquidFrame.width > 0, liquidFrame.height > 0 else { return }
        let center = CGPoint(x: liquidFrame.midX, y: liquidFrame.midY)
        knob.snapToSelection(center: center)

        let radius = Float(liquidFrame.height / 2)
        let desired = knobVisualConfig.copyWith(
            shapeWidth: Float(liquidFrame.width),
            shapeHeight: Float(liquidFrame.height),
            cornerRadius: radius
        )
        if desired != knobAppliedConfig {
            knobAppliedConfig = desired
            knob.updateSettings(config: knobAppliedConfig)
        }
        overlayTextureNeedsUpdate = true
        requestRedraw()
    }

    func commitSelection(_ finalIndex: Int) {
        selectedIndex = finalIndex
        onTabSelected?(finalIndex)
        knobSink?.endAnimation(finalIndex: finalIndex)
    }

    func setInteractionsEnabled(_ enabled: Bool) {
        tabButtons.forEach { $0.isUserInteractionEnabled = enabled }
        stackView.isUserInteractionEnabled = enabled
    }

    func createRenderedTextureIfNeeded(size: CGSize) {
        guard size != .zero else { return }
        if let renderedTexture,
           renderedTexture.width == Int(round(size.width)),
           renderedTexture.height == Int(round(size.height)) {
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(round(size.width)),
            height: Int(round(size.height)),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        renderedTexture = metalContext.device.makeTexture(descriptor: descriptor)
    }

    func createGlassTextureIfNeeded(size: CGSize) {
        guard size != .zero else { return }
        if let glassTexture,
           glassTexture.width == Int(round(size.width)),
           glassTexture.height == Int(round(size.height)) {
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(round(size.width)),
            height: Int(round(size.height)),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        glassTexture = metalContext.device.makeTexture(descriptor: descriptor)
    }

    func applyKnobVisualConfigInternal(_ config: LiquidGlassConfig) {
        knobVisualConfig = config
        guard selectedIndex >= 0, selectedIndex < tabButtons.count else { return }
        if case .resting = knobController.selectorState {
            syncKnobToSelection()
        } else {
            let liquidFrame = knobFrame(for: selectedIndex, mode: .liquid)
            guard liquidFrame.width > 0, liquidFrame.height > 0 else { return }
            let radius = Float(liquidFrame.height / 2)
            knobAppliedConfig = knobVisualConfig.copyWith(
                shapeWidth: Float(liquidFrame.width),
                shapeHeight: Float(liquidFrame.height),
                cornerRadius: radius
            )
            knob.updateSettings(config: knobAppliedConfig)
        }
        requestRedraw()
    }

    func overlayTextureIfNeeded() -> MTLTexture? {
        let pixelWidth = Int(round(drawableSize.width))
        let pixelHeight = Int(round(drawableSize.height))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        if !overlayTextureNeedsUpdate,
           overlayTextureSize.width == CGFloat(pixelWidth),
           overlayTextureSize.height == CGFloat(pixelHeight),
           overlayTexture != nil {
            return overlayTexture
        }

        guard window != nil else { return overlayTexture }

        overlayTextureNeedsUpdate = false
        overlayTextureSize = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))

        let scale = max(CGFloat(1), contentScaleFactor)
        let sizePoints = CGSize(width: overlayTextureSize.width / scale, height: overlayTextureSize.height / scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: sizePoints, format: format)
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.clear.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: sizePoints))

            context.cgContext.translateBy(x: stackView.frame.minX, y: stackView.frame.minY)
            stackView.layer.render(in: context.cgContext)
        }

        guard let cgImage = image.cgImage else { return nil }
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false
        ]
        do {
            overlayTexture = try textureLoader.newTexture(cgImage: cgImage, options: options)
        } catch {
            overlayTexture = nil
        }
        return overlayTexture
    }

    enum KnobFrameMode {
        case resting
        case liquid
    }

    func knobFrame(for index: Int, mode: KnobFrameMode) -> CGRect {
        guard tabButtons.indices.contains(index) else { return .zero }
        let base = tabButtons[index].convert(tabButtons[index].bounds, to: self)
        let center = CGPoint(x: base.midX, y: base.midY)
        switch mode {
        case .resting:
            if let restingKnobSize {
                return centeredFrame(size: restingKnobSize, center: center)
            }
            return base
        case .liquid:
            if let liquidKnobSize {
                return centeredFrame(size: liquidKnobSize, center: center)
            }
            return base.insetBy(dx: -base.width * 0.06, dy: -base.height * 0.12)
        }
    }

    func centeredFrame(size: CGSize, center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    @objc func handleKnobTouch(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            guard case .resting = knobController.selectorState else { return }
            setInteractionsEnabled(false)
            dragStartTouchX = location.x
            dragStartKnobCenterX = (knobLayer.presentation()?.frame ?? knobLayer.frame).midX
            knobSink?.beginAnimation(fromIndex: selectedIndex, mode: .pan)
            updateInteractive(touchX: location.x, velocityX: 0)
        case .changed:
            guard allowsPanUpdates(in: knobController.selectorState) else { return }
            updateInteractive(touchX: location.x, velocityX: 0)
        case .ended, .cancelled, .failed:
            guard allowsPanUpdates(in: knobController.selectorState) else { return }
            let rawX = rawKnobCenterX(forTouchX: location.x)
            dragStartTouchX = nil
            dragStartKnobCenterX = nil
            knob.engine.setPullDistance(0)
            let toIndex = nearestTabIndex(toX: clampedX(rawX))
            knobSink?.snap(toIndex: toIndex)
        default:
            break
        }
    }

    func allowsPanUpdates(in state: SelectorState) -> Bool {
        switch state {
        case .transitioningToLiquid(_, target: .interactivePan), .liquidInteractive:
            return true
        default:
            return false
        }
    }

    private func rawKnobCenterX(forTouchX touchX: CGFloat) -> CGFloat {
        guard let dragStartTouchX, let dragStartKnobCenterX else { return touchX }
        return dragStartKnobCenterX + (touchX - dragStartTouchX)
    }

    private func updateInteractive(touchX: CGFloat, velocityX: CGFloat) {
        let rawX = rawKnobCenterX(forTouchX: touchX)
        updateInteractive(rawX: rawX, velocityX: velocityX)
    }

    private func updateInteractive(rawX: CGFloat, velocityX: CGFloat) {
        guard allowsPanUpdates(in: knobController.selectorState) else { return }

        let clamped = clampedX(rawX)
        let overscroll = rawX - clamped
        knob.engine.setPullDistance(overscroll)

        let pullShiftX = overdragCenterShift(for: overscroll)
        knobSink?.updateInteractive(x: clamped + pullShiftX, velocity: velocityX)
    }

    private func overdragCenterShift(for overscroll: CGFloat) -> CGFloat {
        guard abs(overscroll) > 0.001 else { return 0 }
        let sign: CGFloat = overscroll >= 0 ? 1 : -1
        let maxShift: CGFloat = 10
        let response: CGFloat = 20
        let t = 1 - exp(-abs(overscroll) / max(1, response))
        return sign * maxShift * t
    }

    func clampedX(_ x: CGFloat) -> CGFloat {
        guard let first = tabButtons.first,
              let last = tabButtons.last
        else { return x }
        let minX = first.convert(first.bounds, to: self).midX
        let maxX = last.convert(last.bounds, to: self).midX
        return max(minX, min(maxX, x))
    }

    func nearestTabIndex(toX x: CGFloat) -> Int {
        guard !tabButtons.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, button) in tabButtons.enumerated() {
            let centerX = button.convert(button.bounds, to: self).midX
            let distance = abs(centerX - x)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
