//
//  Extensions.swift
//  ARStack
//
//  Created by Sachin Agrawal on 7/10/23.
//

import SceneKit

// Extension of SCNNode to provide a method for center aligning its child nodes
extension SCNNode {
    func centerAlign() {
        // Calculate the bounding box of the node's geometry
        let (min, max) = boundingBox
        let extents = ((max) - (min))
        // Set the pivot of the node's transform to center align its child nodes
        simdPivot = float4x4(translation: SIMD3((extents / 2) + (min)))
    }
}

// Extension of float4x4 to provide an initializer for translation
extension float4x4 {
    init(translation vector: SIMD3<Float>) {
        self.init(SIMD4(1, 0, 0, 0),
                  SIMD4(0, 1, 0, 0),
                  SIMD4(0, 0, 1, 0),
                  SIMD4(vector.x, vector.y, vector.z, 1))
    }
}

// Overloaded operators for SCNVector3 to support arithmetic operations
func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x + right.x, left.y + right.y, left.z + right.z)
}
func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
}
func / (left: SCNVector3, right: Int) -> SCNVector3 {
    return SCNVector3Make(left.x / Float(right), left.y / Float(right), left.z / Float(right))
}

// Extension of Int to convert degrees to radians
extension Int {
    var degreesToRadians : Double {return Double(self) * .pi/180}
}

// Extension of SCNVector3 to see if it is equatable
extension SCNVector3: Equatable {
    public static func == (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
    
    // Define inequality based on equality
    public static func != (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return !(lhs == rhs)
    }
}

// Extension of SCNVector3 that returns the absolute value of each component
extension SCNVector3 {
  func absoluteValue() -> SCNVector3 {
    return SCNVector3Make(abs(self.x), abs(self.y), abs(self.z))
  }
}
