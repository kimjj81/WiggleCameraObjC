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

@objc
class WMRenderer: NSObject, MTKViewDelegate {
    func draw(in view: MTKView) {
        self.render()
    }
    
    static let kMaxInflightBuffers:Int = 3
    
    var focalMagnificationFactor:Float
    var view:MTKView?
    var inflightSemaphore:DispatchSemaphore?

    var dynamicConstantBuffer:MTLBuffer?
    
    // Uniforms
    var sharedUniformBuffer:MTLBuffer?
    var meshModelUniformBuffer:MTLBuffer?
    var constantDataBufferIndex:UInt8 = 0
    
    var device:MTLDevice?
    var commandQueue:MTLCommandQueue?
    var depthStencilState:MTLDepthStencilState?
    var texturePipelineState:MTLRenderPipelineState?
    
    var meshModelTexture:MTLTexture?
    
    // Matrices
    var projectionMatrix:matrix_float4x4?
    var viewMatrix:matrix_float4x4?
    
    var cameraReferenceFrameDimensions:CGSize?
    var cameraFocalLength:Float
    
    var camera:WMCamera?
    
    var meshModel:WMMeshModel?
    var meshModelOrientationRadAngle:Float = 0
    
    var rendererQueue:DispatchQueue?
    
    init(_ view:MTKView?) throws {
        
        cameraReferenceFrameDimensions = CGSize.init(width: 4032, height: 3024)
        cameraFocalLength = 6600.0 // Initialize with a reasonable value (units: pixels)
        focalMagnificationFactor = 0.90 // Avoid cropping the image in case the calibration data is off
        
        rendererQueue = DispatchQueue.init(label: "com.WiggleMe.RendererQueue")
        constantDataBufferIndex = 0;
        inflightSemaphore = DispatchSemaphore.init(value: WMRenderer.kMaxInflightBuffers)
        
        super.init()
        
        self.setupMetal()
        
        guard device == nil else { throw MetalError.Unavailable }
        
        rendererQueue?.sync  { [weak self] in
            self?.setupView(view,device!)
            self?.setupUniformBuffers()
            
            self?.loadMeshes()
            self?.setuptPipeline()
            self?.setupCamera()
            
            self?.reshape()
        }
        
    }
    
    // Delegate
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.reshape()
    }
    
    // Called whenever the view needs to render
    
    func drawInMTKView(in view:MTKView)
    {
        self.render()
    }

}

extension WMRenderer {
    public func reshape() {
        let fov:Float = WMUtilities.fieldOfView(fromViewPort: (self.view?.bounds.size)!, depthOrientation: meshModelOrientationRadAngle, with: cameraFocalLength, with: cameraReferenceFrameDimensions!, magnificatioFactor: focalMagnificationFactor)
        let aspect:Float = Float((self.view?.bounds.size.width)!) / Float((self.view?.bounds.size.height)!)
        projectionMatrix = matrix_from_perspective(fov, aspect, 0.1, 1000.0);
    }
    public func update() {
        self.updateUniforms()
    }
    public func render() {
        inflightSemaphore?.wait()
        rendererQueue?.sync {
            self.update()
            
            // Create a new command buffer for each renderpass to the current drawable
            let commandBuffer:MTLCommandBuffer? = (commandQueue?.makeCommandBuffer())!
            commandBuffer?.label = "WiggleMe.Command";
        
            // Call the view's completion handler which is required by the view since it will signal its semaphore and set up the next buffer
            let block_sema:DispatchSemaphore = inflightSemaphore!;
            commandBuffer?.addCompletedHandler({ (buffer) in
               block_sema.signal()
            })
            // Obtain a renderPassDescriptor generated from the view's drawable textures
            let renderPassDescriptor:MTLRenderPassDescriptor? = view?.currentRenderPassDescriptor;
            
            if let renderPassDescriptor = renderPassDescriptor // If we have a valid drawable, begin the commands to render into it
            {
                // Create a render command encoder so we can render into something
                let commandEncoder:MTLRenderCommandEncoder? = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
                
                commandEncoder?.label = "WiggleMe.CommandEncoder";
                commandEncoder?.setDepthStencilState(depthStencilState)
                
                commandEncoder?.setFrontFacing(MTLWinding.counterClockwise)
                commandEncoder?.setCullMode(MTLCullMode.back)
                
                if let commandEncoder = commandEncoder {
                    self.drawMeshModelWithCommandEncoder(commandEncoder)
                }
                
                // We're done encoding commands
                commandEncoder?.endEncoding()
                
                // Schedule a present once the framebuffer is complete using the current drawable
                commandBuffer?.present((view?.currentDrawable)!);
            }
            
            // The render assumes it can now increment the buffer index and that the previous index won't be touched until we cycle back around to the same index
            constantDataBufferIndex = UInt8(Int(constantDataBufferIndex + 1) % Int(WMRenderer.kMaxInflightBuffers));
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer?.commit();
        }
    }
    public func setDepthMap( depthMap:CVPixelBuffer, intrinsicMatrix:matrix_float3x3, intrinsicMatrixReferenceDimensions:CGSize) {
        rendererQueue?.sync {
            cameraFocalLength = intrinsicMatrix.columns.0.x;
            cameraReferenceFrameDimensions = intrinsicMatrixReferenceDimensions;
            meshModel?.setDepthMap(depthMap, intrinsicMatrix, intrinsicMatrixReferenceDimensions)
            self.reshape();
        }
    }
    public func setDepthMapOrientation(angleRad:Float) {
        rendererQueue?.sync {
            meshModelOrientationRadAngle = angleRad
        }
    }
    public func setTextureOrientation(angleRad:Float) {
        rendererQueue?.sync {
            meshModel?.setTextureOrientation(angleRad)
        }
    }
    public func setTexture(_ image:UIImage) {
        let textureLoader:MTKTextureLoader = MTKTextureLoader.init(device: device!)
        
        do {
            let texture:MTLTexture = try textureLoader.newTexture(with: image.cgImage!, options:nil)
            rendererQueue?.sync {
                meshModelTexture = texture
                meshModelTexture?.label = "MeshModel Texture"
            }
        } catch {
            print(error)
        }
        
        
    }
    
    public func setCamera( camera:WMCamera) {
        self.camera = camera
    }
    public func copyCamera() -> WMCamera? {
        return camera?.copy() as? WMCamera
    }
}

extension WMRenderer {
//    func BUFFEROFFSET(n: Int) -> UnsafeRawPointer {
//        let ptr: UnsafePointer<Void>? = nil
//        return ptr + n
//    }
    
    fileprivate func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
    }
    
    fileprivate func setupView(_ view:MTKView?,_ device:MTLDevice?) {
        self.view = view
        self.view?.delegate = self
        self.view?.device = device
        self.view?.preferredFramesPerSecond = 60;
        
        self.view?.sampleCount = 4;
        self.view?.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
    }
    
    fileprivate func setupUniformBuffers() {
        sharedUniformBuffer = device?.makeBuffer(length: MemoryLayout<WMSharedUniforms>.size *  WMRenderer.kMaxInflightBuffers, options: MTLResourceOptions.cpuCacheModeWriteCombined)
        sharedUniformBuffer?.label = "Shared Uniforms"
        
        meshModelUniformBuffer = device?.makeBuffer(length: MemoryLayout<WMPerInstanceUniforms>.size * 1 * WMRenderer.kMaxInflightBuffers, options: MTLResourceOptions.cpuCacheModeWriteCombined)
        meshModelUniformBuffer?.label = "MeshModel Uniforms"
    }
    
    fileprivate func setuptPipeline () {
        let library:MTLLibrary = (device?.makeDefaultLibrary())!
        
        self.setupTexturePipelineWithLibrary(library)
        
        let depthstatedesc:MTLDepthStencilDescriptor = MTLDepthStencilDescriptor.init()
        depthstatedesc.depthCompareFunction = MTLCompareFunction.less
        depthstatedesc.isDepthWriteEnabled = true
        depthStencilState = device?.makeDepthStencilState(descriptor: depthstatedesc)
    }
    fileprivate func setupTexturePipelineWithLibrary(_ library:MTLLibrary) {
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
        pipelineStateDescriptor.sampleCount = (view?.sampleCount)!;
        pipelineStateDescriptor.vertexFunction = library.makeFunction(name: "texturevertexshader")
        pipelineStateDescriptor.fragmentFunction = library.makeFunction(name: "texturefragmentshader")
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = (view?.colorPixelFormat)!;
        pipelineStateDescriptor.depthAttachmentPixelFormat = (view?.depthStencilPixelFormat)!;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = (view?.depthStencilPixelFormat)!;
        
        do {
            texturePipelineState = try device?.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch {
            print(error)
        }
        
        if texturePipelineState === nil {
            print("Failed to created pipeline state")
        }
    }
    fileprivate func setupCamera () {
        camera = WMCamera.init(vector_float3(0.0,0.0,0.0), vector_float3(0.0,0.0,0.0))
        viewMatrix = camera?.lookAt()
    }
    
    fileprivate func loadMeshes() {
        meshModelOrientationRadAngle = 0.0;
        meshModel = WMMeshModel.init(768,576,matrix_identity_float4x4,device!)
    }
    
    fileprivate func updateUniforms() {
        self.updateCamera()
        self.updateSharedUniforms()
        self.updateMeshModelUniforms()
    }
    
    fileprivate func drawMeshModelWithCommandEncoder(_ commandEncoder:MTLRenderCommandEncoder)
    {
        // Set context state
        // #todo what is that?
//        commandEncoder.pushDebugGroup()
//        {
        if let meshModel =  meshModel {
            commandEncoder.setRenderPipelineState(texturePipelineState!);
            
            commandEncoder.setVertexBuffer(meshModel.vertexBuffer!, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(sharedUniformBuffer!, offset:MemoryLayout<WMSharedUniforms>.size * Int(constantDataBufferIndex) , index: 1)
            commandEncoder.setVertexBuffer(meshModelUniformBuffer!, offset: MemoryLayout<WMPerInstanceUniforms>.size * Int(constantDataBufferIndex), index: 2 )
            commandEncoder.setFragmentTexture(meshModelTexture, index: 0)
            
            commandEncoder.drawIndexedPrimitives(type: MTLPrimitiveType.triangleStrip,
                                                 indexCount:(meshModel.indexBuffer)!.length /
                                                    MemoryLayout<UInt32>.size,
                                                 indexType: MTLIndexType.uint32,
                                                 indexBuffer: meshModel.indexBuffer!,
                                                 indexBufferOffset: 0)
            
        }
        
//        commandEncoder.popDebugGroup()
    }

}
extension WMRenderer {
    fileprivate func updateCamera() {
        viewMatrix = camera?.lookAt()
    }
    
    public func updateSharedUniforms() {
        var uniforms:WMSharedUniforms? = sharedUniformBuffer?.contents().bindMemory(to: WMSharedUniforms.self, capacity: MemoryLayout<WMSharedUniforms>.size).pointee
        
        uniforms?.projectionMatrix = projectionMatrix!;
        uniforms?.viewMatrix = viewMatrix!;
    }
    
    fileprivate func updateMeshModelUniforms () {
        let modelMatrix:matrix_float4x4 = matrix_from_rotation(meshModelOrientationRadAngle, 0.0, 0.0, 1.0);
    
        var uniforms:WMPerInstanceUniforms = meshModelUniformBuffer!.contents().bindMemory(to: WMPerInstanceUniforms.self, capacity: MemoryLayout<WMPerInstanceUniforms>.size).pointee
        uniforms.modelMatrix = modelMatrix;
    }
}
