import UIKit
import CocoaAsyncSocket

class ViewController: UIViewController ,NADViewDelegate {

    
    fileprivate var nadViewLocal: NADView!
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController!.navigationBar.tintColor = UIColor.white;  // バーアイテムカラー
        self.navigationController!.navigationBar.barTintColor = UIColor.purple;
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

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

