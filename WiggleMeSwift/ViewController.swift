//
//  ViewController.swift
//  WiggleMeSwift
//
//  Created by KimJeongjin on 2017. 7. 25..
//  Copyright © 2017년 windroamer. All rights reserved.
//

import UIKit
import CoreMotion

import simd
import AVFoundation
import ImageIO
import CoreVideo
import Photos
import MetalKit

class ViewController: UIViewController ,UINavigationControllerDelegate, UIImagePickerControllerDelegate{
    var renderer:WMRenderer?;
    var motionManager:CMMotionManager?
    var requestPhotoLibrary:Bool?
    var updateTimer:Timer?
    var useGyroscope:Bool?
    var effectRotation:Float?
    var referenceMotionAttitude:CMAttitude?
    var adjustedMotionPitch:Float?
    var adjustedMotionRoll:Float?
    var matrixDeviceOrientation:matrix_float4x4?

    override func viewDidLoad() {
        requestPhotoLibrary = true;
        useGyroscope = false;
        effectRotation = 0.0;
        referenceMotionAttitude = nil;
        matrixDeviceOrientation = matrix_identity_float4x4;
        
        super.viewDidLoad()
        PHPhotoLibrary.requestAuthorization { (phstatus) in
            print("PHAuthorizationStatus = \(phstatus)")
        }
        // Do any additional setup after loading the view, typically from a nib.
        do {
            renderer = try WMRenderer.init((self.view as! MTKView))
        } catch {
            print("self.view : \(self.view)")
            print("Renderer를 못만들어 + \(error.localizedDescription)")
        }
        // Gyroscope
        motionManager = CMMotionManager.init()
        motionManager?.deviceMotionUpdateInterval = 1.0 / 60.0;
        
        // Update timer
        updateTimer =  Timer.scheduledTimer(timeInterval: 1.0/60.0, target: self, selector: #selector(doTimerUpdate), userInfo: nil, repeats: true)
        
        // Gestures
        let singleTapRecognizer = UITapGestureRecognizer.init(target: self, action: #selector(didSingleTap(_:)))
        singleTapRecognizer.numberOfTapsRequired = 1;
        self.view.addGestureRecognizer(singleTapRecognizer)
        
        let doubleTapRecognizer = UITapGestureRecognizer.init(target: self, action: #selector(didDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2;
        self.view.addGestureRecognizer(doubleTapRecognizer)
        
        let pinchRecognizer = UIPinchGestureRecognizer.init(target:self, action:#selector(didPinch(_:)))
        self.view.addGestureRecognizer(pinchRecognizer)
     
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    override func viewDidAppear(_ animated: Bool) {
        if requestPhotoLibrary != nil {
            self.selectPhotoFromLibrary()
        }
    }
    
//   - (BOOL)shouldAutorotate {
//    return YES;
//    }
//    - (UIInterfaceOrientationMask)supportedInterfaceOrientations{
//    return UIInterfaceOrientationMaskAll;
//    }
//
//    - (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
//    return UIInterfaceOrientationPortrait;
//    }
//
//    - (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
//    {
//    return YES;
//    }
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let deviceOrientation = UIDevice.current.orientation;
        if deviceOrientation == UIDeviceOrientation.faceDown || deviceOrientation == UIDeviceOrientation.faceUp {
            return;
        }
        
        var deviceOrientationRadAngle = 0.0;
        switch (deviceOrientation) {
            case UIDeviceOrientation.portraitUpsideDown:
                deviceOrientationRadAngle = Double.pi;
            case UIDeviceOrientation.landscapeLeft:
                deviceOrientationRadAngle = Double.pi
            case UIDeviceOrientation.landscapeRight:
                deviceOrientationRadAngle = -(Double.pi / 2.0)
            default :
                break
        }
        
        matrixDeviceOrientation = matrix_from_rotation(Float(deviceOrientationRadAngle), 0.0, 0.0, 1.0);
        
        referenceMotionAttitude = nil;
    }
    
    fileprivate func updateForDeviceMotion(_ deviceMotion:CMDeviceMotion)
    {
        let camera = renderer?.copyCamera()
        
        if referenceMotionAttitude != nil {
            referenceMotionAttitude = deviceMotion.attitude.copy() as? CMAttitude
            adjustedMotionPitch = 0.0;
            adjustedMotionRoll = 0.0;
        }
        
        let attitude:CMAttitude = (motionManager?.deviceMotion?.attitude)!
        
        attitude.multiply(byInverseOf: referenceMotionAttitude!)
        
        let roll:Float  = Float(attitude.roll - Double(adjustedMotionRoll!))
        let pitch:Float = Float(attitude.pitch - Double(adjustedMotionPitch!))
        
        if fabs(roll) > Float(ViewController.kEffectGyroResetEpsilon) {
            adjustedMotionRoll = adjustedMotionRoll! + Float(ViewController.kEffectGyroResetRate) * ((roll > 0.0) ? 1.0 : -1.0);
        }
        
        if fabs(pitch) > Float(ViewController.kEffectGyroResetEpsilon) {
            adjustedMotionPitch = adjustedMotionPitch! + Float(ViewController.kEffectGyroResetRate) * ((pitch > 0.0) ? 1.0 : -1.0);
        }
        
        let rx = sinf(roll) * Float(ViewController.kEffectGyroRadius)
        let ry = sinf(-pitch) * Float(ViewController.kEffectGyroRadius)
        
        let vrxy = matrix_multiply(matrixDeviceOrientation!, vector4(rx, ry, 0.0, 1.0))
        camera?.xPosition = vrxy.x / vrxy.w
        camera?.yPosition = vrxy.y / vrxy.w
        
        renderer?.camera = camera
    }
    
    @objc fileprivate func doTimerUpdate(_ timer:Timer)
    {
        let camera:WMCamera = (renderer?.copyCamera())!
    
        effectRotation = effectRotation! + Float(ViewController.kEffectRotationRate)
        if let effectRotation = effectRotation {
            if  fabs(Double(effectRotation)) >= 360.0 {
                self.effectRotation? -= 360.0;
            }
        }
    
        let theta = effectRotation! / 180.0 * Float.pi
        let rx = cosf(-theta) * Float(ViewController.kEffectRotationRadius);
        let ry = sinf(-theta) * Float(ViewController.kEffectRotationRadius);
        
        camera.xPosition = rx
        camera.yPosition = ry
        renderer?.setCamera(camera: camera)
    }
}

// gesture
extension ViewController {
    @objc fileprivate func didSingleTap(_ gestureRecognizer:UITapGestureRecognizer)
    {
        useGyroscope = !useGyroscope!
    
        if useGyroscope != nil {
            updateTimer?.invalidate()
            updateTimer = nil;
        
            referenceMotionAttitude = nil;

            motionManager?.startDeviceMotionUpdates(to: OperationQueue.main, withHandler: { (motion, error) in
                self.updateForDeviceMotion(motion!)
            })
        } else {
            motionManager?.stopDeviceMotionUpdates()
        
            updateTimer = Timer.scheduledTimer(timeInterval: 1.0/60.0,
                                               target: self,
                                               selector: #selector(doTimerUpdate(_:)),
                                               userInfo: nil,
                                               repeats: true)
        }
    }
    
    @objc fileprivate func didDoubleTap(_ gestureRecognizer:UITapGestureRecognizer)
    {
        self.selectPhotoFromLibrary()
    }
    
    static var lastScale:Float = 0.0
    
    @objc fileprivate func didPinch(_ gestureRecognizer:UIPinchGestureRecognizer)
    {
        if gestureRecognizer.state == UIGestureRecognizerState.began {
            ViewController.lastScale = Float(gestureRecognizer.scale)
        }
        
        if gestureRecognizer.state == UIGestureRecognizerState.began ||
        gestureRecognizer.state == UIGestureRecognizerState.changed
        {
            let newScale = (Float(gestureRecognizer.scale) - ViewController.lastScale) * 25.0;
            
            let camera = renderer?.copyCamera()
            let zPosition = min(Float(ViewController.kEffectMagnificationRangeMax), max(Float(ViewController.kEffectMagnificationRangeMin), Float((camera?.zPosition)! + newScale)))
            
            let mag = Float(ViewController.kEffectMagnificationMinFactor) - (Float(zPosition) * Float(ViewController.kEffectMagnificationRate))
            
            camera?.zPosition = zPosition
            renderer?.camera = camera
            renderer?.focalMagnificationFactor = mag
            
            ViewController.lastScale = Float(gestureRecognizer.scale)
        }
    }
    
    fileprivate func selectPhotoFromLibrary()
    {
        let imagePickerController = UIImagePickerController.init()
        imagePickerController.sourceType = UIImagePickerControllerSourceType.photoLibrary;
        imagePickerController.delegate = self;
//[self presentViewController:imagePickerController animated:YES completion:nil];
        self.present(imagePickerController, animated: true, completion: nil)
    }
}

extension ViewController {
    static let kEffectRotationRate = 3.5
    static let kEffectRotationRadius = 1.5
    static let kEffectGyroRadius = 6.0
    static let kEffectGyroResetEpsilon = 0.01
    static let kEffectGyroResetRate = 0.005
    static let kEffectMagnificationRate = 0.01
    static let kEffectMagnificationMinFactor = 0.90
    static let kEffectMagnificationRangeMin = 0.0
    static let kEffectMagnificationRangeMax = 30.0
}
