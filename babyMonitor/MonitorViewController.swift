import UIKit
import AVFoundation
import CocoaAsyncSocket

class MonitorViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncSocketDelegate,GCDAsyncUdpSocketDelegate ,NADViewDelegate{

    @IBOutlet weak var imgVw: UIImageView!
    var udpSocket:GCDAsyncUdpSocket?;
    var asyncSocket:GCDAsyncSocket?;
    var socketQueue:DispatchQueue?;
    var connectedSockets:NSMutableArray? = [];
    var isConnected:Bool?;
    fileprivate var nadViewLocal: NADView!

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.bringSubview(toFront: reconnectBtn)
        do {
            self.isConnected = false
            self.udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
            self.socketQueue = DispatchQueue(label: "socketQueue2",attributes: [])
            self.asyncSocket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
            try self.udpSocket?.enableBroadcast(true)
            try self.udpSocket?.bind(toPort: 0)
            try self.udpSocket?.beginReceiving()
            let data = UIDevice.current.name.data(using: String.Encoding.utf8)
            self.udpSocket?.send(data, toHost: "255.255.255.255", port: 8081, withTimeout: -1, tag:0)
        }catch {
            print("error viewDidLoad")
        }
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
    }
    func nadViewDidFinishLoad(_ adView: NADView!) {
        self.view.addSubview(adView) // ロードが完了してから NADView を表示する場合
    }

    @IBOutlet weak var reconnectBtn: UIButton!
    @IBAction func reconnectClick(_ sender: AnyObject) {
        do {
            self.isConnected = false
            self.udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
            self.socketQueue = DispatchQueue(label: "socketQueue2",attributes: [])
            self.asyncSocket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
            try self.udpSocket?.enableBroadcast(true)
            try self.udpSocket?.bind(toPort: 0)
            try self.udpSocket?.beginReceiving()
            let data = UIDevice.current.name.data(using: String.Encoding.utf8)
            self.udpSocket?.send(data, toHost: "255.255.255.255", port: 8081, withTimeout: -1, tag:0)
        }catch {
            print("error viewDidLoad")
        }
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: AnyObject) {
        if (self.isConnected == true) {
            return
        }
        do{
            let msg: String = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as! String
            try self.asyncSocket?.connect(toHost: msg, onPort: 8080)
            self.asyncSocket?.readData(toLength: 2, withTimeout: -1, tag: Const.NEED_PWD)
            self.isConnected = true
        }catch{
            print("error udp didReceiveData")
        }
    }

    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        if (tag == Const.LEN_MSG) {
            var length: Int = 0;
            (data as NSData).getBytes(&length, length: MemoryLayout<Int>.size)
            self.asyncSocket?.readData(toLength: UInt(length), withTimeout: -1, tag: Const.IMG_MSG)
        }
        else if (tag == Const.IMG_MSG) {
            // Process the response
            self.recieveVideoFromData2(data)
            // Start reading the next response
            self.asyncSocket?.readData(toLength: 8, withTimeout: -1, tag: Const.LEN_MSG)
        }
        else if (tag == Const.NEED_PWD){
            
        }
    }

    func recieveVideoFromData2(_ data: Data) {
        let image: UIImage = UIImage(data: data)!
        self.imgVw.image = image
    }
    
}
