import SwiftUI
import RealityKit
import ValigiaCore

/// 3D suitcase generated in code (RealityKit, no assets): rotate it with a finger,
/// ticked items fly in (or out in unpacking rounds), the content rises with the
/// fill level, the lid closes with its zipper at 100% and reopens when emptied.
/// Respects "Reduce Motion": no flying items, the lid moves without animation.
struct ThreeDLuggageVisual: LuggageVisual {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.m3) private var m3
    let state: LuggageFillState
    let lastEvents: [PackingEvent]
    let eventID: UUID?
    let size: CGFloat

    @State private var scene = LuggageScene()
    @State private var baseYaw: Float = -0.45
    @State private var basePitch: Float = 0.42
    @GestureState private var drag: CGSize = .zero

    init(state: LuggageFillState, lastEvents: [PackingEvent], eventID: UUID?, size: CGFloat) {
        self.state = state
        self.lastEvents = lastEvents
        self.eventID = eventID
        self.size = size
    }

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            setUp(content)
        }
        .frame(height: size)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(rotateGesture)
        .onTapGesture(count: 2, perform: resetRotation)
        .onChange(of: drag) { _, d in dragChanged(d) }
        .onChange(of: state) { _, s in scene.apply(s, animated: !reduceMotion) }
        .onChange(of: eventID) { _, _ in playEvents() }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Trascina per ruotarla, tocca due volte per raddrizzarla")
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($drag) { value, s, _ in s = value.translation }
            .onEnded { value in
                let w = Float(value.translation.width)
                let h = Float(value.translation.height)
                baseYaw += w * 0.01
                basePitch = clampPitch(basePitch + h * 0.006)
            }
    }

    private func resetRotation() {
        baseYaw = -0.45
        basePitch = 0.42
        scene.setRotation(yaw: baseYaw, pitch: basePitch, animated: !reduceMotion)
    }

    private func dragChanged(_ d: CGSize) {
        let yaw: Float = baseYaw + Float(d.width) * 0.01
        let pitch: Float = clampPitch(basePitch + Float(d.height) * 0.006)
        scene.setRotation(yaw: yaw, pitch: pitch)
    }

    private func playEvents() {
        guard !reduceMotion else { return }
        for e in lastEvents {
            if let motion = e.motion { scene.flyItem(motion) }
        }
    }

    private var accessibilityText: String {
        let closed = state.isClosed ? ", chiusa" : ""
        return "Valigia 3D \(state.name): \(state.progress.packed) su \(state.progress.total)" + closed
    }

    private func setUp(_ content: RealityViewCameraContent) {
        let color = UIColor(Color(hex: state.colorHex))
        let accent = UIColor(m3.error)
        scene.build(kind: state.kind, color: color, accent: accent)
        content.add(scene.root)
        content.add(scene.cameraEntity)
        for light in scene.lights { content.add(light) }
        scene.apply(state, animated: false)
        scene.setRotation(yaw: baseYaw, pitch: basePitch)
    }

    private func clampPitch(_ p: Float) -> Float { min(1.1, max(-0.2, p)) }
}

/// Entities of the 3D suitcase. Sizes in metres; origin at the centre of the bottom.
@MainActor
final class LuggageScene {
    let root = Entity()
    let cameraEntity = PerspectiveCamera()
    private(set) var lights: [Entity] = []

    private let pivot = Entity()          // rotated by the finger
    private let lidHinge = Entity()       // rotates around the back top edge
    private let content = Entity()        // anchor on the floor, scaled in y
    private var contentBox = ModelEntity()
    private var zipperPull = ModelEntity()
    private var contentMaterial = SimpleMaterial()
    private var overMaterial = SimpleMaterial()
    private var built = false
    private var lidClosed: Bool?

    // Shape
    private let width: Float = 0.56
    private let depth: Float = 0.36
    private let height: Float = 0.20
    private let wall: Float = 0.018
    private let lidHeight: Float = 0.05
    private let openAngle: Float = -1.95   // radians, lid open towards the back

    private var innerHeight: Float { height - wall }

    func build(kind: LuggageKind, color: UIColor, accent: UIColor) {
        guard !built else { return }
        built = true
        root.addChild(pivot)

        let shell = SimpleMaterial(color: color, roughness: 0.45, isMetallic: false)
        let dark = SimpleMaterial(color: color.mixed(with: .black, amount: 0.45), roughness: 0.6, isMetallic: false)
        let lining = SimpleMaterial(color: color.mixed(with: .white, amount: 0.75), roughness: 0.9, isMetallic: false)
        contentMaterial = SimpleMaterial(color: color.mixed(with: .white, amount: 0.45), roughness: 0.8, isMetallic: false)
        overMaterial = SimpleMaterial(color: accent, roughness: 0.6, isMetallic: false)
        let metal = SimpleMaterial(color: .lightGray, roughness: 0.25, isMetallic: true)

        // Open box made of five slabs.
        func slab(_ w: Float, _ h: Float, _ d: Float, _ pos: SIMD3<Float>, _ m: SimpleMaterial, radius: Float = 0.006) -> ModelEntity {
            let e = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: radius), materials: [m])
            e.position = pos
            pivot.addChild(e)
            return e
        }
        _ = slab(width, wall, depth, [0, wall / 2, 0], shell)
        _ = slab(width, height, wall, [0, height / 2, depth / 2 - wall / 2], shell)
        _ = slab(width, height, wall, [0, height / 2, -depth / 2 + wall / 2], shell)
        _ = slab(wall, height, depth, [width / 2 - wall / 2, height / 2, 0], shell)
        _ = slab(wall, height, depth, [-width / 2 + wall / 2, height / 2, 0], shell)
        // Inner lining on the floor
        _ = slab(width - wall * 2.2, 0.004, depth - wall * 2.2, [0, wall + 0.002, 0], lining, radius: 0)
        // Zipper track around the rim
        _ = slab(width + 0.004, 0.008, 0.012, [0, height - 0.004, depth / 2 - 0.004], dark, radius: 0.003)
        _ = slab(0.012, 0.008, depth + 0.004, [width / 2 - 0.004, height - 0.004, 0], dark, radius: 0.003)
        _ = slab(0.012, 0.008, depth + 0.004, [-width / 2 + 0.004, height - 0.004, 0], dark, radius: 0.003)

        // Content: grows from the floor with the fill level.
        contentBox = ModelEntity(mesh: .generateBox(width: width - wall * 3, height: innerHeight, depth: depth - wall * 3, cornerRadius: 0.02), materials: [contentMaterial])
        contentBox.position = [0, innerHeight / 2, 0]
        content.addChild(contentBox)
        content.position = [0, wall, 0]
        content.scale = [1, 0.001, 1]
        pivot.addChild(content)

        // Handle on the front.
        let handle = ModelEntity(mesh: .generateBox(width: 0.14, height: 0.022, depth: 0.03, cornerRadius: 0.01), materials: [dark])
        handle.position = [0, height * 0.55, depth / 2 + 0.03]
        pivot.addChild(handle)
        for x in [-0.06, 0.06] as [Float] {
            let post = ModelEntity(mesh: .generateBox(width: 0.016, height: 0.022, depth: 0.03, cornerRadius: 0.004), materials: [dark])
            post.position = [x, height * 0.55, depth / 2 + 0.012]
            pivot.addChild(post)
        }

        // Wheels for a trolley, feet for the rest.
        if kind == .trolley || kind == .suitcase {
            for x in [-width / 2 + 0.05, width / 2 - 0.05] {
                for z in [-depth / 2 + 0.05, depth / 2 - 0.05] {
                    let wheel = ModelEntity(mesh: .generateSphere(radius: 0.022), materials: [dark])
                    wheel.position = [x, -0.012, z]
                    pivot.addChild(wheel)
                }
            }
        }

        // Lid: hinge at the back top edge, the lid extends forwards from it.
        lidHinge.position = [0, height, -depth / 2]
        pivot.addChild(lidHinge)
        let lid = ModelEntity(mesh: .generateBox(width: width, height: lidHeight, depth: depth, cornerRadius: 0.03), materials: [shell])
        lid.position = [0, lidHeight / 2, depth / 2]
        lidHinge.addChild(lid)
        // Straps on the lid
        for x in [-width * 0.22, width * 0.22] {
            let strap = ModelEntity(mesh: .generateBox(width: 0.035, height: 0.004, depth: depth + 0.002, cornerRadius: 0.002), materials: [dark])
            strap.position = [x, lidHeight + 0.001, depth / 2]
            lidHinge.addChild(strap)
        }
        // Zipper pull: slides along the front when the lid closes.
        zipperPull = ModelEntity(mesh: .generateBox(width: 0.02, height: 0.012, depth: 0.03, cornerRadius: 0.004), materials: [metal])
        zipperPull.position = [-width / 2 + 0.03, height + 0.002, depth / 2 + 0.01]
        pivot.addChild(zipperPull)

        // Camera and lights.
        cameraEntity.camera.fieldOfViewInDegrees = 34
        cameraEntity.look(at: [0, 0.1, 0], from: [0, 0.75, 1.15], relativeTo: nil)

        let key = DirectionalLight()
        key.light.intensity = 4200
        key.look(at: .zero, from: [0.6, 1.2, 0.9], relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 1600
        fill.look(at: .zero, from: [-0.8, 0.5, 0.4], relativeTo: nil)
        let back = DirectionalLight()
        back.light.intensity = 900
        back.look(at: .zero, from: [0, 0.6, -1], relativeTo: nil)
        lights = [key, fill, back]

        root.position = [0, -0.06, 0]
        lidHinge.orientation = simd_quatf(angle: openAngle, axis: [1, 0, 0])
        lidClosed = false
    }

    func setRotation(yaw: Float, pitch: Float, animated: Bool = false) {
        let q = simd_quatf(angle: pitch * 0.5, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
        if animated {
            var t = pivot.transform
            t.rotation = q
            _ = pivot.move(to: t, relativeTo: pivot.parent, duration: 0.45, timingFunction: .easeInOut)
        } else {
            pivot.orientation = q
        }
    }

    /// Fill level, overweight color and lid.
    func apply(_ s: LuggageFillState, animated: Bool) {
        guard built else { return }
        let level = Float(max(0.001, min(1, s.fillLevel)))
        contentBox.model?.materials = [s.isOverweight ? overMaterial : contentMaterial]
        var t = content.transform
        t.scale = [1, level * 0.92, 1]
        if animated {
            _ = content.move(to: t, relativeTo: content.parent, duration: 0.5, timingFunction: .easeOut)
        } else {
            content.transform = t
        }
        setLid(closed: s.isClosed, animated: animated)
    }

    private func setLid(closed: Bool, animated: Bool) {
        guard lidClosed != closed else { return }
        lidClosed = closed
        var t = lidHinge.transform
        t.rotation = simd_quatf(angle: closed ? 0 : openAngle, axis: [1, 0, 0])
        var zip = zipperPull.transform
        zip.translation.x = closed ? width / 2 - 0.03 : -width / 2 + 0.03
        if animated {
            _ = lidHinge.move(to: t, relativeTo: lidHinge.parent, duration: closed ? 0.7 : 0.6, timingFunction: .easeInOut)
            // The zipper runs once the lid has landed.
            let pull = zipperPull
            let parent = zipperPull.parent
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(closed ? 650 : 0))
                _ = pull.move(to: zip, relativeTo: parent, duration: closed ? 0.55 : 0.3, timingFunction: .easeInOut)
            }
        } else {
            lidHinge.transform = t
            zipperPull.transform = zip
        }
    }

    /// A small parcel flies into the bag (or out of it).
    func flyItem(_ motion: ItemMotion) {
        guard built else { return }
        let colors: [UIColor] = [.systemOrange, .systemTeal, .systemPink, .systemYellow, .systemIndigo, .systemGreen, .white]
        let mat = SimpleMaterial(color: colors.randomElement() ?? .white, roughness: 0.7, isMetallic: false)
        let parcel = ModelEntity(mesh: .generateBox(width: 0.07, height: 0.045, depth: 0.05, cornerRadius: 0.012), materials: [mat])
        let x = Float.random(in: -width * 0.3...width * 0.3)
        let z = Float.random(in: -depth * 0.25...depth * 0.25)
        let inside = Transform(scale: [0.4, 0.4, 0.4], rotation: simd_quatf(angle: .random(in: -1...1), axis: [0, 1, 0]), translation: [x * 0.6, height * 0.6, z * 0.6])
        let above = Transform(scale: [1, 1, 1], rotation: simd_quatf(angle: .random(in: -0.6...0.6), axis: [0, 0, 1]), translation: [x, height + 0.32, z + 0.05])
        parcel.transform = motion == .enter ? above : inside
        pivot.addChild(parcel)
        _ = parcel.move(to: motion == .enter ? inside : above, relativeTo: pivot, duration: 0.55, timingFunction: .easeIn)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(560))
            var gone = parcel.transform
            gone.scale = [0.01, 0.01, 0.01]
            _ = parcel.move(to: gone, relativeTo: parcel.parent, duration: 0.15, timingFunction: .easeOut)
            try? await Task.sleep(for: .milliseconds(170))
            parcel.removeFromParent()
        }
    }
}

private extension UIColor {
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = min(1, max(0, amount))
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k, alpha: 1)
    }
}
