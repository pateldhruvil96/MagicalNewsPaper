//
//  ViewController.swift
//  MagicalNewsPaper
//
//  Created by Dhruvil Patel on 03/03/21.
//  Copyright © 2020 Dhruvil Patel. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import SwiftyJSON


class ViewController: UIViewController, ARSCNViewDelegate{
    
    @IBOutlet weak var saveSnapshotButtonOutlet: UIButton!
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var tempImageView: UIImageView!
    var videonodee=SKVideoNode()
    
    var identifier = 0
    let configuration = ARWorldTrackingConfiguration()
    var customReferenceImages = [ARReferenceImage]()
    let augmentedRealitySession = ARSession()
    
    var request = VNRecognizeTextRequest(completionHandler: nil)
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupARSession()
    }
    func setupARSession(){
        // clearAllFile()
        
        loadCustomImages()
        
        saveSnapshotButtonOutlet.layer.cornerRadius = 10
        
        sceneView.session = augmentedRealitySession
        configuration.planeDetection = []
        
        configuration.maximumNumberOfTrackedImages = 2
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        sceneView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    @IBAction func saveScreenShot(_ sender: Any) {
        LoadingOverlay.shared.showOverlay(view: self.view)
        //1. Create A Snapshot Of The ARView
        let screenShot = self.sceneView.snapshot()
        
        //2. Convert It To A PNG
        guard let imageData = screenShot.pngData() else { return }
        
        //3. Store The File In The Documents Directory
        let fileURL = getDocumentsDirectory().appendingPathComponent("custom\(identifier).png")
        
        //4. Write It To The Documents Directory & Increase The Identifier
        do {
            try imageData.write(to: fileURL)
            identifier += 1
        } catch  {
            print("Error Saving File")
        }
        
        //5. Load The Custom Images
        loadCustomImages()
    }
    
    func getDirectoryPath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]; return documentsDirectory
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) { //this function will continuosly gets called everytime
        
        if let imageAnchor = anchor as? ARImageAnchor{
            if (imageAnchor.isTracked) {
                DispatchQueue.main.async{
                    self.saveSnapshotButtonOutlet.isHidden = true
                }
            }else {
                DispatchQueue.main.async{
                    self.saveSnapshotButtonOutlet.isHidden = false
                }
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        //1. If Out Target Image Has Been Detected Than Get The Corresponding Anchor
        guard let currentImageAnchor = anchor as? ARImageAnchor else { return }
        
        //2. Get The Targets Name
        let name = currentImageAnchor.referenceImage.name!
        
        //3. Get The Targets Width & Height
        let width = currentImageAnchor.referenceImage.physicalSize.width
        let height = currentImageAnchor.referenceImage.physicalSize.height
        print("""
                   Image Name = \(name)
                   Image Width = \(width)
                   Image Height = \(height)
                   """)
        let fileManager = FileManager.default
        let imagePAth = (self.getDirectoryPath() as NSString).appendingPathComponent(name)
        if fileManager.fileExists(atPath: imagePAth){
            let planeGeometry = SCNPlane(width: width, height: height)
            let loader = LoadingOverlay()
            DispatchQueue.main.async {
                loader.showOverlay(view: self.view)
            }
            // Do video searching work here //
            setupVisionTextRecognizeImage(image: UIImage(contentsOfFile: imagePAth)) { (id) in
                
                let webView = UIWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 900))
                webView.allowsInlineMediaPlayback = true
                let request = URLRequest(url: URL(string: "https://www.youtube.com/embed/\(id)?playsinline=0")!)
                webView.loadRequest(request)
                planeGeometry.firstMaterial?.diffuse.contents = webView
                
                
                let planeNodes = SCNNode(geometry: planeGeometry)
                
                planeNodes.geometry = planeGeometry
                
                
                planeNodes.eulerAngles.x = -.pi/2
                planeNodes.position.y = 0.01
                node.addChildNode(planeNodes)
                
                DispatchQueue.main.async {
                    loader.hideOverlayView()
                    self.saveSnapshotButtonOutlet.isHidden = true
                }
            }
        }else{
            print("No Image")
            let planeGeometry = SCNPlane(width: width, height: height)
            planeGeometry.firstMaterial?.diffuse.contents = UIColor.white
            let planeNodes = SCNNode(geometry: planeGeometry)
            planeNodes.opacity = 0.9
            planeNodes.geometry = planeGeometry
            
            //6. Rotate The PlaneNode To Horizontal
            planeNodes.eulerAngles.x = -.pi/2
            node.addChildNode(planeNodes)
        }
        
        
        
    }
}
extension ViewController{
    func setupVisionTextRecognizeImage(image:UIImage?, completion: @escaping (String) -> ()){
        var textString = ""
        request = VNRecognizeTextRequest(completionHandler: { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else{fatalError("Received invalid observation")}
            
            for observation in observations{
                guard let topCandidate = observation.topCandidates(1).first else{
                    print("No candidate")
                    continue
                }
                textString += topCandidate.string
                break
            }
            print("TEXT RECOGNIZED IS : " + textString)
            let searchQuery = textString
            let baseURL = Constants.BASEURL
            var requestURL = URLComponents(string: baseURL)
            let queryItems = [URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "q", value: searchQuery), URLQueryItem(name: "key", value: Constants.API_KEY)]
            requestURL?.queryItems = queryItems
            guard let url = requestURL?.url else{return}
            print(url)
            ServerRequest.postcall(url: url, httpMethod: .get, params: nil) { (response, error) in
                if let dict = response, dict.count > 0{
                    let json = JSON(dict)
                    let totalItems = json["items"].count
                    var count = 0
                    while totalItems > count {
                        if let id = json["items"][count]["id"]["videoId"].string{
                            print(id)
                            completion(id)
                            return
                        }
                        count += 1
                    }
                    if(count == totalItems){
                        print("NO YOUTUBE ID FOUND")
                    }
                    count = 0
                }
            }
            
        })
        //        request.customWords = ["custOm"]
        request.minimumTextHeight = 0.03125
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en_US"]
        request.usesLanguageCorrection = true
        
        let requests = [request]
        DispatchQueue.global(qos: .userInitiated).async {
            guard let img = image?.cgImage else{fatalError("Missing image to scan")}
            let handle = VNImageRequestHandler(cgImage: img, options: [:])
            try? handle.perform(requests)
        }
        
    }
    func loadCustomImages(){
        //1. Get Reference To The NSFileManager
        let fileManager = FileManager.default
        
        //2. Get The URL Of The Documents Directory
        let documentsDirectory = getDocumentsDirectory()
        
        do {
            
            //a. Get All Files In The Documents Directory
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            //b. Loop Through Them And If The Path Contains Our Custom Prefix Then Convert To CGImage & Then ARReference Image
            for file in fileURLs{
                
                if file.lastPathComponent.hasPrefix("custom"){
                    
                    if let arImage = UIImage(contentsOfFile: file.path), let arCGImage = arImage.cgImage{
                        
                        /* Here You Will Need To Work Out The Pysical Widht Of The Image In Metres */
                        
                        let widthInCM: CGFloat = CGFloat(arCGImage.width) / CGFloat(47)
                        let widthInMetres: CGFloat = widthInCM * 0.01
                        
                        let arReferenceImage = ARReferenceImage(arCGImage,
                                                                orientation: cgImagePropertyOrientation(arImage.imageOrientation),
                                                                physicalWidth: widthInMetres)
                        
                        arReferenceImage.name = file.lastPathComponent
                        
                        customReferenceImages.append(arReferenceImage)
                    }
                }
            }
            
        } catch {
            
            print("Error Listing Files \(documentsDirectory.path): \(error.localizedDescription)")
        }
        
        
        //3. Set Our ARSession Configuration Detection Images
        configuration.detectionImages = Set(customReferenceImages)
        augmentedRealitySession.run(configuration, options:  [.resetTracking, .removeExistingAnchors ])
        
        
    }
    func getDocumentsDirectory() -> URL {
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
        
    }
    func cgImagePropertyOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        case .left:
            return .left
        }
    }
    func clearAllFile() {
        let fileManager = FileManager.default
        
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        
        print("Directory: \(paths)")
        
        do
            {
                let fileName = try fileManager.contentsOfDirectory(atPath: paths)
                
                for file in fileName {
                    // For each file in the directory, create full path and delete the file
                    let filePath = URL(fileURLWithPath: paths).appendingPathComponent(file).absoluteURL
                    try fileManager.removeItem(at: filePath)
                }
            }catch let error {
                print(error.localizedDescription)
            }
    }
}
public class LoadingOverlay
{
    var overlayView: UIView!
    var activityIndiacator: UIActivityIndicatorView!
    var mainView: UIView!
    class var shared: LoadingOverlay {
        struct Static {
            static let instance : LoadingOverlay = LoadingOverlay()
        }
        return Static.instance
    }
    init() {
        DispatchQueue.main.async {
            self.overlayView = UIView()
            self.mainView = UIView()
            self.mainView.frame = UIScreen.main.bounds
            self.activityIndiacator = UIActivityIndicatorView()
            self.overlayView.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
            self.overlayView.backgroundColor = UIColor(white: 0, alpha: 0.7)
            self.overlayView.clipsToBounds = true
            self.overlayView.layer.cornerRadius = 10
            self.overlayView.layer.zPosition = 1
            self.activityIndiacator.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
            self.activityIndiacator.center = CGPoint(x: self.overlayView.bounds.width / 2, y: self.overlayView.bounds.height / 2)
            self.activityIndiacator.style = .large
            self.activityIndiacator.color = .white
            self.overlayView.addSubview(self.activityIndiacator)
            self.mainView.addSubview(self.overlayView)
        }
    }
    public func showOverlay(view: UIView) {
        DispatchQueue.main.async {
            self.overlayView.center = view.center
            self.mainView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            view.addSubview(self.mainView)
            self.activityIndiacator.startAnimating()
        }
    }
    public func hideOverlayView() {
        DispatchQueue.main.async {
            self.activityIndiacator.stopAnimating()
            self.overlayView.removeFromSuperview()
            self.mainView.removeFromSuperview()
        }
    }
}
