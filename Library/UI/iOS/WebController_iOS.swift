import UIKit
import SafariServices

final class WebControllerIOS: SFSafariViewController, SFSafariViewControllerDelegate, WebController {
    
    private var currentRequest: URLRequest?
    private var onResult: ((WebControllerResult) -> ())?
    var onDismiss: (() -> ())?
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        onDismiss?()
    }
    
    init?(urlRequest: URLRequest, onResult: @escaping (WebControllerResult) -> (), onDismiss: (() -> ())?) {
        guard let url = urlRequest.url else {
            return nil
        }
        super.init(url: url, configuration: .init())
        
        self.delegate = self
        
        self.currentRequest = urlRequest
        self.onResult = onResult
        self.onDismiss = onDismiss
    }
    
    func load(urlRequest: URLRequest, onResult: @escaping (WebControllerResult) -> ()) {}
    func reload() {}
    func goBack() {}
    
    func dismiss() {
        DispatchQueue.main.async {
            self.dismiss(animated: true, completion: nil)
        }
    }
    
    func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo URL: URL) {
        if URL.absoluteString.contains("access_token") {
            onResult?(.response(URL))
        }
    }

}
