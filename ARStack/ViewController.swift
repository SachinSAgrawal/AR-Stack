//
//  ViewController.swift
//  ARStack
//
//  Created by Xander Xu on 2017/10/14.
//  Modified by Sachin Agrawal under Apache-2.0.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation

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
    var baseNode: SCNNode?          /// Represents the base of the game
    var gameNode: SCNNode?          /// Node for all game elements
    var baseNodeAdded = false       /// Has the base node been added
    
    // Game variables
    var direction = true            /// Direction of block movement
    var gameStarted = false         /// Boolean for if game has started
    var height = 0                  /// Height of the stacked blocks
    var perfectMatches = 0          /// Counter for perfect matches
    
    // Variables for block size and position calculation
    var previousPosition = SCNVector3(0, boxheight*0.5, 0)
    var currentSize = SCNVector3(boxLengthWidth, boxheight, boxLengthWidth)
    var currentPosition = SCNVector3Zero
    var offset = SCNVector3Zero
    var absoluteOffset = SCNVector3Zero
    var newSize = SCNVector3Zero
    
    // True while a tap is slicing a piece so the render loop pauses the block
    private var isPlacingPiece = false

    // True while tracking is degraded so plane content isn't rebuilt yet
    private var trackingDegraded = false

    // Gates whether the plane meshes may be shown
    private var planeMeshesUnlocked = false

    // Preloaded audio players, one per sound effect
    var soundPlayers = [String: AVAudioPlayer]()

    // Serial queue so the synchronous AVAudioSession calls never block the main thread
    private let audioSessionQueue = DispatchQueue(label: "com.arstack.audioSession")
    
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

        // Configure the audio session so effects are audible
        configureAudioSession()

        // Load sound files for game events
        loadSound(name: "GameOver", path: "art.scnassets/Audio/GameOver.wav")
        loadSound(name: "PerfectFit", path: "art.scnassets/Audio/PerfectFit.wav")
        loadSound(name: "SliceBlock", path: "art.scnassets/Audio/SliceBlock.wav")
        
        // Reset the game on foreground, but only once camera access is granted
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { (noti) in
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
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
        
        // Show a message instead of crashing since ARKit needs a physical device
        guard ARWorldTrackingConfiguration.isSupported else {
            playButton.isHidden = true
            sessionInfoLabel.isHidden = false
            sessionInfoLabel.text = "ARKit isn't available: run on a physical device."
            return
        }

        // Start the AR session only once camera access is granted
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            resetAll()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.resetAll()
                    } else {
                        self.playButton.isHidden = true
                        self.sessionInfoLabel.isHidden = false
                        self.sessionInfoLabel.text = "Camera access is required to play."
                    }
                }
            }
        default: /// .denied or .restricted
            playButton.isHidden = true
            sessionInfoLabel.isHidden = false
            sessionInfoLabel.text = "Camera access is required. Enable it in Settings."
        }
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

        // Re-lock the plane meshes for this run
        planeMeshesUnlocked = false

        // Warm up the Taptic Engine so the first stack doesn't stutter
        HapticManager.instance.prepare()

        // When the game starts, show normal tracking in the session label
        DispatchQueue.main.async {
            self.sessionInfoLabel.text = "Planes Detected: Game Active"
        }

        // Stop plane detection
        stopTracking()

        // Clear the base's color now that the game is starting
        baseNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        
        // Load game scene
        gameNode?.removeFromParentNode() /// Remove scene nodes from the previous game
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
                        if let raycastQuery = sceneView.raycastQuery(from: tapLocation, allowing: .existingPlaneGeometry, alignment: .any),
                           let result = sceneView.session.raycast(raycastQuery).first {
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

        // Handle the tap only while a game is running and tracking is stable
        if gameStarted, !trackingDegraded, let currentBoxNode = gameNode?.childNode(withName: "Block\(height)", recursively: false) {
            // Pause the block's movement while we read its position and commit the cut
            isPlacingPiece = true
            defer { isPlacingPiece = false }

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
                playSound(sound: "GameOver")
                if playButton.isHidden { HapticManager.instance.notification (type: .error) }
                updateHighestScore(score: height)
                gameOver()
                height += 1
                currentBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
                return
            } else if height % 2 != 0 && newSize.x <= 0 {
                playSound(sound: "GameOver")
                if playButton.isHidden { HapticManager.instance.notification (type: .error) }
                updateHighestScore(score: height)
                gameOver()
                height += 1
                currentBoxNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: currentBoxNode.geometry!, options: nil))
                return
            }
            
            // Check for perfect match
            checkPerfectMatch(currentBoxNode)
            
            // Swap in the recolored geometry without animation to avoid a white flash
            let slicedGeometry = SCNBox(width: CGFloat(newSize.x), height: boxheight, length: CGFloat(newSize.z), chamferRadius: 0)
            slicedGeometry.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat(height % 24) * 15.0 / 360, saturation: 0.7, brightness: 0.9, alpha: 1)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            currentBoxNode.geometry = slicedGeometry
            currentBoxNode.position = SCNVector3Make(currentPosition.x + (offset.x/2), currentPosition.y, currentPosition.z + (offset.z/2))
            currentBoxNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: slicedGeometry, options: nil))

            // Sync the new physics body to the node's transform to avoid a one-frame flicker
            currentBoxNode.physicsBody?.resetTransform()

            // Add the falling piece in the same transaction so it's shown on the same frame
            addBrokenBlock(currentBoxNode)
            SCNTransaction.commit()

            // Add the new block, play sound and haptic
            addNewBlock(currentBoxNode)
            playSound(sound: "SliceBlock")
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
            
            // Update previous position and increment height
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
            playSound(sound: "PerfectFit")
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
            playSound(sound: "PerfectFit")
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

    // Preload a sound file into its own AVAudioPlayer, ready for instant playback
    func loadSound(name: String, path: String) {
        // Resolve the bundle URL for a path like "art.scnassets/Audio/GameOver.wav"
        let nsPath = path as NSString
        let file = nsPath.lastPathComponent as NSString
        let resource = file.deletingPathExtension
        let ext = file.pathExtension
        let dir = nsPath.deletingLastPathComponent

        let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: dir)
            ?? Bundle.main.url(forResource: resource, withExtension: ext)
        guard let soundURL = url else {
            print("Could not find sound file for \(name) at \(path)")
            return
        }

        // Create and prime the player off the main thread to avoid a UI hitch
        audioSessionQueue.async {
            do {
                let player = try AVAudioPlayer(contentsOf: soundURL)
                player.volume = 0.5
                player.prepareToPlay()
                DispatchQueue.main.async {
                    self.soundPlayers[name] = player
                }
            } catch {
                print("Failed to load sound \(name): \(error)")
            }
        }
    }

    // Put the audio session in a playback category so effects are always heard
    func configureAudioSession() {
        audioSessionQueue.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Audio session setup failed: \(error)")
            }
        }
    }

    // Play a preloaded sound effect from the start
    func playSound(sound: String) {
        // Guard against a missing sound so a failed load can never crash playback
        guard let player = soundPlayers[sound] else { return }

        // Play off the main thread to avoid a UI hitch from activating the session
        audioSessionQueue.async {
            player.currentTime = 0
            player.play()
        }
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

        // Re-enable plane detection that stopTracking disabled at game start
        resumePlaneDetection()

        // Refresh the status UI now that the game is over
        refreshSessionUI()
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
        newBoxNode.geometry?.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat((height + 1) % 24) * 15.0 / 360, saturation: 0.7, brightness: 0.9, alpha: 1) /// Must + 1
        
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

        // Sync the physics body to the node's transform so it doesn't flicker on appear
        newBoxNode.physicsBody?.resetTransform()
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
            brokenBoxNode.physicsBody?.resetTransform()

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
            brokenBoxNode.physicsBody?.resetTransform()
        }
    }

    // MARK: Info Label
    
    // Recompute the AR-status UI from the current session
    private func refreshSessionUI() {
        guard let frame = sceneView.session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    // Single source of truth for the status label, coaching overlay, and play button
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Resolve the tracking message, and whether tracking is normal / degraded
        var message: String
        var isNormal = false
        var degraded = false

        switch trackingState {
        case .normal:
            isNormal = true
            message = "Tracking State is Normal"

        case .notAvailable:
            message = "AR Tracking Not Available"
            degraded = true

        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                message = "Excessive Motion: Move your phone slowly"
            case .insufficientFeatures:
                message = "Insufficient Features: Move or turn on lights"
            case .initializing:
                message = "Initializing AR Tracking"
            case .relocalizing:
                message = "Relocalizing AR Tracking"
            @unknown default:
                message = "Tracking State is Limited"
            }

            // Treat .initializing as normal startup, not a degradation
            degraded = (reason != .initializing)
        }

        // Unlock the plane meshes when tracking recovers after a game
        if !gameStarted, trackingDegraded, !degraded {
            planeMeshesUnlocked = true
        }

        // Remember whether tracking is degraded so plane content isn't rebuilt yet
        trackingDegraded = degraded

        // Reconcile mesh visibility now that both flags are current
        updatePlaneContentVisibility()

        // During a game only update the label and leave the base and coaching alone
        if gameStarted {
            switch trackingState {
            case .normal:
                sessionInfoLabel.text = "Planes Detected: Game Active"
            case .notAvailable:
                sessionInfoLabel.text = "AR Unavailable: Game Paused"
            case .limited(let reason):
                switch reason {
                case .excessiveMotion:
                    sessionInfoLabel.text = "Excessive Motion: Game Paused"
                case .insufficientFeatures:
                    sessionInfoLabel.text = "Insufficient Features: Game Paused"
                case .relocalizing:
                    sessionInfoLabel.text = "Relocalizing AR: Game Paused"
                case .initializing:
                    sessionInfoLabel.text = "Initializing AR: Game Paused"
                @unknown default:
                    sessionInfoLabel.text = "Limited Tracking: Game Paused"
                }
            }
            return
        }

        if degraded {
            // Tear down the stale visual content and guide the user
            removeARContent()
            coachingOverlay.setActive(true, animated: true)
            playButton.isHidden = true
        } else if baseNodeAdded {
            // Tracking is fine and the base is placed, ready to play
            message = "Planes Detected: Ready to Begin"
            coachingOverlay.setActive(false, animated: true)
            playButton.isHidden = false
        } else {
            // Tracking is fine but no base yet, so keep guiding the user
            if isNormal {
                message = "No Flat Surfaces Detected"
            }
            coachingOverlay.setActive(true, animated: true)
            playButton.isHidden = true
        }

        sessionInfoLabel.text = message
    }

    // Show the plane meshes only when idle, tracking is stable, and they're unlocked
    private func updatePlaneContentVisibility() {
        let shouldShow = !gameStarted && !trackingDegraded && planeMeshesUnlocked
        sceneView.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "MeshNode" {
                node.isHidden = !shouldShow
            }
        }
    }

    // Remove the plane meshes, labels, and base while tracking is degraded
    private func removeARContent() {
        // Collect first, then remove, so we don't mutate the tree mid-enumeration
        var nodesToRemove: [SCNNode] = []
        sceneView.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "MeshNode" || node.name == "TextNode" {
                nodesToRemove.append(node)
            }
        }
        nodesToRemove.forEach { $0.removeFromParentNode() }

        baseNode?.removeFromParentNode()
        baseNode = nil
        baseNodeAdded = false
    }

    // This function resets the AR tracking
    private func resetTracking() {
        // Create a new AR configuration with horizontal plane detection and light estimation enabled
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        
        // Run the AR session with options to reset tracking and remove existing anchors
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        // Re-assert the playback audio session in case ARKit changed it
        configureAudioSession()

        // Reset boolean toggles controling some game logic and hide the coaching overlay
        baseNodeAdded = false
        gameStarted = false

        // Fresh acquisition, so allow the plane meshes to show for onboarding
        planeMeshesUnlocked = true
        coachingOverlay.setActive(true, animated: true)
    }
    
    // MARK: Resetting
    
    // This function stops AR tracking
    private func stopTracking() {
        // Create a new AR configuration with plane detection turned off and light estimation enabled
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .init(rawValue: 0)
        configuration.isLightEstimationEnabled = true
        
        // Enable people occlusion only when the device supports it
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        // Run the AR session with the new configuration
        sceneView.session.run(configuration)

        // Re-assert the playback audio session in case ARKit changed it
        configureAudioSession()
    }

    // Re-enable plane detection without resetting tracking or removing anchors
    private func resumePlaneDetection() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration)

        // Re-assert the playback audio session in case ARKit changed it
        configureAudioSession()
    }
    
    // This function resets all game-related data and configurations
    private func resetAll() {
        // Hide the play button and show the session information label
        playButton.isHidden = true
        
        // Reset plane detection configuration and restart detection
        resetTracking()

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
        // Only handle plane anchors
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        // Build on the main thread when tracking is stable and no game is running
        DispatchQueue.main.async {
            guard node.childNodes.count < 1, !self.trackingDegraded, !self.gameStarted else { return }
            self.buildPlaneContent(on: node, for: planeAnchor)
        }
    }

    // Build the plane mesh, its label, and the game base for a plane anchor
    private func buildPlaneContent(on node: SCNNode, for planeAnchor: ARPlaneAnchor) {
        // Add the mesh and instruction label if this anchor doesn't have them yet
        if node.childNode(withName: "MeshNode", recursively: false) == nil,
           let device = sceneView.device,
           let meshGeometry = ARSCNPlaneGeometry(device: device) {
            meshGeometry.update(from: planeAnchor.geometry)
            let meshNode = SCNNode(geometry: meshGeometry)
            meshNode.opacity = 0.5
            meshNode.name = "MeshNode"
            meshNode.geometry?.firstMaterial?.diffuse.contents = UIColor.darkGray
            node.addChildNode(meshNode)

            let textGeometry = SCNText(string: "Tap Anywhere Within to \n  Move Game Location", extrusionDepth: 1)
            textGeometry.font = UIFont(name: "Futura", size: 75)
            let textNode = SCNNode(geometry: textGeometry)
            textNode.name = "TextNode"
            textNode.simdScale = SIMD3(repeating: 0.0005)
            textNode.eulerAngles = SCNVector3(x: Float(-90.degreesToRadians), y: 0, z: 0)
            node.addChildNode(textNode)
            textNode.centerAlign()

            print("Plane node added")
        }

        // Game base, if not already placed
        if !baseNodeAdded {
            let base = SCNBox(width: 0.4, height: 0, length: 0.4, chamferRadius: 0)
            base.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
            let newBase = SCNNode(geometry: base)
            newBase.position = SCNVector3Make(planeAnchor.center.x, 0.05, planeAnchor.center.z)

            let gameGeometry = SCNText(string: "Game", extrusionDepth: 1)
            gameGeometry.font = UIFont(name: "Futura", size: 75)
            let gameLabel = SCNNode(geometry: gameGeometry)
            gameLabel.name = "TextNode"
            gameLabel.simdScale = SIMD3(repeating: 0.0005)
            gameLabel.eulerAngles = SCNVector3(x: Float(-90.degreesToRadians), y: 0, z: 0)
            newBase.addChildNode(gameLabel)
            gameLabel.position = SCNVector3(-0.05, 0, 0.025)

            node.addChildNode(newBase)
            baseNode = newBase
            baseNodeAdded = true

            // Dismiss coaching, show the play button, and update the text
            coachingOverlay.setActive(false, animated: true)
            playButton.isHidden = false
            sessionInfoLabel.text = "Planes Detected: Ready to Begin"
        }

        // Reconcile the freshly built mesh so it stays hidden if still locked
        updatePlaneContentVisibility()
    }

    // MARK: Renderer

    // Called after updating the anchor point and corresponding node
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Check if the anchor is of type ARPlaneAnchor
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        if let meshNode = node.childNode(withName: "MeshNode", recursively: false),
           let planeGeometry = meshNode.geometry as? ARSCNPlaneGeometry {
            // Refresh the existing mesh's geometry from the anchor
            planeGeometry.update(from: planeAnchor.geometry)
        } else {
            // Mesh was torn down while degraded, so rebuild it once tracking is stable
            DispatchQueue.main.async {
                guard !self.trackingDegraded, !self.gameStarted,
                      node.childNode(withName: "MeshNode", recursively: false) == nil else { return }
                self.buildPlaneContent(on: node, for: planeAnchor)
            }
        }
    }
    
    // Called after removing the anchor point and corresponding node
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        // Only plane anchors host the base
        guard anchor is ARPlaneAnchor else { return }

        // Re-arm base placement if its plane is removed while no game is running
        if let base = baseNode, base.parent === node, !gameStarted {
            baseNode = nil
            baseNodeAdded = false

            DispatchQueue.main.async {
                self.refreshSessionUI()
            }
        }
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
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: camera.trackingState)
    }
    
    // MARK: Each Frame
    
    // Called to update the scene at each frame
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Check if the game node exists
        guard let gameNode2 = gameNode else {
            return
        }

        // Detect fallen nodes here but remove them on the main thread to avoid a race
        let fallenNodes = gameNode2.childNodes.filter { $0.presentation.position.y <= -10 }
        if !fallenNodes.isEmpty {
            DispatchQueue.main.async {
                fallenNodes.forEach { $0.removeFromParentNode() }
            }
        }

        // Move the current block unless a tap is placing a piece or tracking is degraded
        if !isPlacingPiece, !trackingDegraded, let currentNode = gameNode?.childNode(withName: "Block\(height)", recursively: false) {
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

    // Keep generators prepared so the Taptic Engine doesn't cold-start on first use
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // Warm up the Taptic Engine ahead of the first feedback event
    func prepare() {
        notificationGenerator.prepare()
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
    }

    // Method to trigger notification haptic feedback
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)

        // Keep the engine warm for the next event
        notificationGenerator.prepare()
    }

    // Method to trigger impact haptic feedback
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = lightImpactGenerator
        case .heavy: generator = heavyImpactGenerator
        case .medium: generator = mediumImpactGenerator
        default: generator = mediumImpactGenerator
        }
        generator.impactOccurred()

        // Keep the engine warm for the next event
        generator.prepare()
    }
}
