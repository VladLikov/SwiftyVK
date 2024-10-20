import Foundation
import AuthenticationServices

protocol WebPresenter: class {
    func presentWith(urlRequest: URLRequest) throws -> String
    func dismiss()
}

enum WebControllerResult {
    case response(URL?)
    case error(VKError)
}

private enum WebPresenterResult {
    case response(String)
    case error(VKError)
}

private enum ResponseParsingResult {
    case response(String)
    case fail
    case nothing
    case wrongPage
}

private final class LoadingState {
    var originalPath: String
    var fails: Int = 0
    var result: WebPresenterResult?
    
    init(originalPath: String) {
        self.originalPath = originalPath
    }
}

final class WebPresenterImpl: NSObject, WebPresenter, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        DispatchQueue.anywayOnMain {
            UIApplication.shared.keyWindow!
        }
    }
    
    private let uiSyncQueue: DispatchQueue
    private weak var controllerMaker: WebControllerMaker?
    private var webAuthSession: ASWebAuthenticationSession?
    private let maxFails: Int
    private let timeout: TimeInterval

    private let callbackURLScheme = "vk5549492"
    
    init(
        uiSyncQueue: DispatchQueue,
        controllerMaker: WebControllerMaker,
        maxFails: Int,
        timeout: TimeInterval
        ) {
        self.uiSyncQueue = uiSyncQueue
        self.controllerMaker = controllerMaker
        self.maxFails = maxFails
        self.timeout = timeout
    }
        
    func presentWith(urlRequest: URLRequest) throws -> String {
        guard let controllerMaker = controllerMaker else { throw VKError.weakObjectWasDeallocated }

        let semaphore = DispatchSemaphore(value: 0)
        let state = LoadingState(originalPath: urlRequest.url?.path ?? "")
        
        return try uiSyncQueue.sync { [weak self] in
                                
            let webAuthSession = ASWebAuthenticationSession(
                url: urlRequest.url!,
                callbackURLScheme: callbackURLScheme)
            { callback, error in
                                
                guard error == nil, let callback else {
                    return
                }
                
                let parsedResult = try? self?.parse(url: callback, originalPath: state.originalPath)

                switch parsedResult {
                case let .response(value):
                    state.result = .response(value)
                    
                case .fail:
                    state.fails += 1
                    
                default:
                    break
                }
                
                semaphore.signal()
                                                
            }
            
            webAuthSession.presentationContextProvider = self
            webAuthSession.start()
            
            self?.webAuthSession = webAuthSession
            
            switch semaphore.wait(timeout: .now() + timeout) {
            case .timedOut:
                throw VKError.webPresenterTimedOut
            case .success:
                break
            }
            
            switch state.result {
            case .response(let response)?:
                return response
            case .error(let error)?:
                throw error
            case nil:
                throw VKError.webPresenterResultIsNil
            }
        }
    }
    
    private func parse(url maybeUrl: URL?, originalPath: String) throws -> ResponseParsingResult {
        guard let url = maybeUrl else {
            throw VKError.authorizationUrlIsNil
        }
                
        let fragment = url.fragment ?? ""
        let query = url.query ?? ""
        let scheme = url.scheme ?? ""
                
        if scheme != callbackURLScheme {
            return .wrongPage
        }
        if fragment.isEmpty && query.isEmpty {
            return .fail
        }
        else if fragment.contains("access_token=") {
            return .response(fragment)
        }
        else if fragment.contains("success=1") {
            return .response(fragment)
        }
        else if fragment.contains("access_denied") {
            throw VKError.authorizationDenied
        }
        else if fragment.contains("cancel=1") {
            throw VKError.authorizationCancelled
        }
        else if fragment.contains("fail=1") {
            throw VKError.authorizationFailed
        }
        
        return .nothing
    }
    
    private func parse(error: VKError, fails: Int) throws -> ResponseParsingResult {
        if case .authorizationCancelled = error {
            throw error
        }
        
        guard fails >= maxFails - 1 else {
            return .fail
        }
        
        throw error
    }
    
    func dismiss() {
        self.webAuthSession?.cancel()
    }
}
