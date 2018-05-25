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

class TextProcessor {
    
    func getMostFrequentTextResultForLines(_ textLines: [String], withMinimumFrequency minFrequency: Int = 2) -> (text: String, frequency: Int)? {
        var mostOccuringTexts = [String:Int]()
        
        for text in textLines {
            let currentValue = mostOccuringTexts[text] ?? 0
            mostOccuringTexts[text] = (currentValue + 1)
        }
        
        let textsWithMinimumFrequency = mostOccuringTexts.filter {$0.value > minFrequency}
        
        let sortedByFrequency = textsWithMinimumFrequency.sorted {$0.value > $1.value}
        guard let mostFrequentText = sortedByFrequency[safe: 0]?.key, let frequency = sortedByFrequency[safe: 0]?.value else {
            return nil
        }
        
        print("most frequent text: \(mostFrequentText) - occuring \(frequency) times")
        return (mostFrequentText, frequency)
    }
    
    func getTopResultsForLines(_ textLines: [String], resultsLimit limit: Int, withMinimumFrequency minFrequency: Int = 2) -> [String] {
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
    
    var captureSampleBufferRate = 2
    
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
    
    let textProcessor = TextProcessor()
    
    var videoOrientation: AVCaptureVideoOrientation = .landscapeRight
    var visionOrientation: VisionDetectorImageOrientation = .rightTop
    
    var cardElements = [CardElement]()
    
    var possibleTitles = [String]()
    
    var frequencyFilteredText = [String]()
    
    var detectedText = [String]()
    
    struct CardElement {
        var text: String
        var frame: CGRect
    }
    
    private let dataOutputQueue = DispatchQueue(label: "com.carsonios.captureQueue")
    
    let apiManager = ApiManager()
    
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
    
    private func processSampleBuffer(_ buffer: CMSampleBuffer) {
        visionHandler.processBuffer(buffer, withOrientation: visionOrientation, { (result) in
            switch result {
            case .success(let visionText):
                self.handleVisionTextResults(visionText)
            case .error(let error):
                print("Error processing sample buffer: \(error)")
                self.scannedTextDisplayTextView.text = "\n\n Error processing sample buffer: \(error)"
            }
        })
    }

    func sortCardElements(_ elements: [CardElement]) {
        if let upperLeftElements = self.getUpperLeftElements(elements) {
            let upperLeftElementText = upperLeftElements.map{$0.text}
            frequencyFilteredText = textProcessor.getTopResultsForLines(upperLeftElementText, resultsLimit: 10, withMinimumFrequency: 3)
            var displayText = ""
            frequencyFilteredText.forEach{displayText += "\($0)\n\n"}
            self.scannedTextDisplayTextView.text = displayText
        }
    }
    
    func handleVisionTextResults(_ visionText: [VisionText]) {
        for feature in visionText {
            if let block = feature as? VisionTextBlock {
                for line in block.lines {
                    let adjustedFrame = self.getAdjustedVisionElementFrame(line.frame)
                    if self.cardDetectionArea.frame.contains(adjustedFrame.origin) {
                        self.addDebugFrameToView(adjustedFrame)
                        let cardElement = CardElement(text: line.text, frame: line.frame)
                        self.detectedText.append(line.text)
                        self.cardElements.append(cardElement)
                        self.sortCardElements(self.cardElements)
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
        frequencyFilteredText = []
        cardElements = []
        scannedTextDisplayTextView.text = ""
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
    
    private func parsePriceData(_ json: [String:Any]) -> ApiResult<Price> {
        guard let results = json["results"] as? [[String:Any]] else {
            return ApiResult.error(NSError(domain: "Invalid price data", code: 3, userInfo: nil))
        }
        var market: Double?
        var marketFoil: Double?
        
        if let marketPriceInfo = results[safe: 0] {
            market = marketPriceInfo["marketPrice"] as? Double
        }
        
        if let marketFoilPriceInfo = results[safe: 1] {
            marketFoil = marketFoilPriceInfo["marketPrice"] as? Double
        }
        
        return ApiResult.success(
            Price(
                market: market != nil ? String(market!) : "No info found for market price",
                marketFoil: marketFoil != nil ? String(marketFoil!) : "No info found for foil market price")
        )
    }
    
    private var selectedNameResult = ""
    
    func showActionSheetPickerForNameOptions(_ sender: UIButton) {
        let sheet = UIAlertController(title: "Select correct name", message: nil, preferredStyle: .actionSheet)
        
        if let firstOption = frequencyFilteredText[safe: 0] {
            let action = UIAlertAction(title: firstOption, style: .default) {
                _ in
                self.processCardName(firstOption)
            }
            sheet.addAction(action)
        }
        if let secondOption = frequencyFilteredText[safe: 1] {
            let action = UIAlertAction(title: secondOption, style: .default) {
                _ in
                self.processCardName(secondOption)
            }
            sheet.addAction(action)
        }
        if let thirdOption = frequencyFilteredText[safe: 2] {
            let action = UIAlertAction(title: thirdOption, style: .default) {
                _ in
                self.processCardName(thirdOption)
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
    
    //MARK: - Sorting
    ///needs to be able to return of array of matches for upper left.
    ///what defines upper left? can i look for origin within top left box?
    func getUpperLeftElements(_ cardElements: [CardElement]) -> [CardElement]? {
        let sortedElements = cardElements.sorted {
            return ($0.frame.origin.y < $1.frame.origin.y) && ($0.frame.origin.x < $1.frame.origin.x)
        }
        
        guard let topLeftMostElement = sortedElements[safe: 0] else {
            return nil
        }
        
        let topLeftElements = sortedElements.filter {topLeftMostElement.frame.intersects($0.frame)}
        return topLeftElements + [topLeftMostElement]
    }
}

//MARK: - Extensions
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if bufferImageForSizing == nil {
            bufferImageForSizing = getImageFromBuffer(sampleBuffer)
        }
        
        outputCounter += 1
        if outputCounter > captureSampleBufferRate {
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
