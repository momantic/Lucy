import Cocoa
import SceneKit

class LucySceneView: SCNView {
    var containerNode = SCNNode()
    var modelNode = SCNNode()
    var idleTimer: Timer?
    var lookTargetX: CGFloat = 0
    var lookTargetY: CGFloat = 0
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
            applyFallbackMaterials(to: modelContainer)

            // Rotate to a more likely visible orientation for converted Blender assets.
            modelContainer.eulerAngles.x = CGFloat(-Double.pi / 2)

            modelLoaded = true
            modelNode = modelContainer
            containerNode.addChildNode(modelNode)
        } catch {
            addFallbackCube(reason: "failed to load model: \(error.localizedDescription)")
        }
    }


    func applyFallbackMaterials(to node: SCNNode) {
        let bodyMaterial = SCNMaterial()
        bodyMaterial.name = "LucyDarkBody"
        bodyMaterial.diffuse.contents = NSColor(calibratedRed: 0.055, green: 0.045, blue: 0.075, alpha: 1.0)
        bodyMaterial.ambient.contents = NSColor(calibratedRed: 0.055, green: 0.045, blue: 0.075, alpha: 1.0)
        bodyMaterial.specular.contents = NSColor(calibratedWhite: 0.25, alpha: 1.0)
        bodyMaterial.emission.contents = NSColor(calibratedRed: 0.018, green: 0.015, blue: 0.025, alpha: 1.0)
        bodyMaterial.shininess = 0.18
        bodyMaterial.lightingModel = .blinn
        bodyMaterial.isDoubleSided = true

        var geometryCount = 0

        func apply(to current: SCNNode) {
            if let geometry = current.geometry {
                geometry.materials = [bodyMaterial]
                geometry.firstMaterial = bodyMaterial
                geometryCount += 1
            }

            for child in current.childNodes {
                apply(to: child)
            }
        }

        apply(to: node)
        print("LucySceneView: applied fallback material to \(geometryCount) geometries")
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

    func tickIdle() {
        let now = CACurrentMediaTime()

        let bob = CGFloat(sin(now * 2.0) * 0.06)
        modelNode.position.y = bob

        let targetYaw = lookTargetX * 0.65
        let targetPitch = -lookTargetY * 0.20

        modelNode.eulerAngles.y = modelNode.eulerAngles.y + (targetYaw - modelNode.eulerAngles.y) * 0.12
        modelNode.eulerAngles.x = modelNode.eulerAngles.x + (targetPitch - modelNode.eulerAngles.x) * 0.08
    }

    func lookToward(dx: CGFloat, dy: CGFloat) {
        lookTargetX = max(-1.0, min(1.0, dx / 180.0))
        lookTargetY = max(-1.0, min(1.0, dy / 180.0))
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
