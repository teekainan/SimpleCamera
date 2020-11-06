//
//  SimpleCamera.swift
//  CustomCamera
//
//  Created by Kai Nan on 06/11/2020.
//

import UIKit
import AVFoundation

public class SimpleCamera {
    
    public var previewLayer: AVCaptureVideoPreviewLayer?
    
    public enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .configurationFailed
    private let sessionQueue = DispatchQueue(label: "simple camera session queue")
    
    public let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput!
    private let photoOutput = AVCapturePhotoOutput()
    private var photoData: Data?
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var isCameraReady: Bool = false
    
    public init() { }
    
    public func initCamera(with view: UIView) {
        checkPermission()
        setupPreviewLayer(with: view)
        isCameraReady = true
    }
    
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            setupResult = .success
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { (granted) in
                self.setupResult = granted ? .success : .notAuthorized
                self.sessionQueue.resume()
            }
        default:
            setupResult = .notAuthorized
        }
        
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        if self.session.canSetSessionPreset(.photo) {
            self.session.sessionPreset = .photo
        }
        self.session.automaticallyConfiguresCaptureDeviceForWideColor = true
        
        
        // configure input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Default video device is unavailable.")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: device)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    let deviceOrientation = UIDevice.current.orientation
                    if deviceOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    self.previewLayer?.connection?.videoOrientation = initialVideoOrientation
                }
                
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // configure output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    private func setupPreviewLayer(with view: UIView) {
        previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer?.session = session
        DispatchQueue.main.async {
            guard let previewLayer = self.previewLayer else { return }
            view.clipsToBounds = true
            view.layer.addSublayer(previewLayer)
            previewLayer.frame = view.layer.frame
        }
    }
    
    public func startSession(completionHander: ((SessionSetupResult) -> Void)? = nil) {
        if !isCameraReady {
            print("SimpleCamera initCamera is not called. Please call initCamera before startSession")
            return
        }
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.addObservers()
                self.session.startRunning()
                completionHander?(self.setupResult)
                
            case .notAuthorized:
                completionHander?(self.setupResult)
                
            case .configurationFailed:
                completionHander?(self.setupResult)
            }
        }
    }
    
    public func stopSession() {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.removeObservers()
            }
        }
    }
    
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc
    private func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    public func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    public func viewWillTransition(to size: CGSize) {
        if let videoPreviewLayerConnection = previewLayer?.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                  deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }
            
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
        
        previewLayer?.frame.size = size
    }
    
    public func capturePhoto(photoSettings: AVCapturePhotoSettings? = nil, willCaptureHandler: (() -> Void)? = nil, photoProcessingHandler: ((Bool) -> Void)? = nil, completionHandler: @escaping (Data?, Error?) -> Void) {
        let videoPreviewLayerOrientation = previewLayer?.connection?.videoOrientation
        
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            
            let defaultSettings = AVCapturePhotoSettings()
            
            if self.videoDeviceInput.device.isFlashAvailable {
                defaultSettings.flashMode = .auto
            }
            
            defaultSettings.isHighResolutionPhotoEnabled = true
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings ?? defaultSettings, willCapturePhotoAnimation: {
                willCaptureHandler?()
            }, completionHandler: { (photoCaptureProcessor, data, error) in
                completionHandler(data, error)
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            }, photoProcessingHandler: { isProcessing in
                photoProcessingHandler?(isProcessing)
            })
            
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings ?? defaultSettings, delegate: photoCaptureProcessor)
        }
    }
}


// MARK: - Extensions
extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
}
