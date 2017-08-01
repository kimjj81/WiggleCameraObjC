//
//  WMCamera.swift
//  WiggleMeSwift
//
//  Created by KimJeongjin on 2017. 7. 25..
//  Copyright © 2017년 windroamer. All rights reserved.
//

import UIKit
import SceneKit
import GLKit

//Apple provides these GLKit functions for conversion:
//
//func GLKMathDegreesToRadians(_ degrees: Float) -> Float
//func GLKMathRadiansToDegrees(_ radians: Float) -> Float

class WMCamera: NSObject, NSCopying {
    var position:vector_float3
    var rotation:vector_float3
    
    fileprivate var initPosition:vector_float3
    fileprivate var initRotation:vector_float3
    
    public init(_ position:vector_float3,_ rotation:vector_float3)
    {
        self.position = position
        self.rotation = rotation
        initPosition = position
        initRotation = rotation
        super.init()
        self.resetCamera()
    }
    
    public func resetCamera() {
        position = initPosition
        rotation = initRotation
    }
    
    public func setDefaultCamera(_ position:vector_float3,_ rotation:vector_float3) {
        initPosition = position
        initRotation = rotation
    }
    
    @objc(copyWithZone:) public func copy(with zone: NSZone? = nil) -> Any
    {
        let cameraCopy:WMCamera = WMCamera.init(position,rotation)
        return cameraCopy
    }
    
    public func lookAt() -> matrix_float4x4 {
        // Create rotation matrix from quaternions in order to avoid gimbal lock error
        let rotX:GLKQuaternion = GLKQuaternionMakeWithAngleAndAxis(GLKMathDegreesToRadians(tilt), -1.0,  0.0,  0.0);
        let rotY:GLKQuaternion = GLKQuaternionMakeWithAngleAndAxis(GLKMathDegreesToRadians(pan),   0.0, -1.0,  0.0);
        let rotZ:GLKQuaternion = GLKQuaternionMakeWithAngleAndAxis(GLKMathDegreesToRadians(roll),  0.0,  0.0, -1.0);
        let rotXYZ:GLKQuaternion = GLKQuaternionNormalize(GLKQuaternionMultiply(rotX, GLKQuaternionMultiply(rotY, rotZ)));
        var glkMatRotXYZ:GLKMatrix4 = GLKMatrix4MakeWithQuaternion(rotXYZ);
        
        
        let pointerRotMat = UnsafeMutablePointer<matrix_float4x4>.allocate(capacity: 1)
        
        var glkMPointer = UnsafeMutablePointer(&glkMatRotXYZ.m)
        var glkPointer = UnsafeRawPointer(glkMPointer).bindMemory(to: GLKMatrix4.self, capacity: 1)
        
        defer {
            pointerRotMat.deallocate(capacity: 1)
        }
        memcpy (pointerRotMat, glkPointer, MemoryLayout<matrix_float4x4>.size)
        
        return matrix_multiply(matrix_from_translation(-position.x, -position.y, -position.z), pointerRotMat.pointee)
    }
    
    public var tilt:Float
    {
        get {
            return rotation[0]
            
        }
        set {
            var degrees = newValue
            if newValue < 0.0 {
                degrees = 360.0 + degrees;
            }
            if (degrees > 360.0) {
                degrees = degrees - 360.0
            }
            rotation[0] = degrees
        }
    }

    public var pan:Float {
        get {
            return rotation[1]
        }
        set {
            var degrees = newValue
            if degrees < 0 {
                degrees = 360.0 + degrees
            }
            if degrees > 360 {
                degrees = degrees - 360.0
            }
            rotation[1] = degrees
        }
    }
    public var roll:Float {
        get {
            return rotation[2]
        }
        set {
            var degrees = newValue
            if degrees < 0.0 {
                degrees = 360.0 + degrees
            }
            if degrees > 360 {
                degrees = degrees - 360.0
            }
            return rotation[2] = degrees
        }
    }
    public var xPosition:Float {
        get {
            return position[0]
        }
        set {
            position[0] = newValue
        }
    }
    public var yPosition:Float {
        get {
            return position[1]
        }
        set {
            position[1] = newValue
        }
    }
    public var zPosition:Float {
        get {
            return position[2]
        }
        set {
            position[2] = newValue
        }
    }
}

