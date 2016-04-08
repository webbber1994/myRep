//
//  MonitorViewController.swift
//  BabyMonitor
//
//  Created by dede on 4/3/16.
//  Copyright © 2016 dede. All rights reserved.
//


import UIKit
import AVFoundation
import CocoaAsyncSocket

class MonitorViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncSocketDelegate,GCDAsyncUdpSocketDelegate {

    @IBOutlet weak var imgVw: UIImageView!
    var udpSocket:GCDAsyncUdpSocket?;
    var asyncSocket:GCDAsyncSocket?;
    var socketQueue:dispatch_queue_t?;
    var connectedSockets:NSMutableArray? = [];
    var isConnected:Bool?;

    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            self.isConnected = false
            self.udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: dispatch_get_main_queue())
            self.socketQueue = dispatch_queue_create("socketQueue2",DISPATCH_QUEUE_SERIAL)
            self.asyncSocket = GCDAsyncSocket(delegate: self, delegateQueue: dispatch_get_main_queue())
            try self.udpSocket?.enableBroadcast(true)
            try self.udpSocket?.bindToPort(0)
            try self.udpSocket?.beginReceiving()
            let data = UIDevice.currentDevice().name.dataUsingEncoding(NSUTF8StringEncoding)
            self.udpSocket?.sendData(data, toHost: "192.168.0.255", port: 8081, withTimeout: -1, tag:0)
        }catch {
            print("error viewDidLoad")
        }

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func udpSocket(sock: GCDAsyncUdpSocket, didReceiveData data: NSData, fromAddress address: NSData, withFilterContext filterContext: AnyObject) {
        if (self.isConnected == true) {
            return
        }
        do{

            let msg: String = NSString(data: data, encoding: NSUTF8StringEncoding) as! String
            try self.asyncSocket?.connectToHost(msg, onPort: 8080)
            self.asyncSocket?.readDataToLength(8, withTimeout: -1, tag: Const.LEN_MSG)

            self.isConnected = true
        }catch{
            print("error udp didReceiveData")
        }
    }

    func socket(sock: GCDAsyncSocket, didReadData data: NSData, withTag tag: Int) {
        if (tag == Const.LEN_MSG) {
            var aBuffer = Array<Int8>(count: data.length, repeatedValue: 0)
            data.getBytes(&aBuffer, length: data.length) // &がアドレス演算子みたいに使える。

            var length: Int = 0;
            data.getBytes(&length, length: sizeof(Int))
            self.asyncSocket?.readDataToLength(UInt(length), withTimeout: -1, tag: Const.IMG_MSG)
        }
        else if (tag == Const.IMG_MSG) {
            // Process the response
            self.recieveVideoFromData2(data)
            // Start reading the next response
            self.asyncSocket?.readDataToLength(8, withTimeout: -1, tag: Const.LEN_MSG)
        }
    }

    func recieveVideoFromData2(data: NSData) {
        let image: UIImage = UIImage(data: data)!
        self.imgVw.image = image
    }
    
}
