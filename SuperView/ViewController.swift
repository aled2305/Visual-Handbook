//
//  ViewController.swift
//  UniversalWebview
//
//  Created by Mario Kovacevic on 05/08/2016.
//  Copyright (c) 2016 Brommko LLC. All rights reserved.
//

import Foundation
import UIKit
import WebKit
import MBProgressHUD
import GoogleMobileAds
import SwiftyUserDefaults
import SwiftyStoreKit
import Firebase
import WKBridge
import CoreLocation
import AVFoundation
import GCDWebServer

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, MBProgressHUDDelegate, GADBannerViewDelegate, GADInterstitialDelegate, LocationServiceDelegate, GCDWebServerDelegate  {
    
    @IBOutlet weak var backgroundImage: UIImageView?
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var toolbar: UIToolbar!
    var bannerView: GADBannerView?

    let webServer = GCDWebServer()

    @IBOutlet var backButton: UIBarButtonItem?
    @IBOutlet var forwardButton: UIBarButtonItem?
    @IBOutlet var iapButton: UIBarButtonItem?
    @IBOutlet var reloadButton: UIBarButtonItem?
    
    var mainURL:URL?
    var wkWebView: WKWebView?
    var popViewController:UIViewController?
    var load : MBProgressHUD = MBProgressHUD()
    var interstitial: GADInterstitial!
    let request = GADRequest()
    
    var timer:Timer?
    var showInterstitialInSecoundsEvery:Int! = 60
    var count:Int = 60
    var audioPlayer = AVAudioPlayer()
    let appData = NSDictionary(contentsOfFile: AppDelegate.dataPath())

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback, with: .mixWithOthers)
            try audioSession.setActive(true)
            print("AVAudioSession is Active")
        } catch {
            print(error)
        }
        
        if let gps = self.appData?.value(forKey: "UseGPS") as? Bool {
            if gps == true {
                LocationService.sharedInstance.delegate = self
                LocationService.sharedInstance.startUpdatingLocation()
            }
        }
        
        self.activityIndicator.startAnimating()
        self.request.testDevices = ["bb394635b98430350b538d1e2ea1e9d6", kGADSimulatorID];
        
        self.loadToolbar()
        self.loadInterstitalAd()
        self.loadBannerAd()
        self.loadWebView()
        
        if let secounds = self.appData?.value(forKey: "ShowInterstitialInSecoundsEvery") as? String {
            if !secounds.isEmpty {
                self.showInterstitialInSecoundsEvery = Int(secounds)!
                self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(ViewController.counterForInterstitialAd), userInfo: nil, repeats: true)
            }
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        var bannerHeight = self.view.frame.height - (self.bannerView?.frame.height ?? 0)
        var safeAreaBottom:CGFloat = 0
        if #available(iOS 11.0, *) {
            safeAreaBottom = (UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0)!
            bannerHeight -= safeAreaBottom
        }
        if self.appData?.value(forKey: "Toolbar") as? Bool == true {
            bannerHeight -= self.toolbar.frame.height
        }
        self.bannerView?.frame.origin = CGPoint(x: self.view.frame.width/2 - self.bannerView!.frame.width/2, y:  bannerHeight)
    }
    
    func showLoader() {
        if self.backgroundImage == nil {
            self.load = MBProgressHUD.showAdded(to: self.view, animated: true)
            self.load.mode = MBProgressHUDMode.indeterminate
        }
    }
    
    func loadToolbar() {
        self.backButton?.isEnabled = false
        self.forwardButton?.isEnabled = false
    }
    
    @objc @IBAction func back() {
        _ = self.wkWebView?.goBack()
    }
    
    @objc @IBAction func forward() {
        _ = self.wkWebView?.goForward()
    }
    
    @objc func pullToRefresh(_ sender: UIRefreshControl?) {
        self.reload()
        sender?.endRefreshing()
    }
    
    @objc @IBAction func reload() {
        self.wkWebView?.reloadFromOrigin()
    }
    
    func loadWebView() {
        self.getURL()
        self.loadWebSite()
    }
    
    func getURL() {
        if let storedURL = UserDefaults.standard.string(forKey: "URL") {
            self.mainURL = URL(string: storedURL)
        }
        
        if self.mainURL == nil {
            if let urlString = self.appData?.value(forKey: "URL") as? String {
                if !urlString.isEmpty {
                    if self.mainURL == nil {
                        self.mainURL = URL(string: urlString)
                    }
                }
            }
        }
    }
    
    func loadLocalWebServer() {
        let folderPath = Bundle.main.path(forResource: "www", ofType: nil)
        do {
            self.webServer.delegate = self
            self.webServer.addGETHandler(forBasePath: "/", directoryPath: folderPath!, indexFilename: nil, cacheAge: 3600, allowRangeRequests: true)
            let options = [
                GCDWebServerOption_Port: 8080,
                GCDWebServerOption_BindToLocalhost: true,
                GCDWebServerOption_ServerName: "GCD Web Server"
                ] as [String : Any]
            try self.webServer.start(options: options)
            print("Visit \(String(describing: webServer.serverURL)) in your web browser")
        } catch {
            print ("File HTML error")
        }
    }
    
    func webServerDidStart(_ server: GCDWebServer) {
        self.mainURL = self.webServer.serverURL?.appendingPathComponent("index.html")
        self.loadWebSite()
    }
    
    func loadWebSite() {
        let theConfiguration:WKWebViewConfiguration? = WKWebViewConfiguration()
        let thisPref:WKPreferences = WKPreferences()
        thisPref.javaScriptCanOpenWindowsAutomatically = true;
        thisPref.javaScriptEnabled = true
        theConfiguration!.preferences = thisPref;
        
        self.wkWebView = WKWebView(frame: self.getFrame(), configuration: theConfiguration!)
        // [START add_handler]
        self.wkWebView?.configuration.userContentController.add(self, name: "firebase")
        // [END add_handler]
        if self.mainURL != nil {
            if self.appData?.value(forKey: "EnableWebViewCache") as? Bool == true {
                _ = self.wkWebView?.load(URLRequest(url: self.mainURL!))
            } else {
                _ = self.wkWebView?.load(URLRequest(url: self.mainURL!, cachePolicy: .reloadIgnoringLocalCacheData))
            }
        } else {
            if self.appData?.value(forKey: "UseLocalServer(Best for games)") as? Bool == true {
                self.loadLocalWebServer()
            } else {
                var fileURL = URL(fileURLWithPath: Bundle.main.path(forResource: "www/index", ofType: "html")!)
                if #available(iOS 9.0, *) {
                    _ = self.wkWebView?.loadFileURL(fileURL, allowingReadAccessTo: fileURL)
                } else {
                    do {
                        fileURL = try fileURLForBuggyWKWebView8(fileURL: fileURL)
                        if self.appData?.value(forKey: "EnableWebViewCache") as? Bool == true {
                            _ = self.wkWebView?.load(URLRequest(url: fileURL))
                        } else {
                            _ = self.wkWebView?.load(URLRequest(url: fileURL, cachePolicy: .reloadIgnoringLocalCacheData))
                        }
                    } catch let error as NSError {
                        print("Error: " + error.debugDescription)
                    }
                }
            }
        }
        
        self.wkWebView?.navigationDelegate = self
        self.wkWebView?.uiDelegate = self
        self.wkWebView?.bridge.printScriptMessageAutomatically = true
        self.wkWebView?.addObserver(self, forKeyPath: "loading", options: .new, context: nil)
        self.wkWebView?.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        
        if let pullToRefresh = self.appData?.value(forKey: "PullToRefresh") as? Bool {
            if pullToRefresh == true {
                let refreshControl = UIRefreshControl()
                refreshControl.addTarget(self, action: #selector(self.pullToRefresh(_:)), for: UIControlEvents.valueChanged)
                self.wkWebView?.scrollView.addSubview(refreshControl)
            }
        }
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            let userID = OneSignal.getPermissionSubscriptionState()?.subscriptionStatus.userId
            completion(.success(["token": userID ?? "No Token"]))
        }, for: "onesignaltoken")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            let token = InstanceID.instanceID().token()
            completion(.success(["token": token ?? "No Token"]))
        }, for: "firebasetoken")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            self.removeAdsAction()
        }, for: "make_purchase")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            if self.interstitial != nil && self.interstitial.isReady {
                self.interstitial.present(fromRootViewController: self)
            }
        }, for: "show_interstitial")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            completion(.success(["purchased": Defaults[.adsPurchased]]))
        }, for: "app_purchased")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            let title:String! = parameters?["title"] as! String
            let message:String! = parameters?["message"] as! String
            
            if #available(iOS 10.0, *) {
                let center = UNUserNotificationCenter.current()
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = message
                content.categoryIdentifier = "alarm"
                content.userInfo = ["customData": "fizzbuzz"]
                content.sound = UNNotificationSound.default()
                
                let trigger = UNTimeIntervalNotificationTrigger.init(timeInterval: 3, repeats: false)
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                center.add(request)
            } else {
                
                // ios 9
                let notification = UILocalNotification()
                notification.fireDate = NSDate(timeIntervalSinceNow: 5) as Date
                notification.alertBody = title
                notification.alertAction = message
                notification.soundName = UILocalNotificationDefaultSoundName
                UIApplication.shared.scheduleLocalNotification(notification)
            }
            
        }, for: "create_notification")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            self.load.hide(animated: true)
            self.load = MBProgressHUD.showAdded(to: self.view, animated: true)
            self.load.mode = MBProgressHUDMode.indeterminate
            self.load.isUserInteractionEnabled = false
        }, for: "show_loader")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            self.load.hide(animated: true)
        }, for: "hide_loader")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            RateMyApp.sharedInstance.showRatingAlert()
        }, for: "rate_app")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            if let name = parameters?["name"] as? String {
                let components = name.components(separatedBy: ".")
                let soundName = components.first
                let extensionName = components.last
                do {
                    let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: soundName, ofType: extensionName)!)
                    self.audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
                    if self.audioPlayer.prepareToPlay() {
                        self.audioPlayer.play()
                    }
                } catch {
                    
                }
            }
        }, for: "play_sound")
        
        self.wkWebView?.bridge.register({ (parameters, completion) in
            self.audioPlayer.stop()
        }, for: "stop_sound")
        
    }
    
    func fileURLForBuggyWKWebView8(fileURL: URL) throws -> URL {
        // Some safety checks
        if !fileURL.isFileURL {
            throw NSError(
                domain: "BuggyWKWebViewDomain",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("URL must be a file URL.", comment:"")])
        }
        _ = try! fileURL.checkResourceIsReachable()
        
        // Create "/temp/www" directory
        let fm = FileManager.default
        let tmpDirURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("www")
        try! fm.createDirectory(at: tmpDirURL, withIntermediateDirectories: true, attributes: nil)
        
        // Now copy given file to the temp directory
        let dstURL = tmpDirURL.appendingPathComponent(fileURL.lastPathComponent)
        let _ = try? fm.removeItem(at: dstURL)
        try! fm.copyItem(at: fileURL, to: dstURL)
        
        // Files in "/temp/www" load flawlesly :)
        return dstURL
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if (keyPath == "loading") {
            self.backButton?.isEnabled = self.wkWebView!.canGoBack
            self.forwardButton?.isEnabled = self.wkWebView!.canGoForward
        } else if (keyPath == "estimatedProgress") {
            let estimatedProgress = Float(self.wkWebView!.estimatedProgress)
            if estimatedProgress > 0.90 {
//                self.didFinish()
            }
        }
    }
    
    func loadInterstitalAd() {
        if Defaults[.adsPurchased] == false {
            if let interstitialId = self.appData?.value(forKey: "AdMobInterstitialUnitId") as? String {
                if !interstitialId.isEmpty {
                    self.interstitial = GADInterstitial(adUnitID: interstitialId)
                    self.interstitial.delegate = self
                    self.interstitial.load(self.request)
                }
            }
            self.count = self.showInterstitialInSecoundsEvery
        }
    }
    
    @objc func counterForInterstitialAd() {
        if(self.count > 0) {
            self.count = self.count - 1
            print("COUNTER FOR INTERSTITIAL AD: \(self.count)")
        } else {
            self.count = self.showInterstitialInSecoundsEvery
            self.showInterstitialAd()
        }
    }
    
    func showInterstitialAd() {
        if self.count == self.showInterstitialInSecoundsEvery {
            if self.interstitial != nil && self.interstitial.isReady {
                self.interstitial.present(fromRootViewController: self)
            } else {
                self.loadBannerAd()
            }
        }
    }
    
    func interstitialDidDismissScreen(_ ad: GADInterstitial) {
        self.loadBannerAd()
        self.loadInterstitalAd()
    }
    
    func adViewDidReceiveAd(_ bannerView: GADBannerView) {
        
    }
    
    func adView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: GADRequestError) {
        print("adView:didFailToReceiveAdWithError: \(error.localizedDescription)")
    }
    
    func loadBannerAd(){
        if Defaults[.adsPurchased] == false {
            if let bannerId = self.appData?.value(forKey: "AdMobBannerUnitId") as? String {
                if !bannerId.isEmpty {
                    let bounds = UIScreen.main.bounds
                    
                    var y:CGFloat = bounds.height - 50
                    if self.appData?.value(forKey: "Toolbar") as? Bool == true {
                        y = y - self.toolbar!.frame.height
                    }
                    
                    self.bannerView = GADBannerView(adSize: kGADAdSizeBanner)
                    self.bannerView?.adUnitID = bannerId
                    self.bannerView?.rootViewController = self
                    self.bannerView?.load(self.request)
                    self.bannerView?.delegate = self
                }
            } else {
                self.bannerView?.removeFromSuperview()
                self.wkWebView?.frame = self.getFrame()
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.didFinish()
    }
    
    func didFinish() {
        self.backgroundImage?.removeFromSuperview()
        self.backgroundImage = nil
        self.activityIndicator.stopAnimating()
        
        UIView.transition(with: self.view, duration: 0.1, options: .transitionCrossDissolve, animations: {
            
            if let urlString = self.appData?.value(forKey: "URL") as? String {
                if !urlString.isEmpty {
                    if self.mainURL != URL(string: urlString) {
                        self.mainURL = URL(string: urlString)
                    }
                }
            }
            
            UserDefaults.standard.removeObject(forKey: "URL")
            
            if self.popViewController == nil {
                if self.wkWebView != nil {
                    self.view.addSubview(self.wkWebView!)
                    if self.appData?.value(forKey: "Toolbar") as? Bool == true {
                        self.toolbar.isHidden = false
                    }
                    self.wkWebView?.frame = self.getFrame()
                }
                if self.bannerView != nil {
                    self.view.addSubview(self.bannerView!)
                }
            }
            
        }) { (success) in
            self.load.hide(animated: true)
        }
    }
    
    func getViewController(_ configuration:WKWebViewConfiguration) -> UIViewController {
        let webView:WKWebView = WKWebView(frame: self.view.frame, configuration: configuration)
        webView.frame = UIScreen.main.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        let newViewController = UIViewController()
        newViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(ViewController.dismissViewController))
        newViewController.modalPresentationStyle = .overCurrentContext
        newViewController.view = webView
        return newViewController
    }
    
    func dismissPopViewController(_ domain:String) {
        if self.mainURL != nil {
            let mainDomain = self.getDomainFromURL(self.mainURL!)
            if domain == mainDomain{
                if self.popViewController != nil {
                    self.dismissViewController()
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        self.popViewController = self.getViewController(configuration)
        let navController = UINavigationController(rootViewController: self.popViewController!)
        self.present(navController, animated: true, completion: nil)
        return self.popViewController?.view as? WKWebView
    }
    
    @objc func dismissViewController() {
        self.dismiss(animated: true, completion: nil)
        self.load.hide(animated: true)
    }
    
    func userContentController(_ userContentController:WKUserContentController, message:WKScriptMessage) {
        print(message)
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        guard let command = body["command"] as? String else { return }
        guard let name = body["name"] as? String else { return }
        
        if command == "setUserProperty" {
            guard let value = body["value"] as? String else { return }
            Analytics.setUserProperty(value, forName: name)
        } else if command == "logEvent" {
            guard let params = body["parameters"] as? [String: NSObject] else { return }
            Analytics.logEvent(name, parameters: params)
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.showLoader()
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // You can inject java script here if required as below
        //        let javascript = "var meta = document.createElement('meta');meta.setAttribute('name', 'viewport');meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');document.getElementsByTagName('head')[0].appendChild(meta);";
        //        self.wkWebView.evaluateJavaScript(javascript, completionHandler: nil)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
            completionHandler()
        }))
        present(alertController, animated: true, completion: nil)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
            completionHandler(true)
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
            completionHandler(false)
        }))
        present(alertController, animated: true, completion: nil)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alertController = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.text = defaultText
        }
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
            if let text = alertController.textFields?.first?.text {
                completionHandler(text)
            } else {
                completionHandler(defaultText)
            }
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
            completionHandler(nil)
        }))
        present(alertController, animated: true, completion: nil)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        var fileURL = URL(fileURLWithPath: Bundle.main.path(forResource: "NoInternet", ofType: "html")!)
        if #available(iOS 9.0, *) {
            _ = self.wkWebView?.loadFileURL(fileURL, allowingReadAccessTo: fileURL)
        } else {
            do {
                fileURL = try fileURLForBuggyWKWebView8(fileURL: fileURL)
                if self.appData?.value(forKey: "EnableWebViewCache") as? Bool == true {
                    _ = self.wkWebView?.load(URLRequest(url: fileURL))
                } else {
                    _ = self.wkWebView?.load(URLRequest(url: fileURL, cachePolicy: .reloadIgnoringLocalCacheData))
                }
            } catch let error as NSError {
                print("Error: " + error.debugDescription)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let domain = self.getDomainFromURL(webView.url)
        self.dismissPopViewController(domain)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        print("NAVIGATION URL: \(String(describing: navigationAction.request.url!.host))")
        
        if let url = navigationAction.request.url {
            let hostAddress = url.host
            // To connnect app store
            if hostAddress == "itunes.apple.com" {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.openURL(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            
            #if DEBUG
                print("url = \(url), host = \(hostAddress)")
            #endif
            
            if let url_elements = navigationAction.request.url?.absoluteString.components(separatedBy: ":") {
                switch url_elements[0] {
                case "itms-services":
                    if UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.openURL(url)
                    }
                    decisionHandler(.cancel)
                    return
                case "tel":
                    #if DEBUG
                        print("this is phone number")
                    #endif
                    openCustomApp(urlScheme: "telprompt://", additional_info: url_elements[1])
                    decisionHandler(.cancel)
                    return
                case "sms":
                    #if DEBUG
                        print("this is sms")
                    #endif
                    openCustomApp(urlScheme: "sms://", additional_info: url_elements[1])
                    decisionHandler(.cancel)
                    return
                case "mailto":
                    #if DEBUG
                        print("this is mail")
                    #endif
                    openCustomApp(urlScheme: "mailto://", additional_info: url_elements[1])
                    decisionHandler(.cancel)
                    return
                case "comgooglemaps":
                    #if DEBUG
                        print("this is sms")
                    #endif
                    openCustomApp(urlScheme: "comgooglemaps://", additional_info: url_elements[1])
                    decisionHandler(.cancel)
                    return
                case "whatsapp":
                    #if DEBUG
                        print("this is whatsapp")
                    #endif
                    openCustomApp(urlScheme: "whatsapp://", additional_info: url_elements[1])
                    decisionHandler(.cancel)
                    return
                default:
                    #if DEBUG
                        print("normal http request")
                    #endif
                }
            }
            
            let domain = self.getDomainFromURL(navigationAction.request.url!)
            if (navigationAction.navigationType == WKNavigationType.linkActivated) {
                print("domains: \(domain)")
                print("navigationType: LinkActivated")
                self.dismissPopViewController(domain)
                decisionHandler(WKNavigationActionPolicy.allow)
            } else if (navigationAction.navigationType == WKNavigationType.backForward) {
                print("navigationType: BackForward")
                decisionHandler(WKNavigationActionPolicy.allow)
            } else if (navigationAction.navigationType == WKNavigationType.formResubmitted) {
                print("navigationType: FormResubmitted")
                decisionHandler(WKNavigationActionPolicy.allow)
            } else if (navigationAction.navigationType == WKNavigationType.formSubmitted) {
                print("navigationType: FormSubmitted")
                self.dismissPopViewController(domain)
                decisionHandler(WKNavigationActionPolicy.allow)
            } else if (navigationAction.navigationType == WKNavigationType.reload) {
                print("navigationType: Reload")
                decisionHandler(WKNavigationActionPolicy.allow)
            } else {
                self.dismissPopViewController(domain)
                decisionHandler(WKNavigationActionPolicy.allow)
            }
        }
    }
    
    /**
     open custom app with urlScheme : telprompt, sms, mailto
     
     - parameter urlScheme: telpromt, sms, mailto
     - parameter additional_info: additional info related to urlScheme
     */
    func openCustomApp(urlScheme:String, additional_info:String){
        let url = "\(urlScheme)"+"\(additional_info)"
        if let requestUrl:NSURL = NSURL(string:url) {
            let application:UIApplication = UIApplication.shared
            if application.canOpenURL(requestUrl as URL) {
                application.openURL(requestUrl as URL)
            }
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow);
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.load.hide(animated: true)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func willRotate(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        UIView.transition(with: self.view, duration: 0.1, options: .transitionCrossDissolve, animations: {
            for view in self.view.subviews {
                if view is GADBannerView {
                    view.removeFromSuperview()
                }
            }
            self.loadBannerAd()
        }) { (success) in
            
        }
    }
    
    override func didRotate(from fromInterfaceOrientation: UIInterfaceOrientation) {
        UIView.transition(with: self.view, duration: 0.1, options: .transitionCrossDissolve, animations: {
            let bounds = UIScreen.main.bounds
//            self.toolbar?.frame = CGRect(x: 0, y: bounds.height - 40, width: bounds.width, height: 40)
            
            var y:CGFloat = bounds.height - 50
            if self.toolbar.isHidden == false {
                y = y - self.toolbar!.frame.height
            }
            
            self.bannerView?.frame = CGRect(x: (bounds.width - 320) / 2, y: y, width: 320, height: 50)
            self.wkWebView?.frame = self.getFrame()
        }) { (success) in
            
        }
    }
    
    func getFrame() -> CGRect {
        let bounds = UIScreen.main.bounds
        
        var height:CGFloat = bounds.height
        if self.toolbar.isHidden == false {
            height -= self.toolbar!.frame.height
            var safeAreaBottom:CGFloat = 0
            if #available(iOS 11.0, *) {
                safeAreaBottom = (UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0)!
                height -= safeAreaBottom
            }
        }
        
        return  CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }
    
    @objc @IBAction func removeAdsAction() {
        if let productId = self.appData?.value(forKey: "RemoveAdsPurchaseId") as? String {
            if !productId.isEmpty {
                SwiftyStoreKit.retrieveProductsInfo([productId]) { result in
                    if let product = result.retrievedProducts.first {
                        let numberFormatter = NumberFormatter()
                        numberFormatter.locale = product.priceLocale
                        numberFormatter.numberStyle = .currency
                        let priceString = numberFormatter.string(from: product.price)
                        print("Product: \(product.localizedDescription), price: \(String(describing: priceString))")
                        
                        let alert = UIAlertController(title: "In-App Purchase", message: "Do you want to purchase Remove Ads for \(priceString!)", preferredStyle: UIAlertControllerStyle.alert)
                        alert.addAction(UIAlertAction(title: "Remove Ads", style: .default, handler: { (action: UIAlertAction!) in
                            self.purchase()
                        }))
                        alert.addAction(UIAlertAction(title: "Restore", style: .default, handler: { (action: UIAlertAction!) in
                            self.restorePurchases()
                        }))
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in
                            
                        }))
                        self.present(alert, animated: true, completion: nil)
                        
                    } else {
                        print("Error: \(String(describing: result.error))")
                        
                        let alert = UIAlertController(title: "In-App Purchase", message: "Product not found", preferredStyle: UIAlertControllerStyle.alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
                            
                        }))
                        self.present(alert, animated: true, completion: nil)
                    }
                }
            }
        }
    }
    
    func restorePurchases() {
        if let productId = self.appData?.value(forKey: "RemoveAdsPurchaseId") as? String {
            SwiftyStoreKit.restorePurchases() { results in
                if results.restoreFailedPurchases.count > 0 {
                    print("Restore Failed: \(results.restoreFailedPurchases)")
                    let alert = UIAlertController(title: "In-App Purchase", message: "Restore Failed", preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                } else if results.restoredPurchases.count > 0 {
                    print("Restore Success: \(results.restoredPurchases)")
                    
                    for restoredProduct in results.restoredPurchases{
                        if restoredProduct.productId == productId {
                            self.removeAds()
                            let alert = UIAlertController(title: "In-App Purchase", message: "Restore successful!", preferredStyle: UIAlertControllerStyle.alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                            break
                        }
                    }
                } else {
                    print("Nothing to Restore")
                    let alert = UIAlertController(title: "In-App Purchase", message: "Nothing to Restore", preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
    }
    
    func purchase() {
        if let productId = self.appData?.value(forKey: "RemoveAdsPurchaseId") as? String {
            if !productId.isEmpty {
                SwiftyStoreKit.purchaseProduct(productId) { result in
                    switch result {
                    case .success(let productId):
                        print("Purchase Success: \(productId)")
                        
                        Defaults[.adsPurchased] = true
                        self.timer?.invalidate()
                        self.timer = nil
                        
                        let alert = UIAlertController(title: "In-App Purchase", message: "Purchase successful!", preferredStyle: UIAlertControllerStyle.alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
                            self.removeAds()
                        }))
                        self.present(alert, animated: true, completion: nil)
                        
                    case .error(let error):
                        print("Purchase Failed: \(error)")
                        let alert = UIAlertController(title: "In-App Purchase", message: "Purchase Failed", preferredStyle: UIAlertControllerStyle.alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
                            
                        }))
                        self.present(alert, animated: true, completion: nil)
                    }
                }
            }
        }
    }
    
    func getDomainFromURL(_ url:URL?) -> String {
        var domain:String = ""
        let domains = self.domains()
        if url?.host != nil {
            let host = url!.host?.lowercased()
            var separatedHost = host?.components(separatedBy: ".")
            separatedHost = separatedHost?.reversed()
            
            for tld in separatedHost! {
                if domains.contains(tld.uppercased()) {
                    domain = ".\(tld)\(domain)"
                } else {
                    domain = "\(tld)\(domain)"
                    break
                }
            }
        }
        return domain
    }
    
    func removeAds() {
        Defaults[.adsPurchased] = true
        
        self.timer?.invalidate()
        self.timer = nil
        
        UIView.transition(with: self.view, duration: 0.3, options: .transitionCrossDissolve, animations: {
            for view in self.view.subviews {
                if view is GADBannerView {
                    view.removeFromSuperview()
                }
            }
            
            if self.toolbar.isHidden == false {
                var buttons = self.toolbar!.items!
                for button in self.toolbar!.items! {
                    if button == self.iapButton {
                        buttons.remove(at: buttons.index(of: button)!)
                        self.toolbar?.setItems(buttons, animated: true)
                    }
                }
            }
            
            self.wkWebView?.frame = self.getFrame()
        }) { (success) in
            
        }
    }
    
    func domains() -> NSArray {
        if let url = Bundle.main.url(forResource: "domains", withExtension: "json") {
            if let data = try? Data(contentsOf: url) {
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                    if let domains = json as? [String] {
                        return domains as NSArray
                    }
                } catch {
                    print("error serializing JSON: \(error)")
                }
            }
            print("Error!! Unable to load domains.json.json")
        }
        return []
    }
    
    //Commented:    black status bar.
    //Uncommented:  white status bar.
    override var preferredStatusBarStyle : UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }
    
    // MARK: LocationService Delegate
    func tracingLocation(_ currentLocation: CLLocation) {
        let latitude = currentLocation.coordinate.latitude
        let longitude = currentLocation.coordinate.longitude
        
        self.wkWebView?.bridge.post(action: "gps_location", parameters: ["latitude": latitude, "longitude": longitude])
    }
    
    func tracingLocationDidFailWithError(_ error: NSError) {
        print("tracing Location Error : \(error.description)")
    }
    
    deinit {
        self.wkWebView?.removeObserver(self, forKeyPath: "loading")
        self.wkWebView?.removeObserver(self, forKeyPath: "estimatedProgress")
        self.wkWebView?.removeBridge()

    }
}

