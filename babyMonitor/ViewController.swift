import UIKit
import CocoaAsyncSocket
import StoreKit

class ViewController: UIViewController ,SKProductsRequestDelegate, SKPaymentTransactionObserver{

    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController!.navigationBar.tintColor = UIColor.white;  // バーアイテムカラー
        self.navigationController!.navigationBar.barTintColor = UIColor.init(red: 30/255, green: 144/255, blue: 1, alpha: 0)
    }



    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        print("productsRequest")
        // Check whether there is an invalid item
        if response.invalidProductIdentifiers.count > 0 {
            let alertController = UIAlertController(title: "Error", message: "Item ID is invalid", preferredStyle: .alert)
            let defaultAction = UIAlertAction(title:  "OK", style: .default, handler: nil)
            alertController.addAction(defaultAction)
            present(alertController, animated: true, completion: nil)
            return
        }
        // Purchase process start
        SKPaymentQueue.default().add(self)
        for product in response.products {
            let payment:SKPayment = SKPayment(product: product )
            SKPaymentQueue.default().add(payment)
        }
    }
}

