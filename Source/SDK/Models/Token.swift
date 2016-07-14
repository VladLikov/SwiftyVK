import Foundation



private var tokenInstance : Token! {
  willSet {
    if newValue != nil {
      Token.notifyExist()
    }
    else {
      Token.notifyNotExist()
    }
  }
}



internal class Token: NSObject, NSCoding {
  
  internal private(set) static var revoke = true
  
  private var token       : String
  private var expires     : Int
  private var isOffline   = false
  private var parameters  : Dictionary<String, String>
  
  override var description : String {
    return "Token with parameters: \(parameters))"
  }
  
  
  
  init(urlString: String) {
    let parameters = Token.parse(urlString)
    token       = parameters["access_token"]!
    expires     = 0 + Int(Date().timeIntervalSince1970)
    if parameters["expires_in"] != nil {expires += Int(parameters["expires_in"]!)!}
    isOffline   = (parameters["expires_in"]?.isEmpty == false && (Int(parameters["expires_in"]!) == 0) || parameters["expires_in"] == nil)
    self.parameters = parameters
    
    super.init()
    tokenInstance = self
    Token.revoke = true
    VK.Log.put("Token", "INIT \(self)")
    save()
  }
  
  
  
  class func get() -> String? {
    VK.Log.put("Token", "Getting")
    
    if tokenInstance != nil && self.isExpired() == false {
      return tokenInstance.token
    }
    else if let _ = _load() where self.isExpired() == false {
      return tokenInstance.token
    }
    return nil
  }
  
  
  
  class var exist : Bool {
    return tokenInstance != nil
  }
  
  
  
  private class func parse(_ request: String) -> Dictionary<String, String> {
    let cleanRequest  = request.components(separatedBy: "#")[1]
    let preParameters = cleanRequest.components(separatedBy: "&")
    var parameters    = Dictionary<String, String>()
    
    for keyValueString in preParameters {
      let keyValueArray = keyValueString.components(separatedBy: "=")
      parameters[keyValueArray[0]] = keyValueArray[1]
    }
    VK.Log.put("Token", "Parse from parameters: \(parameters)")
    return parameters
  }
  
  
  
  private class func isExpired() -> Bool {
    if tokenInstance == nil {
      return true
    }
    else if tokenInstance.isOffline == false && tokenInstance.expires < Int(Date().timeIntervalSince1970) {
      VK.Log.put("Token", "Expired")
      revoke = false
      Token.remove()
      return true
    }
    return false
  }
  
  
  
  private class func _load() -> Token? {
    let parameters  = VK.delegate!.vkTokenPath()
    let useDefaults = parameters.useUserDefaults
    let filePath    = parameters.alternativePath
    if useDefaults {tokenInstance = self.loadFromDefaults()}
    else           {tokenInstance = self.loadFromFile(filePath)}
    return tokenInstance
  }
  
  
  
  private class func loadFromDefaults() -> Token? {
    let defaults = UserDefaults.standard
    if !(defaults.object(forKey: "Token") != nil) {return nil}
    let object: AnyObject! = NSKeyedUnarchiver.unarchiveObject(with: defaults.object(forKey: "Token") as! Data)
    if object == nil {
      VK.Log.put("Token", "Load from NSUSerDefaults failed")
      return nil
    }
    VK.Log.put("Token", "Loaded from NSUserDefaults")
    return object as? Token
  }
  
  ///Загрузка из файла
  private class func loadFromFile(_ filePath : String) -> Token? {
    let manager = FileManager.default
    if !manager.fileExists(atPath: filePath) {
      VK.Log.put("Token", "Loaded from file \(filePath) failed")
      return nil
    }
    let token = (NSKeyedUnarchiver.unarchiveObject(withFile: filePath)) as? Token
    VK.Log.put("Token", "Loaded from file: \(filePath)")
    return token
  }
  
  
  
  func save() {
    let parameters  = VK.delegate!.vkTokenPath()
    let useDefaults = parameters.useUserDefaults
    let filePath    = parameters.alternativePath
    if useDefaults {saveToDefaults()}
    else           {saveToFile(filePath)}
  }
  
  
  
  private func saveToDefaults() {
    let defaults = UserDefaults.standard
    defaults.set(NSKeyedArchiver.archivedData(withRootObject: self), forKey: "Token")
    defaults.synchronize()
    VK.Log.put("Token", "Saved to NSUserDefaults")
  }
  
  
  
  private func saveToFile(_ filePath : String) {
    let manager = FileManager.default
    if manager.fileExists(atPath: filePath) {
      do {
        try manager.removeItem(atPath: filePath)
      }
      catch _ {}
    }
    NSKeyedArchiver.archiveRootObject(self, toFile: filePath)
    VK.Log.put("Token", "Saved to file: \(filePath)")
  }
  
  
  
  class func remove() {
    let parameters  = VK.delegate!.vkTokenPath()
    let useDefaults = parameters.useUserDefaults
    let filePath    = parameters.alternativePath
    
    let defaults = UserDefaults.standard
    if defaults.object(forKey: "Token") != nil {defaults.removeObject(forKey: "Token")}
    defaults.synchronize()
    
    if !useDefaults {
      let manager = FileManager.default
      if manager.fileExists(atPath: filePath) {
        do {try manager.removeItem(atPath: filePath)}
        catch _ {}
      }
    }
    
    if tokenInstance != nil {tokenInstance = nil}
    VK.Log.put("Token", "Remove")
  }
  
  
  
  private class func notifyExist() {
    if VK.state != .authorized {
      DispatchQueue.global(attributes: DispatchQueue.GlobalAttributes.qosDefault).async {
        Thread.sleep(forTimeInterval: 0.1)
        if tokenInstance != nil {
          VK.delegate!.vkDidAutorize(tokenInstance.parameters)
        }
      }
    }
  }
  
  
  private class func notifyNotExist() {
    if VK.state == .authorized {
      VK.delegate!.vkDidUnautorize()
    }
  }
  
  
  
  deinit {VK.Log.put("Token", "DEINIT \(self)")}
  
  
  
  //MARK: - NSCoding protocol
  func encode(with aCoder: NSCoder) {
    aCoder.encode(parameters,  forKey: "parameters")
    aCoder.encode(token,       forKey: "token")
    aCoder.encode(expires,    forKey: "expires")
    aCoder.encode(isOffline,     forKey: "isOffline")
  }
  
  
  required init?(coder aDecoder: NSCoder) {
    token         = aDecoder.decodeObject(forKey: "token") as! String
    expires       = aDecoder.decodeInteger(forKey: "expires")
    isOffline     = aDecoder.decodeBool(forKey: "isOffline")
    
    if let parameters = aDecoder.decodeObject(forKey: "parameters") as? Dictionary<String, String> {
      self.parameters = parameters
    }
    else {
      self.parameters = [:]
    }

  }
}

