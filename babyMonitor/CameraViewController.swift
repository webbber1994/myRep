import UIKit
import AVFoundation
import CocoaAsyncSocket


class CameraViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate  ,NADViewDelegate{

    @IBOutlet weak var passcodeLabel: UILabel!
    @IBOutlet weak var cameraView: UIView!
    var session:AVCaptureSession?
    var sessionQueue: DispatchQueue?
    var videoDataOutputQueue: DispatchQueue?
    var videoDeviceInput:AVCaptureDeviceInput?
    var setupResult: AVCamSetupResult?
    var udpSocket:GCDAsyncUdpSocket?
    var listenSocket:GCDAsyncSocket?
    var udpSocketQueue: DispatchQueue?
    var socketQueue: DispatchQueue?
    var connectedSockets:NSMutableArray = []
    var isRunning: Bool = false
    var cnt: Int = 0
    var previewLayer:AVCaptureVideoPreviewLayer?
    fileprivate var nadViewLocal: NADView!

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

    func nadViewDidFinishLoad(_ adView: NADView!) {
        self.view.addSubview(adView) // ロードが完了してから NADView を表示する場合
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
                        return
                    }

                    // Change this value
                    let videoDevice: AVCaptureDevice = CameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: .back)
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
                        self.setupResult = AVCamSetupResult.sessionConfigurationFailed
                    }

                    self.videoDataOutputQueue = DispatchQueue(label: "videoDataOutputQueue", attributes: [])
                    let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
                    videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable : Int(kCVPixelFormatType_32BGRA)]
                    videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
                    if self.session!.canAddOutput(videoDataOutput) {
                        self.session!.addOutput(videoDataOutput)
                        let connection: AVCaptureConnection = videoDataOutput.connection(withMediaType: AVMediaTypeVideo)
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    else {
                        self.setupResult = AVCamSetupResult.sessionConfigurationFailed
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
        //passcode
        passcodeLabel.backgroundColor = UIColor.clear;
        if(Setting.usePassword){
            Setting.setUsePassword(self.genPwd())
            passcodeLabel.text = "Password:" + Setting.password
        }else{
            passcodeLabel.text = "";
        }

        self.cameraView.addSubview(passcodeLabel);
        self.cameraView.bringSubview(toFront: passcodeLabel);
        // NADViewクラスを生成
        nadViewLocal = NADView(frame: CGRect(x: (UIScreen.main.bounds.size.width - 320)/2, y: UIScreen.main.bounds.size.height - 50, width: UIScreen.main.bounds.size.width, height: 50))

        // 広告枠のapikey/spotidを設定(必須)
        nadViewLocal.setNendID("227c452f8df541d30036a2dfa2168823de732476",
                               spotID: "609226")
        // nendSDKログ出力の設定(任意)
        nadViewLocal.isOutputLog = false
        // delegateを受けるオブジェクトを指定(必須)
        nadViewLocal.delegate = self // 読み込み開始(必須)
        nadViewLocal.load()

        //
    }

    func genPwd() -> String {
        // ランダムの４桁数字
        var random = arc4random_uniform(10)
        var str = random.description

         random = arc4random_uniform(10)
         str = str + random.description

        random = arc4random_uniform(10)
        str = str + random.description
        random = arc4random_uniform(10)
        str = str + random.description

        return str

    }

    class func deviceWithMediaType(_ mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice {
        let devices = AVCaptureDevice.devices(withMediaType: mediaType)
        var captureDevice: AVCaptureDevice = devices!.first as! AVCaptureDevice

        for device in devices!{
            let device = device as! AVCaptureDevice
            if device.position == position {
                captureDevice = device
                break
            }
        }
        return captureDevice
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
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

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

    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: AnyObject) {
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
            let dataLen: NSData = NSData(bytes:&len, length: 8)
            sync(self.connectedSockets){
                for sockTmp in self.connectedSockets{
                    let socketConn:GCDAsyncSocket = sockTmp as! GCDAsyncSocket
                    self.socketQueue!.async{
                        socketConn.write(dataLen as Data!, withTimeout: -1, tag: Const.LEN_MSG)
                        socketConn.write(rawData, withTimeout: -1, tag: Const.IMG_MSG)
                    }
                }
            }
        }
    }

    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        sync(self.connectedSockets){
            let str111 = "";
            if(Setting.usePassword){
                //str111 = "PWD";
            }else{
                //str111 = "NPW";
            }
            let needPwd :Data = str111.data(using: String.Encoding.utf8)!
            newSocket.write(needPwd, withTimeout: -1, tag: Const.NEED_PWD);
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
    
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: NSError) {
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
