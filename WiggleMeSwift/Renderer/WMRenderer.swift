//
//  WMRenderer.swift
//  WiggleMeSwift
//
//  Created by KimJeongjin on 2017. 7. 25..
//  Copyright © 2017년 windroamer. All rights reserved.
//

import Foundation;
import Metal;
import MetalKit;
import CoreVideo;
import SceneKit

enum MetalError : Error{
    case Unavailable
}

class WMRenderer: NSObject , MTKViewDelegate{
    static let kMaxInflightBuffers:Int = 3
    
    var focalMagnificationFactor:Float
    var view:MTKView?
    var _inflight_semaphore:DispatchSemaphore?

    var _dynamicConstantBuffer:MTLBuffer?
    
    // Uniforms
    var _sharedUniformBuffer:MTLBuffer?
    var _meshModelUniformBuffer:MTLBuffer?
    var _constantDataBufferIndex:UInt8 = 0
    
    var _device:MTLDevice?
    var _commandQueue:MTLCommandQueue?
    var _depthStencilState:MTLDepthStencilState?
    var _texturePipelineState:MTLRenderPipelineState?
    
    var _meshModelTexture:MTLTexture
    
    // Matrices
    var _projectionMatrix:matrix_float4x4?
    var _viewMatrix:matrix_float4x4?
    
    var _cameraReferenceFrameDimensions:CGSize?
    var _cameraFocalLength:Float
    
    var _camera:WMCamera?
    
    var _meshModel:WMMeshModel
    var _meshModelOrientationRadAngle:Float
    
    var _rendererQueue:DispatchQueue?
    
    init(_ view:MTKView?) throws {
        _cameraReferenceFrameDimensions = CGSize.init(width: 4032, height: 3024)
        _cameraFocalLength = 6600.0 // Initialize with a reasonable value (units: pixels)
        focalMagnificationFactor = 0.90 // Avoid cropping the image in case the calibration data is off
        
        _rendererQueue = DispatchQueue.init(label: "com.WiggleMe.RendererQueue")
        _constantDataBufferIndex = 0;
        _inflight_semaphore = DispatchSemaphore.init(value: WMRenderer.kMaxInflightBuffers)
        
        self.setuptMetal()
        
        _rendererQueue?.sync {
            
        }
        
        if _device == nil {
            throw MetalError.Unavailable
        }
    }
    
}
extension WMRenderer {
    public func reshape() {
        let fov:Float = WMUtilities.fieldOfView(fromViewPort: (self.view?.bounds.size)!, depthOrientation: _meshModelOrientationRadAngle, with: _cameraFocalLength, with: _cameraReferenceFrameDimensions!, magnificatioFactor: focalMagnificationFactor)
        let aspect:Float = Float((self.view?.bounds.size.width)!) / Float((self.view?.bounds.size.height)!)
        _projectionMatrix = matrix_from_perspective(fov, aspect, 0.1, 1000.0);
    }
    public func update() {
        
    }
    public func render() {
        
    }
    public func setDepthMap(_ depthMap:CVPixelBuffer,_ intrinsicMatrix:matrix_float3x3, intrinsicMatrixReferenceDimensions:CGSize) {
        
    }
    public func setDepthMapOrientation(angleRad:Float) {
        
    }
    public func setTextureOrientation(angleRad:Float) {
        
    }
    public func setCamera(_ camera:WMCamera) {
        
    }
    public func copyCamera() -> WMCamera {
        return WMCamera()
    }
}

extension WMRenderer{
    func BUFFER_OFFSET(n: Int) -> UnsafePointer<Void> {
        let ptr: UnsafePointer<Void> = nil
        return ptr + n
    }
    
    fileprivate func _setuptMetal() {
        _device = MTLCreateSystemDefaultDevice()
        _commandQueue = _device?.makeCommandQueue()
    }
    
    fileprivate func _setupView(_ view:MTKView, device:MTLDevice) {
        self.view = view
        self.view?.delegate = self
        self.view?.device = device
        self.view?.preferredFramesPerSecond = 60;
        
        self.view?.sampleCount = 4;
        self.view?.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
    }
    
    fileprivate func _setupUniformBuffers() {
        _sharedUniformBuffer = _device?.makeBuffer(length: MemoryLayout<WMSharedUniforms>.size *  WMRenderer.kMaxInflightBuffers, options: MTLResourceOptions.cpuCacheModeWriteCombined)
        _sharedUniformBuffer?.label = "Shared Uniforms"
        
        _meshModelUniformBuffer = _device?.makeBuffer(length: MemoryLayout<WMPerInstanceUniforms>.size * 1 * WMRenderer.kMaxInflightBuffers, options: MTLResourceOptions.cpuCacheModeWriteCombined)
        _meshModelUniformBuffer?.label = "MeshModel Uniforms"
    }
    
    fileprivate func _setuptPipeline () {
        let library:MTLLibrary = (_device?.makeDefaultLibrary())!
        
        self._setupTexturePipelineWithLibrary(library)
        
        let depthstatedesc:MTLDepthStencilDescriptor = MTLDepthStencilDescriptor.init()
        depthstatedesc.depthCompareFunction = MTLCompareFunction.less
        depthstatedesc.isDepthWriteEnabled = true
        _depthStencilState = _device?.makeDepthStencilState(descriptor: depthstatedesc)
    }
    fileprivate func _setupTexturePipelineWithLibrary(_ library:MTLLibrary) {
        // Create the vertex descriptor
        let vertexDescriptor:MTLVertexDescriptor = MTLVertexDescriptor.init()
        vertexDescriptor.attributes[0].format = MTLVertexFormat.float3
        vertexDescriptor.attributes[0].offset = 0;
        vertexDescriptor.attributes[0].bufferIndex = 0;
        vertexDescriptor.attributes[1].format = MTLVertexFormat.float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 4
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<WMTextureVertex>.size;
        vertexDescriptor.layouts[0].stepRate = 1;
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        
        // Create a reusable pipeline state
        let pipelineStateDescriptor:MTLRenderPipelineDescriptor = MTLRenderPipelineDescriptor.init()
        pipelineStateDescriptor.label = "TexturePipeline";
        pipelineStateDescriptor.sampleCount = view?.sampleCount;
        pipelineStateDescriptor.vertexFunction = library.makeFunction(name: "texture_vertex_shader")
        pipelineStateDescriptor.fragmentFunction = library.makeFunction(name: "texture_fragment_shader")
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = view?.colorPixelFormat;
        pipelineStateDescriptor.depthAttachmentPixelFormat = view?.depthStencilPixelFormat;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = view?.depthStencilPixelFormat;
        
        _texturePipelineState = _device?.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        if _texturePipelineState === nil {
            print("Failed to created pipeline state")
        }
    }
    fileprivate func setupCamera () {
    _camera = //[[WMCamera alloc] initCameraWithPosition:(vector_float3){0.0f, 0.0f, 0.0f}
        WMCamera
//    andRotation:(vector_float3){0.0f, 0.0f, 0.0f}];
    
    _viewMatrix = [_camera lookAt];
    }
    
    - (void)_loadMeshes
    {
    // MeshModel
    _meshModelOrientationRadAngle = 0.0f;
    _meshModel = [[WMMeshModel alloc] initWithColumns:768 rows:576
    modelMatrix:matrix_identity_float4x4
    device:_device];
    }

}

extension MTKViewDelegate {
    
}
