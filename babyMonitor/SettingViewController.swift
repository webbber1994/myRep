import UIKit
import AVFoundation
import CocoaAsyncSocket

class SettingViewController: UIViewController{

    @IBAction func usePasswordPressed(_ sender: UISwitch) {
        if (sender.isOn) {
            Setting.usePassword = true;
        }else{
            Setting.usePassword = false;
        }
    }

}
