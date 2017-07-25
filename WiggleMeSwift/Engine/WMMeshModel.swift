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
    }
    public func setTextureOrientation(_ radAngle:Float) {
        matTextureRot = matrix_from_rotation(radAngle, 0, 0, 1)
    }
    
    public func setDepthMap(_ depthMap:CVPixelBuffer,_ instrinsicMatrix:matrix_float3x3, _ instrinsicMatrixReferenceDimensions:CGSize) {
        
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
    
    fileprivate func createMeshCoordinatesWithDepthMap(_ depthMapPixelBuffer:CVPixelBuffer, intrinsicMatrix:matrix_float3x3, intrinsicMatrixReferenceDimensions:CGSize)
    {
        let matOrig:matrix_float4x4 = matrix_from_scale(1,-1,1)
        CVPixelBufferLockBaseAddress(depthMapPixelBuffer, CVPixelBufferLockFlags.readOnly)
        
        let depthMapWidth:Int = CVPixelBufferGetWidth(depthMapPixelBuffer)
        let depthMapHeight:Int = CVPixelBufferGetHeight(depthMapPixelBuffer)
        let pin = CVPixelBufferGetBaseAddress(depthMapPixelBuffer)
        let rowBytesSize:size_t = CVPixelBufferGetBytesPerRow(depthMapPixelBuffer)
        
        
//        let pvertext = UnsafeMutablePointer<WMTexture vertexBuffer?.contents()
        
        let cx:Float = intrinsicMatrix.columns.0.z / Float( intrinsicMatrixReferenceDimensions.width ) * Float(numColumns);
        let cy:Float = intrinsicMatrix.columns.1.z / Float (intrinsicMatrixReferenceDimensions.height ) * Float(numRows );
        let focalLength:Float = intrinsicMatrix.columns.0.x / Float( intrinsicMatrixReferenceDimensions.width ) * Float(numColumns);
        
        let xMin = FLT_MAX;
        let xMax = FLT_MIN;
        let yMin = FLT_MAX;
        let yMax = FLT_MIN;
        let zMin = FLT_MAX;
        let zMax = FLT_MIN;
        
        for y in 1...numRows {
            for x in 1...numColumns {
                let xs = (Float(x) / Float(numColumns - 1));
                let ys = (Float(y) / Float(numRows - 1));
                
                let xsi = Int(Int(xs) * Int(depthMapWidth - 1));
                let ysi = Int(Int(ys) * Int(depthMapHeight - 1));
                
                let xsip = min(xsi + 1, depthMapWidth - 1);
                let ysip = min(ysi + 1, depthMapHeight - 1);
                
                let c00 = *(float*)(&pin[ysi  * rowBytesSize + xsi  * sizeof(float)]);
                let c10 = *(float*)(&pin[ysi  * rowBytesSize + xsip * sizeof(float)]);
                let c01 = *(float*)(&pin[ysip * rowBytesSize + xsi  * sizeof(float)]);
                let c11 = *(float*)(&pin[ysip * rowBytesSize + xsip * sizeof(float)]);
                
                let dxs = (xs - xs);
                let dys = (ys - ys);
                let dout = lerp(lerp(c00, c10, dxs), lerp(c01, c11, dxs), dys);
                
                // Creates the vertex from the top down, so that our triangles are
                // counter-clockwise.
                float zz = 1.0f / dout;
                float xx = (x - cx) * zz / focalLength;
                float yy = (y - cy) * zz / focalLength;
                
                // We work in centimeters
                xx = xx * 100.0f;
                yy = yy * 100.0f;
                zz = zz * 100.0f;
                
                xMin = MIN(xMin, xx);
                xMax = MAX(xMax, xx);
                yMin = MIN(yMin, yy);
                yMax = MAX(yMax, yy);
                zMin = MIN(zMin, zz);
                zMax = MAX(zMax, zz);
                
                const vector_float4 pver = matrix_multiply(matrix_multiply(matOrig, _modelMatrix), (vector_float4){xx, yy, zz, 1.0f});
                pvertex__->vx = pver.x / pver.w;
                pvertex__->vy = pver.y / pver.w;
                pvertex__->vz = pver.z / pver.w;
                
                const vector_float4 ptex = matrix_multiply(_matTextureRot, (vector_float4){xs - 0.5f, ys - 0.5f, 0.0f, 1.0f});
                pvertex__->tx = (ptex.x / ptex.w) + 0.5f;
                pvertex__->ty = (ptex.y / ptex.w) + 0.5f;
                
                pvertex__++;
            }
        }
    }
}
