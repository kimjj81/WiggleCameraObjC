//
//  WMUtilities.swift
//  WiggleMeSwift
//
//  Created by KimJeongjin on 2017. 7. 25..
//  Copyright © 2017년 windroamer. All rights reserved.
//

import UIKit
import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import AVFoundation

class WMUtilities: NSObject {
    static public func randAngleFromImageOrientation(_ orientation:CGImagePropertyOrientation) -> Float {
        switch(orientation) {
        case .down:
            return Float(Double.pi)
        case .right:
            return Float(Double.pi / 2.0)
        case .left:
            return Float( -(Double.pi / 2.0))
        default :
            return 0;
        }
    }
    
    // Maintain image contents regardless of the orientation of the device
    static public func fieldOfView(fromViewPort viewPort:CGSize , depthOrientation depthAngleRad:Float, with focalLength:Float, with referenceFrameDimensions:CGSize, magnificatioFactor magFactor:Float) -> Float
    {
        let referenceFrameAspectRatio:Float = Float(referenceFrameDimensions.width / referenceFrameDimensions.height)
        
        let isDepthLandscape:Bool = (fmod(fabs(Double(depthAngleRad)), Double.pi) < (1e-4))
        let isViewLandscape = isDepthLandscape ? Float(viewPort.width / viewPort.height) > referenceFrameAspectRatio : Float(viewPort.height / viewPort.width ) < referenceFrameAspectRatio
        
        var fov:Float = 2.0 * atanf(Float(referenceFrameDimensions.width) / Float(2.0 * focalLength * magFactor))
        if isDepthLandscape != isViewLandscape {
            fov *= referenceFrameAspectRatio
        }
        if !isViewLandscape {
            fov = 2.0 * atanf(Float(tanf(0.5*fov) * Float(viewPort.height / viewPort.width)))
        }
        return fov
    }
    
    static public func imageProperties(from imageData:CFData?) -> Dictionary<String, Any>? {
        let cgImageSource:CGImageSource = CGImageSourceCreateWithData((imageData)!, nil)!
        return CGImageSourceCopyPropertiesAtIndex(cgImageSource, 0,nil) as? Dictionary<String, Any>
    }
    static public func depthData(from imageData:CFData?) -> AVDepthData? {
        var depthData:AVDepthData?
        if let imageData = imageData, let imageSource:CGImageSource = CGImageSourceCreateWithData(imageData,nil) {
            let auxDataDictionary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(imageSource, 0, kCGImageAuxiliaryDataTypeDisparity)
            if let auxDataDictionary = auxDataDictionary {
                do {
                try depthData = AVDepthData.init(fromDictionaryRepresentation: auxDataDictionary as! [AnyHashable : Any])
                } catch {
                    depthData = depthData?.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
                }
            } else {
                depthData = depthData?.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
            }
        }
        return depthData;
    }
}
