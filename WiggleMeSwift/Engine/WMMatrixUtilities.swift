//
//  WMMatrixUtilities.swift
//  WiggleMeSwift
//
//  Created by KimJeongjin on 2017. 7. 25..
//  Copyright © 2017년 windroamer. All rights reserved.
//

import simd
import GLKit

public let matrix_ndc_float4x4:matrix_float4x4 = matrix_float4x4.init([ float4.init([1.0, 0.0, 0.0, 0.0]),
                                                                        float4.init([0.0, 1.0, 0.0, 0.0]),
                                                                        float4.init([0.0, 0.0, 0.5, 0.5]),
                                                                        float4.init([0.0, 0.0, 0.0, 1.0])
                                                                       ])

public func matrix_from_frustrum(_ left:Float,_ right:Float,_ bottom:Float,_ top:Float,_ nearZ:Float,_ farZ:Float) -> matrix_float4x4
{
    let A:Float = (right + left) / (right - left)
    let B:Float = (top + bottom) / (top - bottom)
    let C:Float = ((farZ + nearZ) / (farZ - nearZ))
    let D:Float = ((2.0 * farZ * nearZ) / (farZ - nearZ))

    let sx:Float = (2.0 * nearZ) / (right - left)
    let sy:Float = (2.0 * nearZ) / (top - bottom)

    let m:matrix_float4x4 = matrix_float4x4.init([
        [sx,0.0,A,0.0],
        [0.0,sy,B,0.0],
        [0.0,0.0,C,D],
        [0.0,0.0,-1.0,0.0]
        ])

    return matrix_multiply(matrix_ndc_float4x4, m)
}

public func matrix_from_perspective(_ fovY:Float,_ aspect:Float,_ nearZ:Float,_ farZ:Float) -> matrix_float4x4
{
    let hheight:Float = nearZ * tanf(fovY * 0.5)
    let hwidth:Float  = hheight * aspect

    return matrix_from_frustrum(-hwidth, hwidth, -hheight, hheight, nearZ, farZ)
}

public func matrix_from_translation(_ x:Float,_ y:Float,_ z:Float) -> matrix_float4x4
{
    var m:matrix_float4x4 = matrix_identity_float4x4
    m.columns.3 = vector_float4.init([ x, y, z, 1.0 ])
    
    return m
}

public func matrix_from_rotation(_ radians:Float,_ x:Float,_ y:Float,_ z:Float) -> matrix_float4x4
{
    var v:vector_float3 = simd_normalize(vector_float3.init([x, y, z]))
    let cos:Float = cosf(radians)
    let cosp:Float = 1.0 - cos
    let sin:Float = sinf(radians)
    
    let m:matrix_float4x4 = matrix_float4x4.init(columns: (simd_float4.init([cos + cosp * v.x * v.x,
                                                                            cosp * v.x * v.y + v.z * sin,
                                                                            cosp * v.x * v.z - v.y * sin,
                                                                            0.0,]),
                                                          simd_float4.init([cosp * v.x * v.y - v.z * sin,
                                                                            cos + cosp * v.y * v.y,
                                                                            cosp * v.y * v.z + v.x * sin,
                                                                            0.0,]),
                                                          simd_float4.init([cosp * v.x * v.z + v.y * sin,
                                                                            cosp * v.y * v.z - v.x * sin,
                                                                            cos + cosp * v.z * v.z,
                                                                            0.0,]),
                                                          simd_float4.init([0.0, 0.0, 0.0, 1.0])))
    return m
}

public func matrix_from_scale(_ sx:Float,_ sy:Float,_ sz:Float) -> matrix_float4x4
{
    let m:matrix_float4x4 = matrix_float4x4.init(columns:(simd_float4.init([sx,   0,   0, 0 ]),
                                                          simd_float4.init([0,  sy,   0, 0]),
                                                          simd_float4.init([0,   0,  sz, 0]),
                                                          simd_float4.init([0,   0,   0, 1])))
    return m
}
