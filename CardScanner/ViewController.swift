//
//  ViewController.swift
//  CardScanner
//
//  Created by Reed Carson on 5/14/18.
//  Copyright © 2018 Reed Carson. All rights reserved.
//

import UIKit
import AVFoundation
import FirebaseMLVision


struct Price {
    var market: String
    var marketFoil: String
}

class ViewController: UIViewController, MTGReaderDelegate {
    //MARK: - Outlets
    @IBOutlet weak var cardDetectionArea: UIView!
    @IBOutlet weak var detectButton: UIButton!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var overlayView: UIView!
    @IBOutlet weak var isDetectingIndicatorView: UIView!
    
    @IBOutlet weak var captureCurrentFrameButton: UIButton!
    @IBOutlet weak var scannedTextDisplayTextView: UITextView!
    
    //MARK: - AV Properties
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var dataOutput: AVCaptureVideoDataOutput?
    private let dataOutputQueue = DispatchQueue(label: "com.carsonios.captureQueue")
    var videoOrientation: AVCaptureVideoOrientation = .landscapeRight
    var visionOrientation: VisionDetectorImageOrientation = .rightTop
    
    //MARK: - Private properties
    private var outputIsOn = false {
        didSet {
            guard isDetectingIndicatorView != nil else { return }
            isDetectingIndicatorView.backgroundColor = outputIsOn ? .green : .yellow
        }
    }
 
    private var debugFrames = [UIView]()
    private var outputCounter = 0
   
    var captureSampleBufferRate = 2

    let mtgTitleReader = MTGTitleReader()

    let apiManager = ApiManager()
    
    //MARK: - Orientation Properties
    override var shouldAutorotate: Bool {
        return true
    }

    //MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        mtgTitleReader.readerDelegate = self
        mtgTitleReader.validRectForReading = cardDetectionArea.frame
        mtgTitleReader.accuracyRequired = 0.75
        mtgTitleReader.visionResultsProcessingFrequency = 5
        
        isDetectingIndicatorView.backgroundColor = .yellow
        captureCurrentFrameButton.backgroundColor = .red
        captureCurrentFrameButton.layer.borderColor = UIColor.black.cgColor
        captureCurrentFrameButton.layer.borderWidth = 2
        
        overlayView.backgroundColor = .clear
        
        scannedTextDisplayTextView.text = ""
        scannedTextDisplayTextView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        setupCamera()
        
        cardDetectionArea.layer.borderWidth = 2
        cardDetectionArea.layer.borderColor = UIColor.red.cgColor
        cardDetectionArea.backgroundColor = .clear
        
        if apiManager.isExpired {
            scannedTextDisplayTextView.text = "REQUESTING AUTH"
            apiManager.requestAuthorization { (result) in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        self.scannedTextDisplayTextView.text = "Auth successful"
                    }
                case .error(let error):
                    DispatchQueue.main.async {
                        self.scannedTextDisplayTextView.text = "Auth Error: \(error)"
                    }
                }
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        videoPreviewLayer?.frame = view.bounds
        isDetectingIndicatorView.layer.cornerRadius = isDetectingIndicatorView.bounds.height / 2
        captureCurrentFrameButton.layer.cornerRadius = captureCurrentFrameButton.bounds.height / 2
    }
    
    //MARK: - Private Methods
    private func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            print("Capture Device not found")
            return
        }
        
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.focusMode = .continuousAutoFocus
            captureDevice.unlockForConfiguration()
        } catch let error {
            print("capture device config error: \(error)")
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            captureSession = AVCaptureSession()
            captureSession?.addInput(input)
            
            captureSession?.sessionPreset = .hd1920x1080
            
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds
            videoPreviewLayer?.connection?.videoOrientation = videoOrientation

            dataOutput = AVCaptureVideoDataOutput()
            dataOutput?.setSampleBufferDelegate(self, queue: dataOutputQueue)
            dataOutput?.alwaysDiscardsLateVideoFrames = true
            dataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]

            previewView.layer.addSublayer(videoPreviewLayer!)
            captureSession?.commitConfiguration()
            captureSession?.startRunning()
        } catch let error {
            print("ERROR: \(error)")
        }
    }
    
    private func toggleDataOuput(_ on: Bool) {
        guard let output = dataOutput else {
            return
        }
        if on {
            if captureSession?.canAddOutput(output) ?? false {
                captureSession?.addOutput(output)
            }
        } else {
            captureSession?.removeOutput(output)
        }
    }
    
    private func addDebugFrameToView(_ elementFrame: CGRect) {
        let view = UIView(frame: elementFrame)
        view.layer.borderColor = UIColor.red.cgColor
        view.layer.borderWidth = 2
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let elementFrameCenter = CGPoint(x: elementFrame.width/2, y: elementFrame.height/2)
        var overlappingFrameIndices = [Int]()
        for (i, debugFrame) in debugFrames.enumerated() {
            if debugFrame.bounds.contains(elementFrameCenter) {
                overlappingFrameIndices.append(i)
            }
        }
        
        overlappingFrameIndices.forEach { (i) in
            if debugFrames.count >= i {
                debugFrames[i].removeFromSuperview()
            }
        }
        DispatchQueue.main.async {
            self.overlayView.addSubview(view)
        }
        debugFrames.append(view)
    }

    private func clear() {
        for view in debugFrames {
            view.removeFromSuperview()
        }
        mtgTitleReader.reset()
        scannedTextDisplayTextView.text = ""
    }
    
    private func toggleScan() {
        toggleDataOuput(!outputIsOn)
        outputIsOn = !outputIsOn
    }
    
    //MARK: - IBActions
    @IBAction func detectButtonAction(_ sender: Any) {
        toggleScan()
    }
    
    @IBAction func clearDebugFrames(_ sender: UIButton) {
        clear()
    }
    
    private func parsePriceData(_ json: [String:Any]) -> ApiResult<Price> {
        guard let results = json["results"] as? [[String:Any]] else {
            return ApiResult.error(NSError(domain: "Invalid price data", code: 3, userInfo: nil))
        }
        var market: Double?
        var marketFoil: Double?
        
        if let priceInfo = results[safe: 0] {
            if priceInfo["subTypeName"] as? String == "Foil" {
                marketFoil = priceInfo["marketPrice"] as? Double
            } else if priceInfo["subTypeName"] as? String == "Normal" {
                market = priceInfo["marketPrice"] as? Double
            }
        }
        if let priceInfo = results[safe: 1] {
            if priceInfo["subTypeName"] as? String == "Foil" {
                marketFoil = priceInfo["marketPrice"] as? Double
            } else if priceInfo["subTypeName"] as? String == "Normal" {
                market = priceInfo["marketPrice"] as? Double
            }
        }
        
        return ApiResult.success(
            Price(
                market: market != nil ? String(market!) : "No info found for market price",
                marketFoil: marketFoil != nil ? String(marketFoil!) : "No info found for foil market price")
        )
    }
    
    private func showActionSheetPickerForNameOptions(_ sender: UIButton) {
        let sheet = UIAlertController(title: "Select correct name", message: nil, preferredStyle: .actionSheet)

        for title in mtgTitleReader.textProcessor.getTopXTitles(3) {
            let action = UIAlertAction(title: title, style: .default) {
                _ in
                self.processCardName(title)
            }
            sheet.addAction(action)
        }

        sheet.addAction(UIAlertAction(title: "cancel", style: .cancel, handler: nil))

        DispatchQueue.main.async {
            self.present(sheet, animated: true, completion: nil)
        }
    }
    
    private func processCardName(_ name: String) {
        DispatchQueue.global(qos: .utility).async {
            self.apiManager.getPriceForName(name, { (result) in
                switch result {
                case .success(let priceResult):
                    DispatchQueue.main.async {
                        let result = self.parsePriceData(priceResult)
                        switch result {
                        case .success(let price):
                            let priceMessage = "Price for \(name): \nMarket: \(price.market)\nFoil: \(price.marketFoil)"
                            self.scannedTextDisplayTextView.text = priceMessage
                        case .error(let error):
                            self.scannedTextDisplayTextView.text = "Error: \(error)"
                        }
                    }
                case .error(let error):
                    DispatchQueue.main.async {
                        self.scannedTextDisplayTextView.text = "Error: \(error)"
                    }
                }
            })
        }
    }
    
    
    @IBAction func captureCurrentFrameAction(_ sender: Any) {
        showActionSheetPickerForNameOptions(sender as! UIButton)
    }
    
    func getExifOrientation() -> UInt32 {
        
        var exifOrientation: CGImagePropertyOrientation!
        
        switch UIDevice.current.orientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        
        return exifOrientation.rawValue
    }
    
    func didDetectTitle(_ title: String) {
        toggleScan()
        processCardName(title)
    }
    
    func didDetectFrameForVisionElement(_ frame: CGRect) {
        DispatchQueue.main.async {
            self.addDebugFrameToView(frame)
        }
    }
  
}

//MARK: - Extensions
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        outputCounter += 1

        if outputCounter > captureSampleBufferRate {
            mtgTitleReader.processSampleBuffer(sampleBuffer) { (error) in
                self.scannedTextDisplayTextView.text = "error \(error)"
            }
            outputCounter = 0
        }
    }
}

extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeRight: return .landscapeRight
        case .landscapeLeft: return .landscapeLeft
        case .portrait: return .portrait
        default: return .landscapeRight
        }
    }
}
