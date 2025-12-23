//
//  LiquidGlassConfig.swift
//  liquid-ui-effect-test
//
//  Created by Egor Butyrin on 12/12/2025.
//

import Foundation

public struct LiquidGlassTint: Equatable {
    public let r: Float
    public let g: Float
    public let b: Float
    public let a: Float

    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let clear = LiquidGlassTint(r: 1, g: 1, b: 1, a: 0)
    public static let white = LiquidGlassTint(r: 1, g: 1, b: 1, a: 1)
}

public struct LiquidGlassConfig: Equatable {
    public let refThickness: Float
    public let refFactor: Float
    public let refDispersion: Float
    /// Lens "zoom out" strength (0 = off). Higher values show more of the background within the lens.
    public let zoomOutFactor: Float
    public let refFresnelRange: Float
    public let refFresnelHardness: Float
    public let refFresnelFactor: Float

    public let glareRange: Float
    public let glareHardness: Float
    public let glareFactor: Float
    public let glareConvergence: Float
    public let glareOppositeFactor: Float
    public let glareAngle: Float
    public let glareTint: LiquidGlassTint
    public let glareOppositeTint: LiquidGlassTint

    public let blurRadius: Int
    public let blurEdge: Bool
    public let tint: LiquidGlassTint

    public let shadowExpand: Float
    public let shadowFactor: Float
    public let shadowPosition: SIMD2<Float>

    public let shapeWidth: Float
    public let shapeHeight: Float
    public let cornerRadius: Float
    public let shapeRoundness: Float
    public let mergeRate: Float

    public let springSizeFactor: Float
    public let step: Int

    public init(
        refThickness: Float = 20,
        refFactor: Float = 1.4,
        refDispersion: Float = 7,
        zoomOutFactor: Float = 0,
        refFresnelRange: Float = 30,
        refFresnelHardness: Float = 20,
        refFresnelFactor: Float = 20,
        glareRange: Float = 30,
        glareHardness: Float = 20,
        glareFactor: Float = 90,
        glareConvergence: Float = 50,
        glareOppositeFactor: Float = 80,
        glareAngle: Float = -45,
        glareTint: LiquidGlassTint = .white,
        glareOppositeTint: LiquidGlassTint = .white,
        blurRadius: Int = 8,
        blurEdge: Bool = true,
        tint: LiquidGlassTint = .clear,
        shadowExpand: Float = 0,
        shadowFactor: Float = 0,
        shadowPosition: SIMD2<Float> = .init(0, 0),
        shapeWidth: Float = 200,
        shapeHeight: Float = 200,
        cornerRadius: Float = 80,
        shapeRoundness: Float = 2,
        mergeRate: Float = 0.05,
        springSizeFactor: Float = 10,
        step: Int = 9
    ) {
        self.refThickness = refThickness
        self.refFactor = refFactor
        self.refDispersion = refDispersion
        self.zoomOutFactor = zoomOutFactor
        self.refFresnelRange = refFresnelRange
        self.refFresnelHardness = refFresnelHardness
        self.refFresnelFactor = refFresnelFactor
        self.glareRange = glareRange
        self.glareHardness = glareHardness
        self.glareFactor = glareFactor
        self.glareConvergence = glareConvergence
        self.glareOppositeFactor = glareOppositeFactor
        self.glareAngle = glareAngle
        self.glareTint = glareTint
        self.glareOppositeTint = glareOppositeTint
        self.blurRadius = max(0, min(blurRadius, kMaxBlurRadius))
        self.blurEdge = blurEdge
        self.tint = tint
        self.shadowExpand = shadowExpand
        self.shadowFactor = shadowFactor
        self.shadowPosition = shadowPosition
        self.shapeWidth = shapeWidth
        self.shapeHeight = shapeHeight
        self.cornerRadius = cornerRadius
        self.shapeRoundness = shapeRoundness
        self.mergeRate = mergeRate
        self.springSizeFactor = springSizeFactor
        self.step = step
    }

    public func copyWith(
        refThickness: Float? = nil,
        refFactor: Float? = nil,
        refDispersion: Float? = nil,
        zoomOutFactor: Float? = nil,
        refFresnelRange: Float? = nil,
        refFresnelHardness: Float? = nil,
        refFresnelFactor: Float? = nil,
        glareRange: Float? = nil,
        glareHardness: Float? = nil,
        glareFactor: Float? = nil,
        glareConvergence: Float? = nil,
        glareOppositeFactor: Float? = nil,
        glareAngle: Float? = nil,
        glareTint: LiquidGlassTint? = nil,
        glareOppositeTint: LiquidGlassTint? = nil,
        blurRadius: Int? = nil,
        blurEdge: Bool? = nil,
        tint: LiquidGlassTint? = nil,
        shadowExpand: Float? = nil,
        shadowFactor: Float? = nil,
        shadowPosition: SIMD2<Float>? = nil,
        shapeWidth: Float? = nil,
        shapeHeight: Float? = nil,
        cornerRadius: Float? = nil,
        shapeRoundness: Float? = nil,
        mergeRate: Float? = nil,
        springSizeFactor: Float? = nil,
        step: Int? = nil
    ) -> LiquidGlassConfig {
        LiquidGlassConfig(
            refThickness: refThickness ?? self.refThickness,
            refFactor: refFactor ?? self.refFactor,
            refDispersion: refDispersion ?? self.refDispersion,
            zoomOutFactor: zoomOutFactor ?? self.zoomOutFactor,
            refFresnelRange: refFresnelRange ?? self.refFresnelRange,
            refFresnelHardness: refFresnelHardness ?? self.refFresnelHardness,
            refFresnelFactor: refFresnelFactor ?? self.refFresnelFactor,
            glareRange: glareRange ?? self.glareRange,
            glareHardness: glareHardness ?? self.glareHardness,
            glareFactor: glareFactor ?? self.glareFactor,
            glareConvergence: glareConvergence ?? self.glareConvergence,
            glareOppositeFactor: glareOppositeFactor ?? self.glareOppositeFactor,
            glareAngle: glareAngle ?? self.glareAngle,
            glareTint: glareTint ?? self.glareTint,
            glareOppositeTint: glareOppositeTint ?? self.glareOppositeTint,
            blurRadius: blurRadius ?? self.blurRadius,
            blurEdge: blurEdge ?? self.blurEdge,
            tint: tint ?? self.tint,
            shadowExpand: shadowExpand ?? self.shadowExpand,
            shadowFactor: shadowFactor ?? self.shadowFactor,
            shadowPosition: shadowPosition ?? self.shadowPosition,
            shapeWidth: shapeWidth ?? self.shapeWidth,
            shapeHeight: shapeHeight ?? self.shapeHeight,
            cornerRadius: cornerRadius ?? self.cornerRadius,
            shapeRoundness: shapeRoundness ?? self.shapeRoundness,
            mergeRate: mergeRate ?? self.mergeRate,
            springSizeFactor: springSizeFactor ?? self.springSizeFactor,
            step: step ?? self.step
        )
    }
}

extension LiquidGlassConfig {
    public static let sliderKnob = LiquidGlassConfig(
        refThickness: 30,
        refFactor: 1.05,
        refDispersion: 8,
        zoomOutFactor: 0.5,
        refFresnelRange: 20,
        refFresnelHardness: 48,
        refFresnelFactor: 10,

        glareRange: 28,
        glareHardness: 0,
        glareFactor: 40,
        glareConvergence: 26,
        glareOppositeFactor: 1,
        glareAngle: -40,
        glareTint: LiquidGlassTint(r: 0, g: 0, b: 0, a: 0.42),
        glareOppositeTint: LiquidGlassTint(r: 1, g: 1, b: 1, a: 1),

        blurRadius: 0,

        shadowExpand: 3,
        shadowFactor: 10,
        shadowPosition: .init(0, 5)
    )

    public static let switchKnob = LiquidGlassConfig(
        refThickness: 40,
        refFactor: 1.01,
        refDispersion: 8,
        zoomOutFactor: 1.26,
        refFresnelRange: 20,
        refFresnelHardness: 48,
        refFresnelFactor: 10,

        glareRange: 28,
        glareHardness: 0,
        glareFactor: 40,
        glareConvergence: 26,
        glareOppositeFactor: 1,
        glareAngle: -40,
        glareTint: LiquidGlassTint(r: 0, g: 0, b: 0, a: 0.42),
        glareOppositeTint: LiquidGlassTint(r: 1, g: 1, b: 1, a: 1),

        blurRadius: 0,

        shadowExpand: 2,
        shadowFactor: 8,
        shadowPosition: .init(0, 5)
    )

    static let tabBarKnob = LiquidGlassConfig(
        refThickness: 20,
        refFactor: 1.4,
        refDispersion: 3,
        zoomOutFactor: 0.0,
        glareRange: 0,
        blurRadius: 0,
        shadowExpand: 2,
        shadowFactor: 8,
        shadowPosition: SIMD2<Float>(0, 5),
        shapeRoundness: 2
    )

    static let tabBarBackground = LiquidGlassConfig(
        refThickness: 20,
        refFactor: 1.6,

        glareRange: 28,
        glareHardness: 0,
        glareFactor: 40,
        glareConvergence: 26,
        glareOppositeFactor: 1,
        glareAngle: -40,
        glareTint: LiquidGlassTint(r: 1, g: 1, b: 1, a: 1),
        glareOppositeTint: LiquidGlassTint(r: 1, g: 1, b: 1, a: 1),

        blurRadius: 20,
        tint: LiquidGlassTint(r: 1, g: 1, b: 1, a: 0.5),
        shadowExpand: 2,
        shadowFactor: 10,
        shapeRoundness: 2
    )
}

extension LiquidGlassKnobMotionSettings {
    static let sliderKnobMotion: LiquidGlassKnobMotionSettings = LiquidGlassKnobMotionSettings()
    static let switchKnobMotion: LiquidGlassKnobMotionSettings = LiquidGlassKnobMotionSettings(
        engine: LiquidGlassKnobEngineTuning(),
        travelTiming: LiquidGlassEaseInOutTimingTuning(),
        motion: LiquidGlassMotionTuning(
            maxStretch: 0.05,
            pullDistanceForMaxStretch: 500
        )
    )
    static let tabBarKnobMotion: LiquidGlassKnobMotionSettings = LiquidGlassKnobMotionSettings(
        engine: LiquidGlassKnobEngineTuning(
            transitionDuration: 0.26,
            reverseTransitionDuration: 0.26,
            minTravelDuration: 0.15,
            maxTravelDuration: 0.5,
            durationDistanceNormalization: 260
        ),
        travelTiming: LiquidGlassEaseInOutTimingTuning(
            anticipationFraction: 0.0,
            overshootFraction: 0.0,
            maxOvershootPoints: 0,
            overshootTimeFraction: 0.6
        ),
        motion: LiquidGlassMotionTuning(
            pullDistanceForMaxStretch: 300
        )
    )
}
