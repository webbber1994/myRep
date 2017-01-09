import UIKit
import AVFoundation
import CocoaAsyncSocket

class MonitorViewController: UIViewController, AVAudioPlayerDelegate,GCDAsyncSocketDelegate,GCDAsyncUdpSocketDelegate{

    @IBOutlet weak var imgVw: UIImageView!
    var udpSocket:GCDAsyncUdpSocket?;
    var asyncSocket:GCDAsyncSocket?;
    var socketQueue:DispatchQueue?;
    var connectedSockets:NSMutableArray? = [];
    var isConnected:Bool?;
    var currentType:Int?;

    var audioPlayer:AVAudioPlayer!

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

    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any) {
        if (self.isConnected == true) {
            return
        }
        do{
            let msg: String = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as! String
            try self.asyncSocket?.connect(toHost: msg, onPort: 8080)
            self.asyncSocket?.readData(toLength: 2, withTimeout: -1, tag: Const.IMG_TYP)
            self.isConnected = true
        }catch{
            print("error udp didReceiveData")
        }
    }

    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        if (tag == Const.IMG_TYP){
            var type: Int = 0
            (data as NSData).getBytes(&type, length: 2)
            currentType = type
            self.asyncSocket?.readData(toLength: 8, withTimeout: -1, tag: Const.LEN_MSG)
        }
        else if (tag == Const.LEN_MSG) {
            var length: Int = 0;
            (data as NSData).getBytes(&length, length: MemoryLayout<Int>.size)
            self.asyncSocket?.readData(toLength: UInt(length), withTimeout: -1, tag: Const.IMG_MSG)
        }
        else if (tag == Const.IMG_MSG) {
            // Process the response
            self.recieveVideoFromData2(datain: data)
            // Start reading the next response
            self.asyncSocket?.readData(toLength: 2, withTimeout: -1, tag: Const.IMG_TYP)
        }
        else{
            print("tag error")
        }
    }

    func recieveVideoFromData2(datain: Data) {
        let image: UIImage = UIImage.init(data: datain)!
        self.imgVw.image = image
    }
    
}
