//
//  WMMeshModel.swift
//  WiggleMeSwift
//
//  Created by KimJeongjin on 2017. 7. 25..
//  Copyright © 2017년 windroamer. All rights reserved.
//

import UIKit
import Metal
import CoreVideo
import simd
import GLKit

//#define lerp(a, b, t) ((a) * ( 1 - (t) ) + (b) * (t))
class WMMeshModel: NSObject {
    var vertexBuffer:MTLBuffer?
    var indexBuffer:MTLBuffer?
    var modelMatrix:matrix_float4x4?
    
    fileprivate var numColumns:Int = 0
    fileprivate var numRows:Int = 0
    fileprivate var vertexCount:Int = 0
    fileprivate var indexCount:Int = 0
    fileprivate var matTextureRot:matrix_float4x4
    
    public init(_ numColumns:Int,_ numRows:Int, _ modelMatrix:matrix_float4x4,_ device:MTLDevice) {
        self.modelMatrix = modelMatrix
        self.numColumns = numColumns
        self.numRows = numRows
        self.matTextureRot = matrix_identity_float4x4
        
        super.init()
        
        self.createVertexAndIndexBufferWithDevice(device)
        self.createMeshIndices()
    }
    public func setTextureOrientation(_ radAngle:Float) {
        matTextureRot = matrix_from_rotation(radAngle, 0, 0, 1)
    }
    
    public func setDepthMap(_ depthMap:CVPixelBuffer,_ intrinsicMatrix:matrix_float3x3, _ intrinsicMatrixReferenceDimensions:CGSize) {
        self.createMeshCoordinatesWithDepthMap(depthMap, intrinsicMatrix: intrinsicMatrix, intrinsicMatrixReferenceDimensions: intrinsicMatrixReferenceDimensions)
    }
}

extension WMMeshModel {
    fileprivate func createVertexAndIndexBufferWithDevice(_ device:MTLDevice) {
        vertexCount = numColumns * numRows;
        vertexBuffer = device.makeBuffer(length: vertexCount, options:MTLResourceOptions.cpuCacheModeWriteCombined)
        vertexBuffer?.label = "Vertices (MeshModel)"
        let numStrip:Int = numRows - 1
        let nDegens:Int = 2 * (numStrip - 1)
        let verticesPerStrip = 2 * numColumns
        
        indexCount = verticesPerStrip * numStrip + nDegens
        indexBuffer = device.makeBuffer(length: (indexCount * MemoryLayout<UInt32>.size), options: MTLResourceOptions.cpuCacheModeWriteCombined)
        indexBuffer?.label = "Indices (MeshModel)"
        
    }

    fileprivate func lerp(_ op1:Float,_ op2:Float, _ t:Float) -> Float {
        //    lerp(a, b, t) ((a) * ( 1 - (t) ) + (b) * (t))
        return (op1 * (1-t)) + op2*t
    }
    
    fileprivate func createMeshCoordinatesWithDepthMap(_ depthMapPixelBuffer:CVPixelBuffer, intrinsicMatrix:matrix_float3x3, intrinsicMatrixReferenceDimensions:CGSize)
    {
        let matOrig:matrix_float4x4 = matrix_from_scale(1,-1,1)
        CVPixelBufferLockBaseAddress(depthMapPixelBuffer, CVPixelBufferLockFlags.readOnly)
        
        let depthMapWidth:Int = CVPixelBufferGetWidth(depthMapPixelBuffer)
        let depthMapHeight:Int = CVPixelBufferGetHeight(depthMapPixelBuffer)
        let pin = CVPixelBufferGetBaseAddress(depthMapPixelBuffer)
        let rowBytesSize:size_t = CVPixelBufferGetBytesPerRow(depthMapPixelBuffer)
        
        
        let pvertex = vertexBuffer?.contents().bindMemory(to: WMTextureVertex.self, capacity: 1)
        
        let cx:Float = intrinsicMatrix.columns.0.z / Float( intrinsicMatrixReferenceDimensions.width ) * Float(numColumns);
        let cy:Float = intrinsicMatrix.columns.1.z / Float (intrinsicMatrixReferenceDimensions.height ) * Float(numRows );
        let focalLength:Float = intrinsicMatrix.columns.0.x / Float( intrinsicMatrixReferenceDimensions.width ) * Float(numColumns);
        
        var xMin = Float.greatestFiniteMagnitude;
        var xMax = Float.leastNormalMagnitude;
        var yMin = Float.greatestFiniteMagnitude;
        var yMax = Float.leastNormalMagnitude;
        var zMin = Float.greatestFiniteMagnitude;
        var zMax = Float.leastNormalMagnitude;
        
        for y in 1...numRows {
            for x in 1...numColumns {
                let xs = (Float(x) / Float(numColumns - 1));
                let ys = (Float(y) / Float(numRows - 1));
                
                let xsi = Int(Int(xs) * Int(depthMapWidth - 1));
                let ysi = Int(Int(ys) * Int(depthMapHeight - 1));
                
                let xsip = min(xsi + 1, depthMapWidth - 1);
                let ysip = min(ysi + 1, depthMapHeight - 1);
                
                let c00:Float = pin!.advanced(by: ((ysi  * rowBytesSize + xsi  * MemoryLayout<Float>.size))).load(as: Float.self)
                let c10:Float = pin!.advanced(by: ((ysi  * rowBytesSize + xsip  * MemoryLayout<Float>.size))).load(as: Float.self)
                let c01:Float = pin!.advanced(by: ((ysip * rowBytesSize + xsi  * MemoryLayout<Float>.size))).load(as: Float.self)
                let c11:Float = pin!.advanced(by: ((ysip * rowBytesSize + xsip  * MemoryLayout<Float>.size))).load(as: Float.self)
                
                let dxs = (xs - xs);
                let dys = (ys - ys);
                let dout = self.lerp(self.lerp(c00, c10, dxs),self.lerp(c01, c11, dxs), dys)
                
                // Creates the vertex from the top down, so that our triangles are
                // counter-clockwise.
                var zz = 1.0 / dout;
                var xx = (Float(x) - cx) * zz / focalLength;
                var yy = (Float(y) - cy) * zz / focalLength;
                
                // We work in centimeters
                xx = xx * 100.0;
                yy = yy * 100.0;
                zz = zz * 100.0;
                
                xMin = simd_min(xMin, xx);
                xMax = simd_max(xMax, xx);
                yMin = simd_min(yMin, yy);
                yMax = simd_max(yMax, yy);
                zMin = simd_min(zMin, zz);
                zMax = simd_max(zMax, zz);
                
                let pver:vector_float4 = matrix_multiply(matrix_multiply(matOrig, modelMatrix!), vector_float4.init(xx, yy, zz, 1.0));
                
                pvertex?.pointee.vx = pver.x / pver.w;
                pvertex?.pointee.vy = pver.y / pver.w;
                pvertex?.pointee.vz = pver.z / pver.w;
                
                let ptex:vector_float4 = matrix_multiply(matTextureRot, vector_float4.init(xs - 0.5, ys - 0.5, 0.0, 1.0));
                pvertex?.pointee.tx = (ptex.x / ptex.w) + 0.5;
                pvertex?.pointee.ty = (ptex.y / ptex.w) + 0.5;
                
                pvertex?.successor();
            }
        }
    }
    
    public func createMeshIndices()
    {
    // A complete object can be described as a degenerate strip,
    // which contains zero-area triangles that the processing software
    // or hardware will discard.
    //
    //     1 ---- 2 ---- 3 ---- 4 ---- 5
    //     |    /^|    /^|    /^|    /^|
    //     |  /   |  /   |  /   |  /   |
    //     v/     v/     v/     v/     |
    // deg 6 ---- 7 ---- 8 ---- 9 ----10 deg
    //     |    /^|    /^|    /^|    /^|
    //     |  /   |  /   |  /   |  /   |
    //     v/     v/     v/     v/     |
    //     11----12 ----13 ----14 ----15
    //
    // Indices:
    // 1, 6, 2, 7, 3, 8, 4, 9, 5, 10, (10, 6), 6, 11, 7, 12, 8, 13, 9, 14, 10, 15
    
        let pind = indexBuffer?.contents().bindMemory(to: UInt32.self, capacity: 1)
        
        for y:UInt32 in 1..<(UInt32(numRows) - 1) {
        // Degenerate index on non-first row
            if (y > 0) {
                pind?.pointee = (y * UInt32(numColumns))
                pind?.advanced(by: 1)
            }
        
            // Current strip
            for x:UInt32 in 1..<UInt32(numColumns) {
                pind?.pointee = (y * UInt32(numColumns) + x);
                pind?.advanced(by: 1)
                pind?.pointee = ((y + 1) * UInt32(numColumns) + x);
                pind?.advanced(by: 1)
            }
        
            // Degenerate index on non-last row
            if (y < (numRows - 2)) {
                pind?.pointee = ((y + 1) * UInt32(numColumns) + UInt32(numColumns - 1));
                pind?.advanced(by:1)
            }
        }
    }
}
