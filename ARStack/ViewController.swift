//
//  ViewController.swift
//  ARStack
//
//  Created by Sachin Agrawal on 7/10/23.
//

import UIKit
import SceneKit
import ARKit

// Set the initial dimensions for the game blocks
let boxheight: CGFloat = 0.05
let boxLengthWidth: CGFloat = 0.4

// Offset and speed for block movement animation
let actionOffet: Float = 0.6
let actionSpeed: Float = 0.011

class ViewController: UIViewController, ARCoachingOverlayViewDelegate {
    // UI Outlets
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var scoreLabel: UILabel!
    @IBOutlet weak var highScore: UILabel!
    @IBOutlet weak var debugToggle: UIButton!
    
    // Nodes for managing the AR scene
    weak var baseNode: SCNNode?     /// Represents the base of the game
    weak var planeNode: SCNNode?    /// Represents the detected plane
    var gameNode: SCNNode?          /// Node for all game elements
    var baseNodeAdded = false       /// Has the base node been added
    
    // Game variables
    var updateCount: NSInteger = 0  /// Counter for plane detection updates
    var direction = true            /// Direction of block movement
    var gameStarted = false         /// Boolean for if game has started
    var height = 0                  /// Height of the stacked blocks
    var perfectMatches = 0          /// Counter for perfect matches
    
    // Variables for block size and position calculation
    var previousSize = SCNVector3(boxLengthWidth, boxheight, boxLengthWidth)
    var previousPosition = SCNVector3(0, boxheight*0.5, 0)
    var currentSize = SCNVector3(boxLengthWidth, boxheight, boxLengthWidth)
    var currentPosition = SCNVector3Zero
    var offset = SCNVector3Zero
    var absoluteOffset = SCNVector3Zero
    var newSize = SCNVector3Zero
    
    // Dictionary to store sounds
    var sounds = [String: SCNAudioSource]()
    
    // AR coaching overlay view
    var coachingOverlay: ARCoachingOverlayView!
    
    // Unique key for storing the highest score in user defaults
    var highestScoreKey: String = "StackHighestScore"

    // MARK: View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do not automatically add light to the scene
        sceneView.autoenablesDefaultLighting = false
        
        // Hide the play button and session label to start
        playButton.isHidden = true
        sessionInfoLabel.isHidden = true
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Load sound files for game events
        loadSound(name: "GameOver", path: "art.scnassets/Audio/GameOver.wav")
        loadSound(name: "PerfectFit", path: "art.scnassets/Audio/PerfectFit.wav")
        loadSound(name: "SliceBlock", path: "art.scnassets/Audio/SliceBlock.wav")
        
        // Add observer for application entering foreground to reset the game
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { (noti) in
            self.resetAll()
        }
        
        // Set up the AR coaching overlay
        setupCoachingOverlay()
        
        // Update the highest score text
        updateHighestScoreText()
    }
    
    // Function to set up AR coaching overlay view
    func setupCoachingOverlay() {
        coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = sceneView.session
        coachingOverlay.delegate = self
        
        // Activate the AR coaching overlay view
        coachingOverlay.activatesAutomatically = false
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.setActive(true, animated: true)
        
        // Add the AR coaching overlay view to the scene view
        sceneView.addSubview(coachingOverlay)
        
        // Set the coaching overlay to cover the entire screen
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coachingOverlay.topAnchor.constraint(equalTo: sceneView.topAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: sceneView.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: sceneView.trailingAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: sceneView.bottomAnchor)
        ])
    }
    
    // MARK: View Visibility
    
    // Execute actions when the view is about to appear
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("View will appear")
        
        // Check if ARKit is supported on the device
        guard ARWorldTrackingConfiguration.isSupported else {
            fatalError("ARKit is not available on this device.") /// https://developer.apple.com/documentation/arkit
        }
        
        // Reset interface, parameters, and tracking configuration
        resetAll()
    }
    
    // Execute actions when the view is about to disappear
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    // Handle memory warnings
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use
    }
    
    // MARK: Play Button
    
    // Action triggered when the play button is clicked
    @IBAction func playButtonClick(_ sender: UIButton) {
        // Iterate over all child nodes of the root node of the scene view
        sceneView.scene.rootNode.enumerateChildNodes { (node, _) in
            // Check if the node's name is either "MeshNode" or "TextNode"
            if node.name == "MeshNode" || node.name == "TextNode"  {
                // If the node's name matches either of these, hide the node from view
                node.isHidden = true
            }
        }
        
        // Hide the play button and start the game
        playButton.isHidden = true
        gameStarted = true
        
        // Stop plane detection
        stopTracking()
        
        // Change transparency and color of the plane
        planeNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        planeNode?.opacity = 1
        baseNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        
        // Load game scene
        gameNode?.removeFromParentNode() // Remove scene nodes from the previous game
        gameNode = SCNNode()
        let gameChildNodes = SCNScene(named: "art.scnassets/Scenes/GameScene.scn")!.rootNode.childNodes
        for node in gameChildNodes {
            gameNode?.addChildNode(node)
        }
        baseNode?.addChildNode(gameNode!)
        resetGameData()
        
        // Create and add the first block to the game scene
        let boxNode = SCNNode(geometry: SCNBox(width: boxLengthWidth, height: boxheight, length: boxLengthWidth, chamferRadius: 0))
        boxNode.position.z = -actionOffet
        boxNode.position.y = Float(boxheight * 0.5 + boxheight)
        boxNode.name = "Block\(height)"
        boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat(height % 24) * 15.0 / 360, saturation: 0.7, brightness: 0.9, alpha: 1)
        boxNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: boxNode.geometry!, options: nil))
        gameNode?.addChildNode(boxNode)
    }
    
    // Action triggered when the reset button is clicked
    @IBAction func resetButtonClick(_ sender: UIButton) {
        resetAll()
    }
    
    // Action triggered when the debug toggle is clicked
    @IBAction func debugToggleClick(_ sender: UIButton) {
        if !sceneView.showsStatistics {
            // Show statistics such as FPS and timing information along with some debug options
            sceneView.showsStatistics = true
            sceneView.debugOptions = [SCNDebugOptions.showWorldOrigin, SCNDebugOptions.showFeaturePoints]
            sessionInfoLabel.isHidden = false
        } else {
            // Remove all the debug options
            sceneView.showsStatistics = false
            sceneView.debugOptions = []
            sessionInfoLabel.isHidden = true
        }
    }
    
    // MARK: Screen Tap
    
    // Action triggered when a tap gesture is recognized
    @IBAction func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        // Check if the play button is visible before processing the tap
        if !playButton.isHidden {
            // Iterate over all child nodes of the root node of the scene view
            sceneView.scene.rootNode.enumerateChildNodes { (node, _) in
                // Check if the "MeshNode" is hidden
                if node.name == "MeshNode" {
                    if !node.isHidden {
                        // Get the location of the tap on screen
                        let tapLocation = gestureRecognizer.location(in: sceneView)
                        
                        // Set position to origin to check raycast
                        var position = SCNVector3(0, 0, 0)
                        
                        // Perform a hit test to get the location of the tap on a horizontal plane
                        let raycastQuery = sceneView.raycastQuery(from: tapLocation, allowing: .existingPlaneGeometry, alignment: .any)
                        if let result = sceneView.session.raycast(raycastQuery!).first {
                            let translation = result.worldTransform.columns.3
                            position = SCNVector3(translation.x, translation.y + 0.05, translation.z)
                        }

                        // Check if a valid position was found
                        if position != SCNVector3(0, 0, 0) {
                            // Move the baseNode to the tapped position
                            baseNode?.worldPosition = position
                            print(position)
                        } else {
                            print("Tap location not valid")
                        }
                    }
                }
            }
        }
        
        // Otherwise it will check if the current block exists
        if let currentBoxNode = gameNode?.childNode(withName: "Block\(height)", recursively: false) {
            // Update current position, size, offset, and absolute offset
            currentPosition = currentBoxNode.presentation.position
            let boundsMin = currentBoxNode.boundingBox.min
            let boundsMax = currentBoxNode.boundingBox.max
            currentSize = boundsMax - boundsMin
            offset = previousPosition - currentPosition
            absoluteOffset = offset.absoluteValue()
            newSize = currentSize - absoluteOffset
            
            // Check for game over condition then play sound/haptic as well as update high score if so
            if height % 2 == 0 && newSize.z <= 0 {
                playSound(sound: "GameOver", node: currentBoxNode)
                if playButton.isHidden { HapticManager.instance.notification (type: .error) }
                updateHighestScore(score: height)
                gameOver()
                height += 1
                currentBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
                return
            } else if height % 2 != 0 && newSize.x <= 0 {
                playSound(sound: "GameOver", node: currentBoxNode)
                if playButton.isHidden { HapticManager.instance.notification (type: .error) }
                updateHighestScore(score: height)
                gameOver()
                height += 1
                currentBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
                return
            }
            
            // Check for perfect match
            checkPerfectMatch(currentBoxNode)
            
            // Update current block's geometry, position, physics body, and color
            currentBoxNode.geometry = SCNBox(width: CGFloat(newSize.x), height: boxheight, length: CGFloat(newSize.z), chamferRadius: 0)
            currentBoxNode.position = SCNVector3Make(currentPosition.x + (offset.x/2), currentPosition.y, currentPosition.z + (offset.z/2))
            currentBoxNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
            currentBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat(height % 24) * 15.0 / 360, saturation: 0.7, brightness: 0.9, alpha: 1)
            
            // Add broken and new blocks, play sound and haptic
            addBrokenBlock(currentBoxNode)
            addNewBlock(currentBoxNode)
            playSound(sound: "SliceBlock", node: currentBoxNode)
            if playButton.isHidden { HapticManager.instance.impact (style: .medium) }
            
            // Drop down the stack if its height is greater than or equal to 10
            if height >= 10 {
                gameNode?.enumerateChildNodes({ (node, stop) in
                    // Exclude light nodes from hiding
                    if node.light != nil {
                        return
                    }
                    // Hide nodes below the specified height
                    if node.position.y < Float(self.height-9) * Float(boxheight) {
                        node.isHidden = true
                    }
                })
                
                // Move the game node upwards to compensate for hidden nodes
                let moveUpAction = SCNAction.move(by: SCNVector3Make(0.0, Float(-boxheight), 0.0), duration: 0.2)
                gameNode?.runAction(moveUpAction)
            }
            
            // Update the score
            scoreLabel.text = "\(height+1)"
            
            // Update previous size and position as well as increment height
            previousSize = SCNVector3Make(newSize.x, Float(boxheight), newSize.z)
            previousPosition = currentBoxNode.position
            height += 1
        }
    }
    
    // Function to update the highest score in user defaults
    func updateHighestScore(score: Int) {
        let defaults = UserDefaults.standard
        // Read the current highest score
        let highestScore = defaults.integer(forKey: self.highestScoreKey)
        // Update the stored value and text if the current one is higher
        if highestScore < score {
            defaults.set(score, forKey: self.highestScoreKey)
            highScore.text = "High: \(score)"
        }
    }
    
    // Function to update the highest score text
    func updateHighestScoreText() {
        // Read the most recent high score and set the high score text to be that
        let defaults = UserDefaults.standard;
        let highestScore = defaults.integer(forKey: self.highestScoreKey);
        highScore.text = "High: \(highestScore)"
    }
}

// MARK: Extensions
extension ViewController {
    // Function to check if the current block perfectly matches the previous one
    func checkPerfectMatch(_ currentBoxNode: SCNNode) {
        // Check if the height of the stack is even and the absolute offset in the z direction is within a small threshold
        if height % 2 == 0 && absoluteOffset.z <= 0.005 {
            // Play a sound and haptic indicating a perfect fit
            playSound(sound: "PerfectFit", node: currentBoxNode)
            if playButton.isHidden { HapticManager.instance.notification (type: .success) }
            
            // Set the position of the current block to the previous position in the z direction
            currentBoxNode.position.z = previousPosition.z
            currentPosition.z = previousPosition.z
            
            // Increment the count of perfect matches
            perfectMatches += 1
            
            // If there are 7 or more perfect matches and the current block size is less than 1, increase its size slightly
            if perfectMatches >= 7 && currentSize.z < 1 {
                newSize.z += 0.005
            }
            
            // Calculate the offset and absolute offset between the current and previous positions
            offset = previousPosition - currentPosition
            absoluteOffset = offset.absoluteValue()
            
            // Calculate the new size of the block after considering the offset
            newSize = currentSize - absoluteOffset
        } else if height % 2 != 0 && absoluteOffset.x <= 0.005 {
            // Play a sound and haptic indicating a perfect fit
            playSound(sound: "PerfectFit", node: currentBoxNode)
            if playButton.isHidden { HapticManager.instance.notification (type: .success) }
            
            // Set the position of the current block to the previous position in the x direction
            currentBoxNode.position.x = previousPosition.x
            currentPosition.x = previousPosition.x
            
            // Increment the count of perfect matches
            perfectMatches += 1
            
            // If there are 7 or more perfect matches and the current block size is less than 1, increase its size slightly
            if perfectMatches >= 7 && currentSize.x < 1 {
                newSize.x += 0.005
            }
            
            // Calculate the offset and absolute offset between the current and previous positions
            offset = previousPosition - currentPosition
            absoluteOffset = offset.absoluteValue()
            
            // Calculate the new size of the block after considering the offset
            newSize = currentSize - absoluteOffset
        } else {
            // Reset perfectMatches if there is no perfect match
            perfectMatches = 0
        }
    }

    // Function to load a sound file into the scene
    func loadSound(name: String, path: String) {
        if let sound = SCNAudioSource(fileNamed: path) {
            sound.isPositional = false
            sound.volume = 1
            sound.load()
            sounds[name] = sound
        }
    }
    
    // Function to play a sound associated with a node
    func playSound(sound: String, node: SCNNode) {
        node.runAction(SCNAction.playAudio(sounds[sound]!, waitForCompletion: false))
    }
    
    // Function to execute actions when the game is over
    func gameOver() {
        // Update the highest score text
        updateHighestScoreText()
        
        // Define an action to move the game node to its initial position
        let fullAction = SCNAction.customAction(duration: 0.3) { _,_ in
            let moveAction = SCNAction.move(to: SCNVector3Make(0, 0, 0), duration: 0.3)
            self.gameNode?.runAction(moveAction)
        }
        
        // Run the full action, make the play button visible, and unhide all child nodes of the game node
        gameNode?.runAction(fullAction)
        playButton.isHidden = false
        gameStarted = false
        gameNode?.enumerateChildNodes({ (node, stop) in
            node.isHidden = false
        })
    }
    
    // MARK: New Blocks
    
    // Function to add a new block to the scene
    func addNewBlock(_ currentBoxNode: SCNNode) {
        // Create a new block node with dimensions based on the current size
        let newBoxNode = SCNNode(geometry: SCNBox(width: CGFloat(newSize.x), height: boxheight, length: CGFloat(newSize.z), chamferRadius: 0))
        
        // Set the position of the new block node
        newBoxNode.position = SCNVector3Make(currentBoxNode.position.x, currentPosition.y + Float(boxheight), currentBoxNode.position.z)
        
        // Assign a name to the new block node
        newBoxNode.name = "Block\(height+1)"
        
        // Apply color to the new block node
        newBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat(height + 1 % 24) * 15.0 / 360, saturation: 0.7, brightness: 0.9, alpha: 1) /// Must + 1
        
        // Add physics body to the new block node
        newBoxNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: newBoxNode.geometry!, options: nil))
        
        // Adjust position based on block stacking direction
        if height % 2 == 0 {
            newBoxNode.position.x = -actionOffet
        } else {
            newBoxNode.position.z = -actionOffet
        }
        
        // Add the new block node to the game node
        gameNode?.addChildNode(newBoxNode)
    }
    
    // Function to add a broken block to the scene
    func addBrokenBlock(_ currentBoxNode: SCNNode) {
        // Create a new node for the broken block
        let brokenBoxNode = SCNNode()
        brokenBoxNode.name = "Broken \(height)"
        
        // Check if the height is even and the absolute offset in the z direction is greater than 0
        if height % 2 == 0 && absoluteOffset.z > 0 {
            // Set geometry and position for the broken block in the z direction
            brokenBoxNode.geometry = SCNBox(width: CGFloat(currentSize.x), height: boxheight, length: CGFloat(absoluteOffset.z), chamferRadius: 0)
            
            if offset.z > 0 {
                brokenBoxNode.position.z = currentBoxNode.position.z - (offset.z/2) - ((currentSize - offset).z/2)
            } else {
                brokenBoxNode.position.z = currentBoxNode.position.z - (offset.z/2) + ((currentSize + offset).z/2)
            }
            brokenBoxNode.position.x = currentBoxNode.position.x
            brokenBoxNode.position.y = currentPosition.y
            
            // Add physics body and color to the broken block
            brokenBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: brokenBoxNode.geometry!, options: nil))
            brokenBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat(height % 24) * 15.0 / 360, saturation: 0.7, brightness: 0.9, alpha: 1)
            gameNode?.addChildNode(brokenBoxNode)
            
        } else if height % 2 != 0 && absoluteOffset.x > 0 {
            // Set geometry and position for the broken block in the x direction
            brokenBoxNode.geometry = SCNBox(width: CGFloat(absoluteOffset.x), height: boxheight, length: CGFloat(currentSize.z), chamferRadius: 0)
            
            if offset.x > 0 {
                brokenBoxNode.position.x = currentBoxNode.position.x - (offset.x/2) - ((currentSize - offset).x/2)
            } else {
                brokenBoxNode.position.x = currentBoxNode.position.x - (offset.x/2) + ((currentSize + offset).x/2)
            }
            brokenBoxNode.position.y = currentPosition.y
            brokenBoxNode.position.z = currentBoxNode.position.z
            
            // Add physics body and color to the broken block
            brokenBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: brokenBoxNode.geometry!, options: nil))
            brokenBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat(height % 24) * 15.0 / 360, saturation: 0.7, brightness: 0.9, alpha: 1)
            gameNode?.addChildNode(brokenBoxNode)
        }
    }
 
    // MARK: Info Label
    
    // Update UI to provide feedback on the AR status
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Create a string holding the message
        let message: String
        
        switch trackingState {
        case .normal where !baseNodeAdded:
            // No flat surfaces detected because the base node has yet to be placed
            message = "No Flat Surfaces Detected"
            
        case .normal:
            // Normal and flat surfaces are visible so no need for feedback
            message = "Tracking State is Normal"
            
        case .notAvailable:
            // Not available
            message = "AR Tracking Not Available"
            
        case .limited(.excessiveMotion):
            // Excessive motion
            message = "Excessive Motion: Move your phone slowly"
            
        case .limited(.insufficientFeatures):
            // Insufficient features
            message = "Insufficient Features: Move or turn on lights"
            
        case .limited(.initializing):
            // Initializing
            message = "Initializing AR Tracking"
            
        case .limited(.relocalizing):
            // Relocalizing
            message = "Relocalizing AR Tracking"
            
        case .limited(_):
            // Limited
            message = "Tracking State is Limited"
        }
        
        // Check if coaching overlay and play button should be hidden
        if trackingState == ARCamera.TrackingState.limited(.excessiveMotion) || trackingState == ARCamera.TrackingState.limited(.insufficientFeatures) {
            if !playButton.isHidden {
                coachingOverlay.setActive(true, animated: true)
                playButton.isHidden = true
            }
        } else {
            coachingOverlay.setActive(!baseNodeAdded, animated: true)
            if baseNodeAdded && !gameStarted {
                playButton.isHidden = false
            }
        }
        
        // Set the message to the session information label
        sessionInfoLabel.text = message
    }

    // This function resets the AR tracking
    private func resetTracking() {
        // Create a new AR configuration with horizontal plane detection and light estimation enabled
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        
        // Run the AR session with options to reset tracking and remove existing anchors
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // Reset boolean toggles controling some game logic and hide the coaching overlay
        baseNodeAdded = false
        gameStarted = false
        coachingOverlay.setActive(true, animated: true)
    }
    
    // MARK: Resetting
    
    // This function stops AR tracking
    private func stopTracking() {
        // Create a new AR configuration with plane detection turned off and light estimation enabled
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .init(rawValue: 0)
        configuration.isLightEstimationEnabled = true
        
        // Check for people occlusion support in the configuration
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) else {
            fatalError("People occlusion is not supported on this device.")
        }
        
        // Enable people occlusion in the AR configuration
        configuration.frameSemantics.insert(.personSegmentationWithDepth)
        
        // Run the AR session with the new configuration
        sceneView.session.run(configuration)
    }
    
    // This function resets all game-related data and configurations
    private func resetAll() {
        // Hide the play button and show the session information label
        playButton.isHidden = true
        
        // Reset plane detection configuration and restart detection
        resetTracking()
        
        // Reset the update count
//        updateCount = 0
        
        // Reset game data
        resetGameData()
        print("Reset all")
    }
    
    // This function resets all game-related data
    private func resetGameData() {
        // Reset height and update the score label
        height = 0
        scoreLabel.text = "\(height)"
        
        // Reset game direction, perfect matches, previous and current sizes and positions, and offsets
        direction = true
        perfectMatches = 0
        previousSize = SCNVector3(boxLengthWidth, boxheight, boxLengthWidth)
        previousPosition = SCNVector3(0, boxheight*0.5, 0)
        currentSize = SCNVector3(boxLengthWidth, boxheight, boxLengthWidth)
        currentPosition = SCNVector3Zero
        offset = SCNVector3Zero
        absoluteOffset = SCNVector3Zero
        newSize = SCNVector3Zero
    }
}

// MARK: View Delegate
extension ViewController: ARSCNViewDelegate {
    // Called after a node is added to the scene for an anchor
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Declare variables to hold the mesh node and text node
        let meshNode: SCNNode
        let textNode: SCNNode
        
        // Checks if the anchor is an ARPlaneAnchor and if the node has no child nodes yet
        if let planeAnchor = anchor as? ARPlaneAnchor, node.childNodes.count < 1 { // , updateCount < 1 {
            /*
            print("Snapped to flat ground")
            
            // Create a rectangle-sized plane from the detected flat ground which is an irregular-sized rectangle
            let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
            
            // Use the material property to render the 3D model (default color is white, but changed to green)
            plane.firstMaterial?.diffuse.contents = UIColor.green
            
            // Create a node based on the 3D object model
            planeNode = SCNNode(geometry: plane)
            
            // Set the position of the node to the center position of the anchor point of the detected flat ground
            // The position of the node in the SceneKit framework is a vector coordinate based on the 3D coordinate system SCNVector3
            planeNode?.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
            
            // `SCNPlane` is vertical by default, so rotate it to match the horizontal `ARPlaneAnchor`
            planeNode?.eulerAngles.x = -.pi / 2
            
            // Set transparency
            planeNode?.opacity = 0
            
            // Add to parent node
            node.addChildNode(planeNode!)
            */
            
            // Create an ARSCNPlaneGeometry using the device associated with the sceneView
            guard let meshGeometry = ARSCNPlaneGeometry(device: sceneView.device!) else {
                fatalError("Cannot create the plane geometry.")
            }
            
            // Update the mesh geometry from the plane anchor's geometry
            meshGeometry.update(from: planeAnchor.geometry)
            
            // Create a mesh node using the mesh geometry
            meshNode = SCNNode(geometry: meshGeometry)
            meshNode.opacity = 0.5
            meshNode.name = "MeshNode"
            
            // Set the diffuse contents of the material to light gray
            guard let material = meshNode.geometry?.firstMaterial else {
                fatalError("ARSCNPlaneGeometry always has one material.")
            }
            material.diffuse.contents = UIColor.darkGray
            
            // Add the mesh node as a child of the provided node
            node.addChildNode(meshNode)
            
            // Create a text geometry with the string "Plane" and extrusion depth of 1
            let textGeometry = SCNText(string: "Tap Anywhere Within to \n  Move Game Location", extrusionDepth: 1)
            textGeometry.font = UIFont(name: "Futura", size: 75)
            
            // Create a text node using the text geometry
            textNode = SCNNode(geometry: textGeometry)
            textNode.name = "TextNode"
            
            // Scale and rotate the text node
            textNode.simdScale = SIMD3(repeating: 0.0005)
            textNode.eulerAngles = SCNVector3(x: Float(-90.degreesToRadians), y: 0, z: 0)
            
            // Add the text node as a child of the provided node
            node.addChildNode(textNode)
            
            // Center align the text node
            textNode.centerAlign()
            
            // Print a message indicating that a plane node has been added
            print("Plane node added")
            
            if !baseNodeAdded {
                // Create and position the base of the game to be at the center of the anchor
                let base = SCNBox(width: 0.4, height: 0, length: 0.4, chamferRadius: 0)
                base.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
                baseNode = SCNNode(geometry: base)
                baseNode?.position = SCNVector3Make(planeAnchor.center.x, 0.05, planeAnchor.center.z)
                 
                let gameLabel: SCNNode
                
                // Create a text geometry with the string "Game" and extrusion depth of 1
                let gameGeometry = SCNText(string: "Game", extrusionDepth: 1)
                gameGeometry.font = UIFont(name: "Futura", size: 75)
                
                // Create a text node using the text geometry
                gameLabel = SCNNode(geometry: gameGeometry)
                gameLabel.name = "TextNode"
                
                // Scale and rotate the text node
                gameLabel.simdScale = SIMD3(repeating: 0.0005)
                gameLabel.eulerAngles = SCNVector3(x: Float(-90.degreesToRadians), y: 0, z: 0)
                
                // Add the text node as a child of the provided node
                baseNode?.addChildNode(gameLabel)
                
                // Adjust the position of the text node to center it
                gameLabel.position = SCNVector3(-0.05, 0, 0.025)
                
                // Add the base node to the plane node and set the boolean value
                node.addChildNode(baseNode!)
                baseNodeAdded = true
                
                // Deactivate the coaching overlay with animation
                coachingOverlay.setActive(false, animated: true)
                
                DispatchQueue.main.async {
                    // Then display the enter game button
                    self.playButton.isHidden = false
                }
            }
        }
    }
    
    // MARK: Renderer
    
    // Called before updating the anchor point and corresponding node, ARKit will automatically update the anchor and node to match
    func renderer(_ renderer: SCNSceneRenderer, willUpdate node: SCNNode, for anchor: ARAnchor) {
        /*
        // Only update the paired anchors and nodes obtained in `renderer(_:didAdd:for:)`
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            let planeNode = node.childNodes.first,
            let plane = planeNode.geometry as? SCNPlane
            else { return }
        
        updateCount += 1
        if updateCount > 20 {
            // If the plane has been updated more than 20 times and enough feature points have been captured
            DispatchQueue.main.async {
                // Then display the enter game button
                self.playButton.isHidden = false
            }
        }
        
        // The center point of the plane can change
        planeNode.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
        
        /*
        The plane size may increase, or several small planes may merge into one large plane.
        When merging, `ARSCNView` automatically deletes the corresponding node on the same plane.
        And then it will call this method to update the size of the other retained plane.
        After testing, when merging, the first detected plane and corresponding node are retained.
        */
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.height = CGFloat(planeAnchor.extent.z)
        */
    }
    
    // Called after updating the anchor point and corresponding node
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Check if the anchor is of type ARPlaneAnchor
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // If the node has a child node with the name "MeshNode" and its geometry can be cast to ARSCNPlaneGeometry
        if let planeGeometry = node.childNode(withName: "MeshNode", recursively: false)!.geometry as? ARSCNPlaneGeometry {
            // Update its geometry from the plane anchor's geometry
            planeGeometry.update(from: planeAnchor.geometry)
        }
    }
    
    // Called after removing the anchor point and corresponding node
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        // Not implemented
    }
    
    // Called when the ARSession encounters an error
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Update the session information label to indicate the failure
        sessionInfoLabel.text = "Session Failed: \(error.localizedDescription)"
        resetTracking()
    }
    
    // Called when the ARSession is interrupted
    func sessionWasInterrupted(_ session: ARSession) {
        // Update the session information label to indicate interruption
        sessionInfoLabel.text = "Session Was Interrupted"
    }
    
    // Called when the interruption of the ARSession ends
    func sessionInterruptionEnded(_ session: ARSession) {
        // Update the session information label to indicate the end of interruption
        sessionInfoLabel.text = "Session Interruption Ended"
        resetTracking()
    }
    
    // Called when the ARSession's camera tracking state changes
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // Update session information label based on camera tracking state
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }
    
    // MARK: Each Frame
    
    // Called to update the scene at each frame
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Check if the game node exists
        guard let gameNode2 = gameNode else {
            return
        }
        
        // Remove nodes that have fallen below a certain height threshold
        for node in gameNode2.childNodes {
            if node.presentation.position.y <= -10 {
                node.removeFromParentNode()
            }
        }
        
        // Check if the current node representing the block exists
        if let currentNode = gameNode?.childNode(withName: "Block\(height)", recursively: false) {
            // Determine the movement direction based on the height
            if height % 2 == 0 {
                // Update position based on Z-axis for even heights
                if currentNode.position.z >= actionOffet {
                    direction = false
                } else if currentNode.position.z <= -actionOffet {
                    direction = true
                }
                
                // Move the node along the Z-axis according to the determined direction and action speed
                switch direction {
                case true:
                    currentNode.position.z += actionSpeed
                case false:
                    currentNode.position.z -= actionSpeed
                }
            } else {
                // Update position based on X-axis for odd heights
                if currentNode.position.x >= actionOffet {
                    direction = false
                } else if currentNode.position.x <= -actionOffet {
                    direction = true
                }
                
                // Move the node along the X-axis according to the determined direction and action speed
                switch direction {
                case true:
                    currentNode.position.x += actionSpeed
                case false:
                    currentNode.position.x -= actionSpeed
                }
            }
        }
    }
}

// MARK: Haptics

// This class manages haptic feedback for the application
class HapticManager {
    // Singleton instance of the HapticManager
    static let instance = HapticManager()
    
    // Method to trigger notification haptic feedback
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator ()
        generator.notificationOccurred(type)
    }
    
    // Method to trigger impact haptic feedback
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
