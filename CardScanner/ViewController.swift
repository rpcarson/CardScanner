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

class ViewController: UIViewController {
    
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
    private var currentCMSampleBuffer: CMSampleBuffer?
    
    //MARK: - Private properties
    private var bufferImageForSizing: UIImage?
    private var outputIsOn = false {
        didSet {
            guard isDetectingIndicatorView != nil else { return }
            isDetectingIndicatorView.backgroundColor = outputIsOn ? .green : .yellow
        }
    }
    private var outputCounter = 0
    private var debugFrames = [UIView]()
    
    private var visionHandler: VisionHandler!
    
    var videoOrientation: AVCaptureVideoOrientation = .landscapeRight
    var visionOrientation: VisionDetectorImageOrientation = .rightTop
    
    var cardElements = [CardElement]()
    
    var possibleTitles = [String]()
    
    var detectedText = [String]() {
        didSet {
            var text = ""
            for _text in detectedText {
                text += "\(_text)\n\n"
            }
            scannedTextDisplayTextView.text = text
        }
    }
    
    struct CardElement {
        var text: String
        var frame: CGRect
    }
    
    private let dataOutputQueue = DispatchQueue(label: "com.carsonios.captureQueue")
    
    //MARK: - Orientation Properties
    override var shouldAutorotate: Bool {
        return true
    }

    //MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        visionHandler = VisionHandler()
        
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
            
            captureSession?.sessionPreset = AVCaptureSession.Preset.hd1920x1080
            
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
        DispatchQueue.main.async {
            self.overlayView.addSubview(view)
        }
        
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
        debugFrames.append(view)
    }
    
    private func processSampleBuffer(_ buffer: CMSampleBuffer) {
        visionHandler.processBuffer(buffer, withOrientation: visionOrientation, { (result) in
            switch result {
            case .success(let visionText):
                self.processVisionText(visionText)
            case .error(let error):
                print("Error processing sample buffer: \(error)")
            }
        })
    }
    
    private func processVisionText(_ visionText: [VisionText]) {
        for feature in visionText {
            if let block = feature as? VisionTextBlock {
                for line in block.lines {

                    let adjustedFrame = self.getAdjustedVisionElementFrame(line.frame)
                    if self.cardDetectionArea.frame.contains(adjustedFrame.origin) {
                        let cardElement = CardElement(text: line.text, frame: line.frame)
                        self.detectedText.append(line.text)
                        self.cardElements.append(cardElement)
                        self.addDebugFrameToView(adjustedFrame)
                        print("line \(line.text)")
                    }
                }
            }
        }
    }
    
    private func handleVisionTextResults(_ visionText: [VisionText]) {
        for feature in visionText {
            let value = feature.text
            if let block = feature as? VisionTextBlock {
                for line in block.lines {
                    let adjustedFrame = self.getAdjustedVisionElementFrame(line.frame)
                    if self.cardDetectionArea.frame.contains(adjustedFrame.origin) {
                        let cardElement = CardElement(text: line.text, frame: line.frame)
                        self.detectedText.append(line.text)
                        self.cardElements.append(cardElement)
                        self.addDebugFrameToView(line.frame)
                        
                        let frequencyFilteredText = self.getMostFrequentTextResultForLines(self.detectedText, withMinimumFrequency: 5)
                        
                        let possibleTitles = self.getUpperLeftTextFromElements(cardElements)
                        
                        print("line \(line.text)")
                    }
                }
            }
        }
    }
    
    private func clear() {
        for view in debugFrames {
            view.removeFromSuperview()
        }
        detectedText = []
    }
    
    //MARK: - Utility methods
    private func getAdjustedVisionElementFrame(_ elementFrame: CGRect) -> CGRect {
        let screen = UIScreen.main.bounds
        var frame = elementFrame
        if let image = self.bufferImageForSizing {
            let xRatio = screen.width / image.size.width
            let yRatio = screen.height / image.size.height
            frame = CGRect(x: frame.minX * xRatio, y: frame.minY * yRatio, width: frame.width * xRatio, height: frame.height * yRatio)
        }
        return frame
    }
    
    private func getImageFromBuffer(_ buffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            print("Could not create pixel buffer")
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return UIImage(ciImage: ciImage)
    }
    
    //MARK: - IBActions
    @IBAction func detectButtonAction(_ sender: Any) {
        toggleDataOuput(!outputIsOn)
        outputIsOn = !outputIsOn
    }
    
    @IBAction func clearDebugFrames(_ sender: UIButton) {
        clear()
    }
    
    @IBAction func captureCurrentFrameAction(_ sender: Any) {
        
        toggleDataOuput(false)
        clear()
        
        guard let buffer = currentCMSampleBuffer else {
            self.scannedTextDisplayTextView.text = "no current sample buffer"
            print("no current sample buffer")
            return
        }
        
        visionHandler.processBuffer(buffer, withOrientation: visionOrientation) { (result) in
            switch result {
            case .success(let visionText):
                self.handleVisionTextResults(visionText)
            case .error(let error):
                self.scannedTextDisplayTextView.text = "Error processing sample buffer: \(error)"
                print("Error processing sample buffer: \(error)")
            }
        }
    }
    
    //MARK: - Sorting
    
    func getUpperLeftTextFromElements(_ cardElements: [CardElement]) -> String? {
        let sortedElements = cardElements.sorted {
            return ($0.frame.origin.y < $1.frame.origin.y) && ($0.frame.origin.x < $1.frame.origin.x)
        }
        
        var text: String?
        
        if sortedElements.count > 0 {
            text = sortedElements[0].text
        }
        
        return text
    }
    
    ///for minimum frequency, probably should use a relative appearence rate rather than hard amount of appearances
    private func getMostFrequentTextResultForLines(_ textLines: [String], withMinimumFrequency minFrequency: Int = 2) -> (text: String, frequency: Int) {
        var mostOccuringTexts = [String:Int]()
        
        for text in textLines {
            let currentValue = mostOccuringTexts[text] ?? 0
            mostOccuringTexts[text] = (currentValue + 1)
        }
        
        var textsWithMinimumFrequency = mostOccuringTexts.filter {$0.value > minFrequency}
        
        for (text, val) in mostOccuringTexts {
            if val > 3 {
                //  print("Text: \(text) ; Occurences: \(val)")
            }
        }
        
        let sortedByFrequency = textsWithMinimumFrequency.sorted {$0.value > $1.value}
        let mostFrequentText = sortedByFrequency[0].key
        let frequency = sortedByFrequency[0].value
        print("most frequent text: \(mostFrequentText) - occuring \(frequency) times")
        return (mostFrequentText, frequency)
    }
    
    private func getTopResultsForLines(_ textLines: [String], resultsLimit limit: Int, withMinimumFrequency minFrequency: Int = 2) -> [String] {
        var mostOccuringTexts = [String:Int]()
        
        for text in textLines {
            let currentValue = mostOccuringTexts[text] ?? 0
            mostOccuringTexts[text] = (currentValue + 1)
        }
        
        var textsWithMinimumFrequency = mostOccuringTexts.filter {$0.value > minFrequency}
        
        var topResults: [(String, Int)] {
            var results = [(String, Int)]()
            for (element, frequency) in textsWithMinimumFrequency {
                results.append((element, frequency))
            }
            return results
        }
        
        let resultsSortedByFrequency = topResults.sorted{$0.1 > $1.1}
        let topResultsWithLimit = Array(resultsSortedByFrequency.prefix(limit))
        return topResultsWithLimit.map{ $0.0 }
    }
}

//MARK: - Extensions
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if bufferImageForSizing == nil {
            bufferImageForSizing = getImageFromBuffer(sampleBuffer)
        }
        
        outputCounter += 1
        if outputCounter > 30 {
            currentCMSampleBuffer = sampleBuffer
            processSampleBuffer(sampleBuffer)
            outputCounter = 0
        }
    }
}

extension UIInterfaceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeRight: return .landscapeRight
        case .landscapeLeft: return .landscapeLeft
        case .portrait: return .portrait
        default: return nil
        }
    }
}
