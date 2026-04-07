import Flutter
import UIKit
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 1. Safely extract Dart Defines
    let dartDefinesString = Bundle.main.infoDictionary!["DART_DEFINES"] as? String ?? ""
    var mapsApiKey = ""
    
    // 2. Decode the Base64 strings to find your specific key
    for definedValue in dartDefinesString.components(separatedBy: ",") {
        if let decodedData = Data(base64Encoded: definedValue),
           let decodedString = String(data: decodedData, encoding: .utf8) {
            if decodedString.hasPrefix("MAPS_API_KEY=") {
                mapsApiKey = String(decodedString.dropFirst("MAPS_API_KEY=".count))
            }
        }
    }
    
    // 3. Provide it to Google Maps!
    GMSServices.provideAPIKey(mapsApiKey)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

