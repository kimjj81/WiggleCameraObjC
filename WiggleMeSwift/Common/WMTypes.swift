//
//  WMTypes.swift
//  WiggleMeSwift
//
//  Created by KimJeongjin on 2017. 7. 25..
//  Copyright © 2017년 windroamer. All rights reserved.
//

import simd

public let UNIFORMS_ALIGNED = 16

public struct WMSharedUniforms {
    var projectionMatrix:matrix_float4x4
    var viewMatrix:matrix_float4x4
}

public struct WMPerInstanceUniforms {
    var modelMatrix:matrix_float4x4
}

public struct WMTextureVertex {
    var vx:Float, vy:Float, vz:Float;   // vertext position
    var tx:Float, ty:Float;             // texture coordinate
}
