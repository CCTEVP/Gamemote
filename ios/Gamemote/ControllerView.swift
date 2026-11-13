import SwiftUI
import RealityKit
import UIKit

/// Where the controller's parts sit, in table units (x right, z towards the bottom of the
/// screen, y up). Mirrors the Godot app's "sideways" and compact layouts.
struct ControllerLayout: Equatable {
    var bodySize: SIMD2<Float>          // x, z of the centre slab
    var roundEnds: Bool                 // pill ends + grips + shoulder bumps (handheld look)
    var stick: SIMD2<Float>
    var buttons: SIMD2<Float>           // diamond centre
    var spread: Float
    var stop: SIMD2<Float>
    var screen: SIMD2<Float>?           // centre of the console recess (sideways only)
    var screenSize: SIMD2<Float>
    var content: SIMD2<Float>           // area the camera keeps in view

    /// Landscape handheld: grips, shoulder bumps, console screen in the middle (reference photo).
    static let sideways = ControllerLayout(
        bodySize: [6.4, 3.4], roundEnds: true, stick: [-3.05, -0.1], buttons: [3.05, -0.1],
        spread: 0.62, stop: [0, 1.3], screen: [0, -0.35], screenSize: [4.0, 2.2], content: [10.6, 4.9])

    /// Upright: a compact body only as tall as its controls; STOP between stick and buttons.
    static let compact = ControllerLayout(
        bodySize: [6.4, 3.0], roundEnds: false, stick: [-1.9, 0.0], buttons: [1.9, 0.0],
        spread: 0.62, stop: [0, 0.45], screen: nil, screenSize: .zero, content: [6.8, 3.4])
}

/// The 3D clay controller. Reports stick, button and STOP input, and where the console screen
/// recess is on screen (so SwiftUI can draw the console there).
struct ControllerView: UIViewRepresentable {
    var layout: ControllerLayout
    /// Which of the four face buttons (X, B, A, Y) do something on the gadget.
    var enabled: [Bool]
    var onStick: (SIMD2<Float>) -> Void
    var onButton: (Int, Bool) -> Void
    var onStop: () -> Void
    var onScreenRect: (CGRect) -> Void = { _ in }

    func makeUIView(context: Context) -> ControllerARView {
        let view = ControllerARView(layout: layout)
        update(view)
        return view
    }

    func updateUIView(_ view: ControllerARView, context: Context) {
        if view.layout != layout { view.rebuild(layout) }
        update(view)
    }

    private func update(_ view: ControllerARView) {
        view.onStick = onStick
        view.onButton = onButton
        view.onStop = onStop
        view.onScreenRect = onScreenRect
        view.setEnabled(enabled)
    }
}

final class ControllerARView: ARView {
    static let top: Float = 0.6              // body top surface
    static let stickReach: Float = 0.9       // finger travel for full deflection
    static let stickHit: Float = 1.25
    static let buttonRadius: Float = 0.3
    static let stopRadius: Float = 0.42
    static let pressDepth: Float = 0.09
    static let deadzone: Float = 0.12
    static let tiltDegrees: Float = 12
    static let fovDegrees: Float = 20
    /// Diamond order: top X, right B, bottom A, left Y. Slot i drives binding i.
    static let letters = ["X", "B", "A", "Y"]
    static let offsets: [SIMD2<Float>] = [[0, -1], [1, 0], [0, 1], [-1, 0]]
    static let colors = [Clay.orange, Clay.teal, Clay.coral, Clay.yellow]

    private(set) var layout: ControllerLayout
    var onStick: (SIMD2<Float>) -> Void = { _ in }
    var onButton: (Int, Bool) -> Void = { _, _ in }
    var onStop: () -> Void = {}
    var onScreenRect: (CGRect) -> Void = { _ in }

    private let root = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var controller = Entity()
    private var stickKnob = Entity()
    private var buttonCaps: [ModelEntity] = []
    private var stopCap = Entity()
    private var enabled = [true, true, true, true]
    private enum Owner: Equatable { case stick, button(Int), stop }
    private var owners: [ObjectIdentifier: Owner] = [:]
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var lastScreenRect = CGRect.null

    init(layout: ControllerLayout) {
        self.layout = layout
        super.init(frame: .zero)
        automaticallyConfigureSession = false
        cameraMode = .nonAR
        isMultipleTouchEnabled = true
        environment.background = .color(Clay.table)
        camera.camera.fieldOfViewInDegrees = Self.fovDegrees
        root.addChild(camera)

        let sun = DirectionalLight()
        sun.light.intensity = 2500
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2)
        sun.look(at: .zero, from: [-4, 12, -6], relativeTo: nil)
        root.addChild(sun)

        let table = ModelEntity(mesh: .generatePlane(width: 200, depth: 200),
                                materials: [Self.clay(Clay.table)])
        table.position.y = -0.01
        root.addChild(table)
        scene.addAnchor(root)
        rebuild(layout)
    }

    required init(frame frameRect: CGRect) { fatalError("use init(layout:)") }
    required init?(coder decoder: NSCoder) { fatalError("use init(layout:)") }

    // MARK: building

    static func clay(_ color: UIColor) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: 0.95, isMetallic: false)
    }

    private func disc(radius: Float, height: Float, color: UIColor) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [Self.clay(color)])
        e.position.y = height / 2
        return e
    }

    /// Flat text lying on a surface, centred on `at`, readable from above.
    private func label(_ text: String, size: CGFloat, color: UIColor, at: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.02,
                                             font: .systemFont(ofSize: size, weight: .heavy))
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        let c = mesh.bounds.center
        e.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        e.position = at + SIMD3(-c.x, 0, c.y)
        return e
    }

    func rebuild(_ newLayout: ControllerLayout) {
        layout = newLayout
        controller.removeFromParent()
        controller = Entity()
        buttonCaps = []
        let L = layout
        let top = Self.top

        // Body: a slab, plus pill ends, grips and shoulder bumps for the handheld look.
        let slab = ModelEntity(mesh: .generateBox(size: [L.bodySize.x, top, L.bodySize.y], cornerRadius: 0.28),
                               materials: [Self.clay(Clay.body)])
        slab.position.y = top / 2
        controller.addChild(slab)
        if L.roundEnds {
            for side: Float in [-1, 1] {
                let end = disc(radius: L.bodySize.y / 2, height: top, color: Clay.body)
                end.position.x = side * L.bodySize.x / 2
                controller.addChild(end)
                let grip = disc(radius: 1.2, height: top * 0.95, color: Clay.body)
                grip.position += [side * 3.5, 0, 1.3]
                controller.addChild(grip)
                let bump = ModelEntity(mesh: .generateBox(size: [1.7, top * 1.05, 0.7], cornerRadius: 0.3),
                                       materials: [Self.clay(Clay.body)])
                bump.position = [side * 3.1, top * 0.52, -L.bodySize.y / 2 - 0.05]
                controller.addChild(bump)
            }
        }

        // Console recess (sideways): SwiftUI draws the console exactly over it.
        if let s = L.screen {
            let recess = ModelEntity(mesh: .generateBox(size: [L.screenSize.x + 0.12, 0.04, L.screenSize.y + 0.12],
                                                        cornerRadius: 0.02),
                                     materials: [SimpleMaterial(color: Clay.screen, roughness: 0.3, isMetallic: false)])
            recess.position = [s.x, top + 0.01, s.y]
            controller.addChild(recess)
        }

        // Stick: a low teal ring, and a knob that moves with the finger.
        let ring = disc(radius: 0.8, height: 0.08, color: Clay.tealDark)
        ring.position += [L.stick.x, top, L.stick.y]
        controller.addChild(ring)
        stickKnob = Entity()
        stickKnob.position = [L.stick.x, top, L.stick.y]
        let shaft = disc(radius: 0.28, height: 0.35, color: Clay.teal)
        stickKnob.addChild(shaft)
        let cap = disc(radius: 0.62, height: 0.16, color: Clay.teal)
        cap.position.y += 0.33
        stickKnob.addChild(cap)
        controller.addChild(stickKnob)

        // Face buttons with big letters.
        for i in 0..<4 {
            let c = L.buttons + Self.offsets[i] * L.spread
            let button = disc(radius: Self.buttonRadius, height: 0.25, color: Self.colors[i])
            let holder = Entity()
            holder.position = [c.x, top, c.y]
            holder.addChild(button)
            holder.addChild(label(Self.letters[i], size: 0.36, color: Clay.ink, at: [0, 0.27, 0]))
            controller.addChild(holder)
            buttonCaps.append(button)
        }

        // STOP: clearly red, one tap.
        stopCap = Entity()
        stopCap.position = [L.stop.x, top, L.stop.y]
        stopCap.addChild(disc(radius: Self.stopRadius, height: 0.25, color: Clay.red))
        stopCap.addChild(label("STOP", size: 0.2, color: .white, at: [0, 0.27, 0]))
        controller.addChild(stopCap)

        root.addChild(controller)
        setEnabled(enabled)
        setNeedsLayout()
    }

    func setEnabled(_ flags: [Bool]) {
        enabled = flags
        for (i, cap) in buttonCaps.enumerated() {
            cap.model?.materials = [Self.clay(flags.indices.contains(i) && flags[i] ? Self.colors[i] : Clay.disabled)]
        }
    }

    // MARK: camera

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let aspect = Float(bounds.width / bounds.height)
        let halfFov = Self.fovDegrees * .pi / 360
        let needH = max(layout.content.y, layout.content.x / aspect)
        let distance = needH / (2 * tan(halfFov))
        let tilt = Self.tiltDegrees * .pi / 180
        camera.look(at: .zero, from: [0, distance * cos(tilt), distance * sin(tilt)], upVector: [0, 0, -1], relativeTo: nil)
        reportScreenRect()
    }

    private func reportScreenRect() {
        guard let s = layout.screen else { return }
        let h = layout.screenSize / 2
        let corners: [SIMD3<Float>] = [[s.x - h.x, Self.top, s.y - h.y], [s.x + h.x, Self.top, s.y + h.y]]
        let points = corners.compactMap { project($0) }
        guard points.count == 2 else { return }
        let rect = CGRect(x: points[0].x, y: points[0].y,
                          width: points[1].x - points[0].x, height: points[1].y - points[0].y).standardized
        guard rect != lastScreenRect else { return }
        lastScreenRect = rect
        DispatchQueue.main.async { [weak self] in self?.onScreenRect(rect) }
    }

    // MARK: touch

    /// Where a screen point lands on the body's top surface, in layout units (x, z).
    private func tablePoint(_ p: CGPoint) -> SIMD2<Float>? {
        guard let ray = ray(through: p), abs(ray.direction.y) > 1e-4 else { return nil }
        let t = (Self.top - ray.origin.y) / ray.direction.y
        let hit = ray.origin + ray.direction * t
        return [hit.x, hit.z]
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let q = tablePoint(touch.location(in: self)) else { continue }
            let key = ObjectIdentifier(touch)
            if simd_distance(q, layout.stick) <= Self.stickHit, !owners.values.contains(.stick) {
                owners[key] = .stick
                moveStick(q)
            } else if simd_distance(q, layout.stop) <= Self.stopRadius * 1.3 {
                owners[key] = .stop
                press(stopCap, true)
                haptic.impactOccurred()
                onStop()
            } else if let i = (0..<4).first(where: {
                enabled[$0] && simd_distance(q, layout.buttons + Self.offsets[$0] * layout.spread) <= Self.buttonRadius * 1.4
            }) {
                owners[key] = .button(i)
                press(buttonCaps[i].parent, true)
                haptic.impactOccurred()
                onButton(i, true)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where owners[ObjectIdentifier(touch)] == .stick {
            if let q = tablePoint(touch.location(in: self)) { moveStick(q) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches {
            switch owners.removeValue(forKey: ObjectIdentifier(touch)) {
            case .stick:
                stickKnob.move(to: Transform(translation: [layout.stick.x, Self.top, layout.stick.y]),
                               relativeTo: controller, duration: 0.18, timingFunction: .easeOut)
                onStick(.zero)
            case .button(let i):
                press(buttonCaps[i].parent, false)
                onButton(i, false)
            case .stop:
                press(stopCap, false)
            case nil:
                break
            }
        }
    }

    /// Releases every held control (rotation, leaving Live).
    func releaseAll() {
        for (_, owner) in owners {
            if case .button(let i) = owner { onButton(i, false) }
        }
        owners = [:]
        onStick(.zero)
    }

    private func moveStick(_ q: SIMD2<Float>) {
        var d = (q - layout.stick) / Self.stickReach
        if simd_length(d) > 1 { d = simd_normalize(d) }
        stickKnob.position = [layout.stick.x + d.x * 0.35, Self.top, layout.stick.y + d.y * 0.35]
        let value = simd_length(d) < Self.deadzone ? SIMD2<Float>.zero : SIMD2(d.x, -d.y)
        onStick(value)
    }

    private func press(_ entity: Entity?, _ down: Bool) {
        guard let entity else { return }
        entity.position.y = Self.top - (down ? Self.pressDepth : 0)
    }
}
