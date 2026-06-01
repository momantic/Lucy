import Cocoa
import SceneKit

enum LucyPounceVisualPhase {
    case normal
    case crouch
    case stretch
    case land
}


class LucySceneView: SCNView {
    var containerNode = SCNNode()
    var modelNode = SCNNode()
    var idleTimer: Timer?
    var lookTargetX: CGFloat = 0
    var lookTargetY: CGFloat = 0
    var curiosityOffsetX: CGFloat = 0
    var curiosityOffsetY: CGFloat = 0
    var targetCuriosityOffsetX: CGFloat = 0
    var targetCuriosityOffsetY: CGFloat = 0
    var nextFidgetTime: TimeInterval = 0
    var runEnergy: CGFloat = 0
    var baseModelScale = SCNVector3(1, 1, 1)
    var hopImpulse: CGFloat = 0
    var nextMicroHopTime: TimeInterval = 0
    var settleEnergy: CGFloat = 0
    var lastAttention: CGFloat = 0
    var pauseAliveMotion = false
    var pounceVisualPhase: LucyPounceVisualPhase = .normal
    var onDoubleClick: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var modelLoaded = false

    override init(frame frameRect: NSRect, options: [String : Any]? = nil) {
        super.init(frame: frameRect, options: options)
        setupScene()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScene()
    }

    deinit {
        idleTimer?.invalidate()
    }

    func setupScene() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        backgroundColor = .clear
        allowsCameraControl = false

        let scene = SCNScene()
        self.scene = scene

        scene.rootNode.addChildNode(containerNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 5.0
        cameraNode.position = SCNVector3(0, 0, 8)
        scene.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 850
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1200
        key.position = SCNVector3(0, 3, 6)
        scene.rootNode.addChildNode(key)

        loadModel()
        startIdle()
    }


    func addFallbackCube(reason: String) {
        print("LucySceneView fallback cube: \(reason)")

        let box = SCNBox(width: 1.4, height: 1.4, length: 1.4, chamferRadius: 0.15)
        box.firstMaterial?.diffuse.contents = NSColor.systemPurple
        box.firstMaterial?.emission.contents = NSColor.systemPink

        let cube = SCNNode(geometry: box)
        cube.name = "LucyFallbackCube"
        modelNode = cube
        containerNode.addChildNode(cube)
    }


    func loadModel() {
        let modelURL = LucyPaths.root
            .appendingPathComponent("assets")
            .appendingPathComponent("scenekit")
            .appendingPathComponent("lucy_spider_v1.obj")

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            addFallbackCube(reason: "model missing at \(modelURL.path)")
            return
        }

        do {
            let loadedScene = try SCNScene(url: modelURL, options: nil)

            let modelContainer = SCNNode()
            for child in loadedScene.rootNode.childNodes {
                modelContainer.addChildNode(child.clone())
            }

            if modelContainer.childNodes.isEmpty {
                addFallbackCube(reason: "DAE loaded but had zero child nodes")
                return
            }

            normalize(node: modelContainer)
            baseModelScale = modelContainer.scale
            applyFallbackMaterials(to: modelContainer)

            // Base orientation for Blender/OBJ converted Lucy.
            // X lays the model into the SceneKit camera view.
            // Y turns her so she faces the user instead of facing sideways.
            modelContainer.eulerAngles.x = CGFloat(-Double.pi / 2)
            modelContainer.eulerAngles.y = CGFloat(-Double.pi / 2)

            modelLoaded = true
            modelNode = modelContainer
            containerNode.addChildNode(modelNode)
        } catch {
            addFallbackCube(reason: "failed to load model: \(error.localizedDescription)")
        }
    }


    func applyFallbackMaterials(to node: SCNNode) {
        let textureURL = LucyPaths.root
            .appendingPathComponent("assets")
            .appendingPathComponent("scenekit")
            .appendingPathComponent("textures")
            .appendingPathComponent("cute+jumping+spider+3d+model_basecolor.png")

        let normalURL = LucyPaths.root
            .appendingPathComponent("assets")
            .appendingPathComponent("scenekit")
            .appendingPathComponent("textures")
            .appendingPathComponent("cute+jumping+spider+3d+model_normal.png")

        let baseColorImage = NSImage(contentsOf: textureURL)
        let normalImage = NSImage(contentsOf: normalURL)

        let fallbackMaterial = SCNMaterial()
        fallbackMaterial.name = "LucyOriginalTextureMaterial"

        if let baseColorImage {
            fallbackMaterial.diffuse.contents = baseColorImage
            fallbackMaterial.ambient.contents = baseColorImage
        } else {
            fallbackMaterial.diffuse.contents = NSColor(calibratedRed: 0.055, green: 0.045, blue: 0.075, alpha: 1.0)
            fallbackMaterial.ambient.contents = NSColor(calibratedRed: 0.055, green: 0.045, blue: 0.075, alpha: 1.0)
        }

        if let normalImage {
            fallbackMaterial.normal.contents = normalImage
        }

        fallbackMaterial.specular.contents = NSColor(calibratedWhite: 0.25, alpha: 1.0)
        fallbackMaterial.shininess = 0.20
        fallbackMaterial.lightingModel = .blinn
        fallbackMaterial.isDoubleSided = true
        fallbackMaterial.diffuse.wrapS = .repeat
        fallbackMaterial.diffuse.wrapT = .repeat

        var geometryCount = 0

        func apply(to current: SCNNode) {
            if let geometry = current.geometry {
                geometry.materials = [fallbackMaterial]
                geometry.firstMaterial = fallbackMaterial
                geometryCount += 1
            }

            for child in current.childNodes {
                apply(to: child)
            }
        }

        apply(to: node)
        print("LucySceneView: applied original GLB basecolor texture to \(geometryCount) geometries")
        print("LucySceneView: texture path \(textureURL.path), exists \(FileManager.default.fileExists(atPath: textureURL.path))")
    }


    func normalize(node: SCNNode) {
        let bounds = node.boundingBox
        let minBounds = bounds.min
        let maxBounds = bounds.max

        let width = maxBounds.x - minBounds.x
        let height = maxBounds.y - minBounds.y
        let depth = maxBounds.z - minBounds.z
        let largest = Swift.max(width, Swift.max(height, depth))

        if largest > 0 {
            let scale = 5.0 / largest
            node.scale = SCNVector3(scale, scale, scale)
        }

        let centerX = (minBounds.x + maxBounds.x) / 2
        let centerY = (minBounds.y + maxBounds.y) / 2
        let centerZ = (minBounds.z + maxBounds.z) / 2

        node.position = SCNVector3(
            -centerX * node.scale.x,
            -centerY * node.scale.y,
            -centerZ * node.scale.z
        )
    }

    func startIdle() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            self.tickIdle()
        }
    }


    func setAliveMotionPaused(_ paused: Bool) {
        pauseAliveMotion = paused

        if paused {
            lookTargetX *= 0.65
            lookTargetY *= 0.65
            settleEnergy *= 0.5
            hopImpulse = 0
        }
    }



    func setPounceVisualPhase(_ phase: LucyPounceVisualPhase) {
        pounceVisualPhase = phase
    }


    func tickIdle() {
        let now = CACurrentMediaTime()

        if pauseAliveMotion {
            // Freeze most motion while the cursor is on Lucy so she is easy to click/drag.
            let baseYaw = CGFloat(-Double.pi / 2)

            modelNode.position.y = modelNode.position.y + (0 - modelNode.position.y) * 0.18
            modelNode.eulerAngles.y = modelNode.eulerAngles.y + (baseYaw - modelNode.eulerAngles.y) * 0.16
            modelNode.eulerAngles.x = modelNode.eulerAngles.x + (0 - modelNode.eulerAngles.x) * 0.16
            modelNode.eulerAngles.z = modelNode.eulerAngles.z + (0 - modelNode.eulerAngles.z) * 0.16
            modelNode.scale = baseModelScale

            return
        }

        // Occasionally choose a tiny curiosity/fidget target.
        if now > nextFidgetTime {
            nextFidgetTime = now + Double.random(in: 2.0...5.0)
            targetCuriosityOffsetX = CGFloat.random(in: -0.20...0.20)
            targetCuriosityOffsetY = CGFloat.random(in: -0.12...0.12)
        }

        curiosityOffsetX += (targetCuriosityOffsetX - curiosityOffsetX) * 0.028
        curiosityOffsetY += (targetCuriosityOffsetY - curiosityOffsetY) * 0.028

        let attention = min(1.0, abs(lookTargetX) + abs(lookTargetY))

        // Detect sudden attention changes for a little "noticed you!" settle.
        let attentionDelta = max(0, attention - lastAttention)
        if attentionDelta > 0.25 {
            settleEnergy = min(1.0, settleEnergy + attentionDelta * 0.55)
        }
        lastAttention = attention
        settleEnergy *= 0.94

        // Occasional micro-hop when idle or curious.
        if now > nextMicroHopTime {
            nextMicroHopTime = now + Double.random(in: 4.0...8.5)

            if attention < 0.45 {
                hopImpulse = CGFloat.random(in: 0.055...0.11)
            }
        }

        hopImpulse *= 0.88

        // Breathing + tiny life motion.
        let breath = CGFloat(sin(now * 2.0) * 0.050)
        let tinyTremble = CGFloat(sin(now * 8.0) * 0.006) * attention
        let curiousLift = attention * 0.045
        let settleBounce = CGFloat(sin(now * 8.5)) * settleEnergy * 0.035

        modelNode.position.y = breath + tinyTremble + curiousLift + hopImpulse + settleBounce

        // Base yaw controls Lucy's default facing direction.
        let baseYaw = CGFloat(-Double.pi / 2)

        // Softer non-linear look: visible but not snappy.
        let softenedLookX = tanh(lookTargetX * 1.10)
        let softenedLookY = tanh(lookTargetY * 1.00)

        let targetYaw = baseYaw + softenedLookX * 1.10 + curiosityOffsetX
        let targetPitch = -softenedLookY * 0.38 + curiosityOffsetY

        // Organic tilt: curiosity + tiny idle sway.
        let idleRoll = CGFloat(sin(now * 1.15) * 0.022)
        let targetRoll = -softenedLookX * 0.18 + idleRoll + settleEnergy * 0.045

        let yawEase = 0.10 + attention * 0.09
        let pitchEase = 0.08 + attention * 0.07
        let rollEase = 0.07 + attention * 0.07

        modelNode.eulerAngles.y = modelNode.eulerAngles.y + (targetYaw - modelNode.eulerAngles.y) * yawEase
        modelNode.eulerAngles.x = modelNode.eulerAngles.x + (targetPitch - modelNode.eulerAngles.x) * pitchEase
        modelNode.eulerAngles.z = modelNode.eulerAngles.z + (targetRoll - modelNode.eulerAngles.z) * rollEase

        // Breathing scale, preserving the normalized model scale.
        var scaleX = CGFloat(1.0 + sin(now * 2.0) * 0.010 + settleEnergy * 0.012)
        var scaleY = scaleX
        var scaleZ = scaleX

        switch pounceVisualPhase {
        case .normal:
            break
        case .crouch:
            scaleX *= 1.08
            scaleY *= 0.82
            scaleZ *= 1.08
            modelNode.position.y -= 0.05
        case .stretch:
            scaleX *= 0.90
            scaleY *= 1.18
            scaleZ *= 0.92
            modelNode.eulerAngles.x += 0.10
        case .land:
            scaleX *= 1.12
            scaleY *= 0.78
            scaleZ *= 1.10
            modelNode.position.y -= 0.06
        }

        modelNode.scale = SCNVector3(
            baseModelScale.x * scaleX,
            baseModelScale.y * scaleY,
            baseModelScale.z * scaleZ
        )
    }

    func lookToward(dx: CGFloat, dy: CGFloat) {
        let targetX = max(-1.0, min(1.0, dx / 88.0))
        let targetY = max(-1.0, min(1.0, dy / 115.0))

        // Smooth target itself so cursor tracking feels alive, not robotic.
        lookTargetX += (targetX - lookTargetX) * 0.22
        lookTargetY += (targetY - lookTargetY) * 0.20
    }


    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.deltaX, event.deltaY)
    }



    func modelBoundsInView() -> CGRect? {
        let bounds = modelNode.boundingBox
        let min = bounds.min
        let max = bounds.max

        let corners = [
            SCNVector3(min.x, min.y, min.z),
            SCNVector3(min.x, min.y, max.z),
            SCNVector3(min.x, max.y, min.z),
            SCNVector3(min.x, max.y, max.z),
            SCNVector3(max.x, min.y, min.z),
            SCNVector3(max.x, min.y, max.z),
            SCNVector3(max.x, max.y, min.z),
            SCNVector3(max.x, max.y, max.z)
        ]

        let projected = corners.map { corner -> CGPoint in
            let world = modelNode.convertPosition(corner, to: nil)
            let projectedPoint = projectPoint(world)
            return CGPoint(x: CGFloat(projectedPoint.x), y: CGFloat(projectedPoint.y))
        }

        guard let first = projected.first else {
            return nil
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in projected {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func modelBoundsInfoText() -> String {
        guard let bounds = modelBoundsInView() else {
            return "Model bounds unavailable."
        }

        let bottomEmpty = bounds.minY
        let topEmpty = self.bounds.height - bounds.maxY
        let leftEmpty = bounds.minX
        let rightEmpty = self.bounds.width - bounds.maxX

        return """
        View size: \(Int(self.bounds.width))x\(Int(self.bounds.height))
        Model bounds in view:
          x \(Int(bounds.minX)), y \(Int(bounds.minY)), w \(Int(bounds.width)), h \(Int(bounds.height))
        Empty space:
          bottom \(Int(bottomEmpty))
          top \(Int(topEmpty))
          left \(Int(leftEmpty))
          right \(Int(rightEmpty))
        """
    }


    func renderInfoText() -> String {
        let modelURL = LucyPaths.root
            .appendingPathComponent("assets")
            .appendingPathComponent("scenekit")
            .appendingPathComponent("lucy_spider_v1.obj")

        let bbox = modelNode.boundingBox

        return """
        Real 3D SceneKit mode
        Model path: \(modelURL.path)
        Model exists: \(FileManager.default.fileExists(atPath: modelURL.path))
        Model loaded: \(modelLoaded)
        Model child nodes: \(modelNode.childNodes.count)
        Model position: \(modelNode.position)
        Model scale: \(modelNode.scale)
        Bounding min: \(bbox.min)
        Bounding max: \(bbox.max)
        """
    }
}
