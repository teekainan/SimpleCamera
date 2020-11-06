//
//  ViewController.swift
//  SimpleCamera
//
//  Created by teekainan on 11/06/2020.
//  Copyright (c) 2020 teekainan. All rights reserved.
//

import UIKit
import SimpleCamera

class ViewController: UIViewController {

    
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var captureButton: UIButton!
    
    private var spinner: UIActivityIndicatorView!
    
    let simpleCamera = SimpleCamera()
    
    
    // MARK: - Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        captureButton.isEnabled = false
        previewView.isUserInteractionEnabled = false
        
        simpleCamera.initCamera(with: previewView)
        
        DispatchQueue.main.async {
            if #available(iOS 13.0, *) {
                self.spinner = UIActivityIndicatorView(style: .large)
            } else {
                self.spinner = UIActivityIndicatorView(style: .whiteLarge)
            }
            self.spinner.color = UIColor.white
            self.previewView.addSubview(self.spinner)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        simpleCamera.startSession { (setupResult) in
            switch setupResult {
            case .success:
                DispatchQueue.main.async {
                    self.captureButton.isEnabled = self.simpleCamera.session.isRunning
                    self.previewView.isUserInteractionEnabled = self.simpleCamera.session.isRunning
                }
                break
            case .notAuthorized:
                DispatchQueue.main.async {
                    let message = "SimpleCamera doesn't have permission to use the camera, please change privacy settings"
                    let alertController = UIAlertController(title: "SimpleCamera", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                    
                    alertController.addAction(
                        UIAlertAction(title: "Settings", style: .default) { (_) in
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                      options: [:],
                                                      completionHandler: nil)
                        }
                    )
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let message = "Unable to capture media"
                    let alertController = UIAlertController(title: "SimpleCamera", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        simpleCamera.stopSession()

        super.viewWillDisappear(animated)
    }
    
    // MARK: - Orientation
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        simpleCamera.viewWillTransition(to: size)
    }
    
    
    
    // MARK: - Camera Functions
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        if let devicePoint = simpleCamera.previewLayer?.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view)) {
            simpleCamera.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
        }
    }
    
    
    // MARK: - Capture Photo
    @IBAction func capturePhoto(_ sender: UIButton) {
        simpleCamera.capturePhoto(willCaptureHandler: {
            DispatchQueue.main.async {
                self.previewView.layer.opacity = 0
                UIView.animate(withDuration: 0.25) {
                    self.previewView.layer.opacity = 1
                }
                self.captureButton.isEnabled = false
            }
        }, photoProcessingHandler: { isProcessing in
            DispatchQueue.main.async {
                if isProcessing {
                    self.spinner.hidesWhenStopped = true
                    self.spinner.center = CGPoint(x: self.previewView.frame.size.width / 2.0, y: self.previewView.frame.size.height / 2.0)
                    self.spinner.startAnimating()
                } else {
                    self.spinner.stopAnimating()
                }
            }
        }) { (photoData, error) in
            DispatchQueue.main.async {
                self.captureButton.isEnabled = true
            }
            
            if let error = error {
                print("Error capturing photo: \(error)")
                return
            }
            
            guard let photoData = photoData else {
                print("No photo data resource")
                return
            }
            
            // show photo
            let imageVC = ImageViewController()
            imageVC.imageView.image = UIImage(data: photoData)
            self.present(imageVC, animated: true) {
                self.captureButton.isEnabled = true
            }
        }
    }
}

