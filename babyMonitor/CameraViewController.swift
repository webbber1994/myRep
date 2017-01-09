import UIKit
import AVFoundation
import CocoaAsyncSocket


class CameraViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate {

    @IBOutlet weak var passcodeLabel: UILabel!
    @IBOutlet weak var cameraView: UIView!
    var session:AVCaptureSession?
    var sessionQueue: DispatchQueue?
    var recordingQueue: DispatchQueue?
    var setupResult: AVCamSetupResult?
    var udpSocket:GCDAsyncUdpSocket?
    var listenSocket:GCDAsyncSocket?
    var udpSocketQueue: DispatchQueue?
    var socketQueue: DispatchQueue?
    var connectedSockets:NSMutableArray = []
    var isRunning: Bool = false
    var cnt: Int = 0
    var previewLayer:AVCaptureVideoPreviewLayer?

    override func willMove(toParentViewController parent: UIViewController?) {
        super.willMove(toParentViewController: parent)
        if parent == nil {
            self.udpSocket?.close()
            self.listenSocket?.disconnect()
            sync(self.connectedSockets){
                for sockTmp in self.connectedSockets{
                    let socketConn:GCDAsyncSocket = sockTmp as! GCDAsyncSocket
                    self.socketQueue!.async{
                        socketConn.disconnect()
                    }
                }
            }
            connectedSockets.removeAllObjects()
            isRunning = false;
            cnt = 0;
        }

    }


    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds: CGRect = self.cameraView.bounds
        previewLayer?.frame = self.cameraView.bounds
        previewLayer?.videoGravity = AVLayerVideoGravityResizeAspect
        previewLayer?.bounds = self.cameraView.bounds
        previewLayer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }


    override func viewDidLoad() {
        super.viewDidLoad()
        do{
            UIApplication.shared.isIdleTimerDisabled = true
            self.udpSocketQueue = DispatchQueue(label: "uppSocketQueue",attributes: [])
            self.udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: self.udpSocketQueue)
            self.socketQueue = DispatchQueue(label: "socketQueue",attributes: [])
            self.listenSocket = GCDAsyncSocket(delegate: self, delegateQueue: self.socketQueue)
            try self.listenSocket?.accept(onPort: 8080)
            self.connectedSockets = NSMutableArray()
            try self.udpSocket?.bind(toPort: 8081)
            try self.udpSocket?.enableBroadcast(true)
            try self.udpSocket?.beginReceiving()
            // setup for camera
            self.session = AVCaptureSession()
            self.session?.sessionPreset = AVCaptureSessionPresetMedium
            self.sessionQueue = DispatchQueue(label: "session queue", attributes: [])

            switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
            case AVAuthorizationStatus.authorized:
                self.setupResult = AVCamSetupResult.success
                break
            case AVAuthorizationStatus.notDetermined:
                self.sessionQueue!.suspend()
                AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: {(granted: Bool) -> Void in
                    if !granted {
                        self.setupResult = AVCamSetupResult.cameraNotAuthorized
                    }else{
                        self.setupResult = AVCamSetupResult.success
                    }
                    self.sessionQueue!.resume()

                })
            default:
                self.setupResult = AVCamSetupResult.cameraNotAuthorized

            }

            previewLayer = AVCaptureVideoPreviewLayer(session:self.session)
            // Full Screen for PreviewLayer
            let bounds: CGRect = self.cameraView.bounds
            previewLayer?.frame = self.cameraView.bounds
            previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
            previewLayer?.bounds = bounds
            previewLayer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

            self.cameraView.layer.addSublayer(previewLayer!)
            (self.sessionQueue)!.async {
                do{
                    if self.setupResult !=  AVCamSetupResult.success {
                        DispatchQueue.main.async {
                            //UIAlertView
                            let alert:UIAlertController = UIAlertController(title:"エラー",
                                                                            message: "カメラにアクセスできません。",
                                                                            preferredStyle: UIAlertControllerStyle.alert)
                            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        }
                        return
                    }

                    // Change this value
                    let videoDevice: AVCaptureDevice = AVCaptureDevice.defaultDevice(withMediaType:AVMediaTypeVideo)

                    let videoDeviceInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: videoDevice) as AVCaptureDeviceInput

                    self.session?.beginConfiguration()

                    self.session!.addInput(videoDeviceInput)

                    self.recordingQueue = DispatchQueue(label: "recordingQueue", attributes: [])
                    let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
                    videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable : Int(kCVPixelFormatType_32BGRA)]
                    videoDataOutput.setSampleBufferDelegate(self, queue: self.recordingQueue)
                    self.session!.addOutput(videoDataOutput)
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



    // Return IP address of WiFi interface (en0) as a String, or `nil`
    func getWiFiAddress() -> String? {
        var address : String?

        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {

                // Check interface name:
                let name = String(cString: interface.ifa_name)
                if  name == "en0" {

                    // Convert interface address to a human readable string:
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        
        return address
    }

    func imageToBuffer(_ sampleBuffer: CMSampleBuffer) -> Data {
        let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!

        // ベースアドレスをロック
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

        // 画像データの情報を取得
        let baseAddress: UnsafeMutableRawPointer = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)!

        let bytesPerRow: Int = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width: Int = CVPixelBufferGetWidth(imageBuffer)
        let height: Int = CVPixelBufferGetHeight(imageBuffer)

        // RGB色空間を作成
        let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()

        // Bitmap graphic contextを作成
        let bitsPerCompornent: Int = 8
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) as UInt32)
        let newContext: CGContext = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: bitsPerCompornent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)! as CGContext

        // Quartz imageを作成
        let imageRef: CGImage = newContext.makeImage()!

        // UIImageを作成
        let resultImage: UIImage = UIImage(cgImage: imageRef, scale:1.0 ,orientation:UIImageOrientation.right)
        let resData: Data = UIImageJPEGRepresentation(resultImage, 0)!
        return resData
    }

    func convertArr<T>(count: Int, data: UnsafePointer<T>) -> [T] {

        let buffer = UnsafeBufferPointer(start: data, count: count)
        return Array(buffer)
    }


    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any) {
        let msg: String = self.getWiFiAddress()!
        let data2: Data = msg.data(using: String.Encoding.utf8)!
        self.udpSocket!.send(data2, toAddress: address, withTimeout: -1, tag: 0)
    }

    func captureOutput(_ captureOutput: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !self.isRunning {
            return
        }
        cnt = cnt + 1
        if (self.cnt % 3 == 0) {
            let rawData = self.imageToBuffer(sampleBuffer)
            var len: Int = rawData.count
            var video: NSInteger = 1
            let videoData = NSData(bytes: &video, length: 2)

            let dataLen: NSData = NSData(bytes:&len, length: 8)
            sync(self.connectedSockets){
                for sockTmp in self.connectedSockets{
                    let socketConn:GCDAsyncSocket = sockTmp as! GCDAsyncSocket
                    self.socketQueue!.async{
                        socketConn.write(videoData as Data!, withTimeout: -1, tag: Const.IMG_TYP)
                        socketConn.write(dataLen as Data!, withTimeout: -1, tag: Const.LEN_MSG)
                        socketConn.write(rawData, withTimeout: -1, tag: Const.IMG_MSG)
                    }
                }
            }
        }
    }

    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        sync(self.connectedSockets){
            self.connectedSockets.add(newSocket)
            NSLog("socket accepted %@: %hu", newSocket.connectedHost, newSocket.connectedPort)

        }
        self.isRunning = true
    }

    func socket(_ sock: GCDAsyncSocket, shouldTimeoutReadWithTag tag: Int, elapsed: TimeInterval, bytesDone length: UInt) -> TimeInterval {
        if elapsed <= Const.READ_TIMEOUT {
            let warningMsg: String = "Are you still there?\r\n"
            let warningData: Data = warningMsg.data(using: String.Encoding.utf8)!
            sock.write(warningData, withTimeout: -1, tag: Const.WARNING_MSG)
            return Const.READ_TIMEOUT_EXTENSION
        }
        return 0.0
    }
    
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error) {
        if sock != self.listenSocket {
            sync(self.connectedSockets){
                self.connectedSockets.remove(sock)
            }
        }
    }
    
    func sync(_ lock: AnyObject, proc: () -> ()) {
        objc_sync_enter(lock)
        proc()
        objc_sync_exit(lock)
    }
    
}
