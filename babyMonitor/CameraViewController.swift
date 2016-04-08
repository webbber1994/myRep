//
//  CameraViewController.swift
//  BabyMonitor
//
//  Created by dede on 4/3/16.
//  Copyright © 2016 dede. All rights reserved.
//


import UIKit
import AVFoundation
import CocoaAsyncSocket


class CameraViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate {

    @IBOutlet weak var cameraBtn: UIButton!
    @IBOutlet var cameraView: UIView!
    var session:AVCaptureSession?
    var sessionQueue: dispatch_queue_t?
    var videoDataOutputQueue: dispatch_queue_t?
    var videoDeviceInput:AVCaptureDeviceInput?
    var setupResult: AVCamSetupResult?
    var udpSocket:GCDAsyncUdpSocket?
    var listenSocket:GCDAsyncSocket?
    var socketQueue: dispatch_queue_t?
    var connectedSockets:NSMutableArray = []
    var isRunning: Bool = false
    var cnt: Int = 0
    var previewLayer:AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        do{
            UIApplication.sharedApplication().idleTimerDisabled = true
            self.udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: dispatch_get_main_queue())
            self.socketQueue = dispatch_queue_create("socketQueue",DISPATCH_QUEUE_SERIAL)
            self.listenSocket = GCDAsyncSocket(delegate: self, delegateQueue: self.socketQueue)
            try self.listenSocket?.acceptOnPort(8080)
            self.connectedSockets = NSMutableArray()
            try self.udpSocket?.bindToPort(8081)
            try self.udpSocket?.beginReceiving()
            // setup for camera
            self.session = AVCaptureSession()
            self.session?.sessionPreset = AVCaptureSessionPresetMedium
            self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
            switch AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo) {

            case AVAuthorizationStatus.Authorized:
                self.setupResult = AVCamSetupResult.Success
                break
            case AVAuthorizationStatus.NotDetermined:
                dispatch_suspend(self.sessionQueue!)
                AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: {(granted: Bool) -> Void in
                    if !granted {
                        self.setupResult = AVCamSetupResult.CameraNotAuthorized
                    }
                    dispatch_resume(self.sessionQueue!)
                })
            default:
                self.setupResult = AVCamSetupResult.CameraNotAuthorized

            }

            previewLayer = AVCaptureVideoPreviewLayer(session:self.session)
            // Full Screen for PreviewLayer
            let bounds: CGRect = self.cameraView.bounds
            previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
            previewLayer?.bounds = bounds
            previewLayer?.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
            self.cameraView.layer.addSublayer(previewLayer!)
            dispatch_async((self.sessionQueue)!) {
                do{
                    if self.setupResult !=  AVCamSetupResult.Success {
                        return
                    }

                    // Change this value
                    let videoDevice: AVCaptureDevice = CameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: .Back)
                    // Get the active capture device
                    try videoDevice.lockForConfiguration()
                    videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, 2)
                    videoDevice.activeVideoMaxFrameDuration = CMTimeMake(1, 2)
                    videoDevice.unlockForConfiguration()

                    let videoDeviceInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: videoDevice) as AVCaptureDeviceInput

                    self.session?.beginConfiguration()

                    if self.session!.canAddInput(videoDeviceInput) {
                        self.session!.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput

                    }
                    else {
                        NSLog("Could not add video device input to the session")
                        self.setupResult = AVCamSetupResult.SessionConfigurationFailed
                    }

                    self.videoDataOutputQueue = dispatch_queue_create("videoDataOutputQueue", DISPATCH_QUEUE_SERIAL)
                    let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
                    videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_32BGRA)]
                    videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
                    if self.session!.canAddOutput(videoDataOutput) {
                        self.session!.addOutput(videoDataOutput)
                        let connection: AVCaptureConnection = videoDataOutput.connectionWithMediaType(AVMediaTypeVideo)
                        if connection.supportsVideoStabilization {
                            connection.preferredVideoStabilizationMode = .Auto
                        }
                    }
                    else {
                        self.setupResult = AVCamSetupResult.SessionConfigurationFailed
                    }
                    self.session!.commitConfiguration()
                    self.session!.startRunning()

                }catch{
                    NSLog("ERROR back thread")
                }
            }
        }catch{
            NSLog("ERROR viewDidLoad")
        }
    }

    class func deviceWithMediaType(mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType)
        var captureDevice: AVCaptureDevice = devices.first as! AVCaptureDevice

        for device in devices{
            let device = device as! AVCaptureDevice
            if device.position == position {
                captureDevice = device
                break
            }
        }
        return captureDevice
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // Return IP address of WiFi interface (en0) as a String, or `nil`
    func getWiFiAddress() -> String? {
        var address : String?

        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs> = nil
        if getifaddrs(&ifaddr) == 0 {

            // For each interface ...
            for (var ptr = ifaddr; ptr != nil; ptr = ptr.memory.ifa_next) {
                let interface = ptr.memory

                // Check for IPv4 or IPv6 interface:
                let addrFamily = interface.ifa_addr.memory.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

                    // Check interface name:
                    if let name = String.fromCString(interface.ifa_name) where name == "en0" {

                        // Convert interface address to a human readable string:
                        var addr = interface.ifa_addr.memory
                        var hostname = [CChar](count: Int(NI_MAXHOST), repeatedValue: 0)
                        getnameinfo(&addr, socklen_t(interface.ifa_addr.memory.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String.fromCString(hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    func imageToBuffer(sampleBuffer: CMSampleBufferRef) -> NSData {
        let imageBuffer: CVImageBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer)!

        // ベースアドレスをロック
        CVPixelBufferLockBaseAddress(imageBuffer, 0)

        // 画像データの情報を取得
        let baseAddress: UnsafeMutablePointer<Void> = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)

        let bytesPerRow: Int = CVPixelBufferGetBytesPerRow(imageBuffer)
        let height: Int = CVPixelBufferGetWidth(imageBuffer)
        let width: Int = CVPixelBufferGetHeight(imageBuffer)

        // RGB色空間を作成
        let colorSpace: CGColorSpaceRef = CGColorSpaceCreateDeviceRGB()!

        // Bitmap graphic contextを作成
        let bitsPerCompornent: Int = 8
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.ByteOrder32Little.rawValue | CGImageAlphaInfo.PremultipliedFirst.rawValue) as UInt32)
        let newContext: CGContextRef = CGBitmapContextCreate(baseAddress, width, height, bitsPerCompornent, bytesPerRow, colorSpace, bitmapInfo.rawValue)! as CGContextRef

        // Quartz imageを作成
        let imageRef: CGImageRef = CGBitmapContextCreateImage(newContext)!

        // UIImageを作成
        let resultImage: UIImage = UIImage(CGImage: imageRef)
        let resData: NSData = UIImageJPEGRepresentation(resultImage, 0)!
        return resData
    }

    func udpSocket(sock: GCDAsyncUdpSocket, didReceiveData data: NSData, fromAddress address: NSData, withFilterContext filterContext: AnyObject) {
        let msg: String = self.getWiFiAddress()!
        let data2: NSData = msg.dataUsingEncoding(NSUTF8StringEncoding)!
        self.udpSocket!.sendData(data2, toAddress: address, withTimeout: -1, tag: 0)
    }

    func captureOutput(captureOutput: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, fromConnection connection: AVCaptureConnection) {
        if !self.isRunning {
            return
        }
        cnt = cnt + 1
        if self.cnt % 3 == 0 {
            let rawData = self.imageToBuffer(sampleBuffer)
            //var dataImg: NSMutableData = NSMutableData.init(data: self.imageToBuffer(sampleBuffer))
            var len: Int = rawData.length
            let dataLen: NSData = NSData(bytes: &len, length: 8)
            //let temp: NSData = NSData(bytes: &dataLen, length: 8)
            sync(self.connectedSockets){
                for sockTmp in self.connectedSockets{
                    let socketConn:GCDAsyncSocket = sockTmp as! GCDAsyncSocket
                    dispatch_async(self.socketQueue!){
                        socketConn.writeData(dataLen, withTimeout: -1, tag: Const.LEN_MSG)
                        socketConn.writeData(rawData, withTimeout: -1, tag: Const.IMG_MSG)
                    }
                }
            }
        }
    }

    func socket(sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        sync(self.connectedSockets){
            self.connectedSockets.addObject(newSocket)
            NSLog("socket accepted %@: %hu", newSocket.connectedHost, newSocket.connectedPort)
        }
        self.isRunning = true
    }

    func socket(sock: GCDAsyncSocket, shouldTimeoutReadWithTag tag: Int, elapsed: NSTimeInterval, bytesDone length: UInt) -> NSTimeInterval {
        if elapsed <= Const.READ_TIMEOUT {
            let warningMsg: String = "Are you still there?\r\n"
            let warningData: NSData = warningMsg.dataUsingEncoding(NSUTF8StringEncoding)!
            sock.writeData(warningData, withTimeout: -1, tag: Const.WARNING_MSG)
            return Const.READ_TIMEOUT_EXTENSION
        }
        return 0.0
    }
    
    func socketDidDisconnect(sock: GCDAsyncSocket, withError err: NSError) {
        if sock != self.listenSocket {
            sync(self.connectedSockets){
                self.connectedSockets.removeObject(sock)
            }
        }
    }
    
    func sync(lock: AnyObject, proc: () -> ()) {
        objc_sync_enter(lock)
        proc()
        objc_sync_exit(lock)
    }
    
}