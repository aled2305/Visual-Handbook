//
//  AppDelegate.swift
//  UniversalWebview
//
//  Created by Mario Kovacevic on 05/08/2016.
//  Copyright (c) 2016 Brommko LLC. All rights reserved.
//

import UIKit
import Firebase
import SwiftyUserDefaults
import SwiftyStoreKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, FIRMessagingDelegate {
    
    var window: UIWindow?
    
    var googlePlistExists = false
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        let urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024, diskPath: nil)
        URLCache.shared = urlCache
        
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            googlePlistExists = true
        }
        
        if #available(iOS 10.0, *) {
            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current().requestAuthorization( options: authOptions, completionHandler: {_, _ in })
            // For iOS 10 display notification (sent via APNS)
            UNUserNotificationCenter.current().delegate = self
            
            if googlePlistExists == true {
                // For iOS 10 data message (sent via FCM)
                FIRMessaging.messaging().remoteMessageDelegate = self
            }
        } else {
            let settings: UIUserNotificationSettings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }
        
        if googlePlistExists == true {
            application.registerForRemoteNotifications()
            FIRApp.configure()
            NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.tokenRefreshNotification), name: NSNotification.Name.firInstanceIDTokenRefresh, object: nil)
        }
        
        let appData = NSDictionary(contentsOfFile: AppDelegate.dataPath())
        if let oneSignalAppID = appData?.value(forKey: "OneSignalAppID") as? String {
            if !oneSignalAppID.isEmpty {
                application.registerForRemoteNotifications()
                OneSignal.initWithLaunchOptions(launchOptions, appId: oneSignalAppID, handleNotificationAction: nil, settings:
                    [kOSSettingsKeyInAppAlerts: false,
                     kOSSettingsKeyAutoPrompt: false,
                     kOSSettingsKeyInAppLaunchURL: false
                    ])
                print("OneSignal registered!")
            }
        } else {
            print("OneSignal API Key is not in the plist file!")
        }
        
        if let productId = appData?.value(forKey: "RemoveAdsPurchaseId") as? String {
            if !productId.isEmpty {
                SwiftyStoreKit.completeTransactions() { completedTransactions in
                    for completedTransaction in completedTransactions {
                        if completedTransaction.transaction.transactionState == .purchased || completedTransaction.transaction.transactionState == .restored {
                            print("purchased: \(completedTransaction.productId)")
                            
                            if completedTransaction.productId == productId {
                                Defaults[.adsPurchased] = true
                            }
                        }
                    }
                }
            }
        }
        
        return true
    }
    
    func applicationReceivedRemoteMessage(_ remoteMessage: FIRMessagingRemoteMessage) {
        
    }
    
    func tokenRefreshNotification(_ notification: Notification) {
        let refreshedToken:String? = FIRInstanceID.instanceID().token()
        print("FOREBASE TOKEN: \(String(describing: refreshedToken))")
        FIRMessaging.messaging().connect { (error) in
            if (error != nil) {
                print("Unable to connect with FCM. \(String(describing: error))")
            } else {
                print("Connected to FCM.")
            }
        }
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        self.handleUserInfo(userInfo: userInfo)
    }
    
    func application(_ application: UIApplication, handleActionWithIdentifier identifier: String?, forRemoteNotification userInfo: [AnyHashable : Any], completionHandler: @escaping () -> Void) {
        self.handleUserInfo(userInfo: userInfo)
    }
    
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        self.handleUserInfo(userInfo: notification.request.content.userInfo)
        completionHandler([UNNotificationPresentationOptions.alert, UNNotificationPresentationOptions.sound, UNNotificationPresentationOptions.badge])
    }
    
    @available(iOS 10.0, *)
    private func userNotificationCenter(center: UNUserNotificationCenter, willPresentNotification notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        self.handleUserInfo(userInfo: notification.request.content.userInfo)
    }
    
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        self.handleUserInfo(userInfo: response.notification.request.content.userInfo)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        self.handleUserInfo(userInfo: userInfo)
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FIRInstanceID.instanceID().setAPNSToken(deviceToken, type: FIRInstanceIDAPNSTokenType.sandbox)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Couldn't register: \(error)")
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        if googlePlistExists == true {
            FIRMessaging.messaging().disconnect()
            print("Disconnected from FCM.")
        }
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        print("APPDELEGATE: open url \(url)")
        
        self.openURL(url: url)

        return true
    }
    
    func open(_ url: URL, options: [String : Any] = [:], completionHandler completion: ((Bool) -> Swift.Void)? = nil){
        print("APPDELEGATE: open url \(url) with completionHandler")
        
        self.openURL(url: url)

        completion?(true)
    }
    
    func application(_ application: UIApplication, handleOpen url: URL) -> Bool {
        self.openURL(url: url)
        return true
    }
    
    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        print("openURL \(url)")
        
        self.openURL(url: url)
        
        return true
    }
    
    func handleUserInfo(userInfo:[AnyHashable : Any]) {
        if let custom = userInfo["custom"] as? [AnyHashable : Any] {
            if let a = custom["a"] as? [AnyHashable : Any] {
                if let url = a["url"] as? String {
                    print("url: \(url)")
                    self.openURL(url: URL(string: url)!)
                }
            }
        }
    }
    
    func openURL(url:URL) {
        var urlString = url.absoluteString
        let urlSeperated = urlString.components(separatedBy: "//")
        var parsedURLString:String? = nil
        var host:String = "http"

        if urlSeperated.count > 1 {
            if urlSeperated.count > 2 {
                host = urlSeperated[1]
                urlString = urlSeperated[2]
            } else {
                urlString = urlSeperated[1]
            }
            parsedURLString = "\(host)://\(urlString)"
        } else {
            parsedURLString = "\(host)://\(urlString)"
        }
        
        if parsedURLString != nil {
            UserDefaults.standard.set(parsedURLString, forKey: "URL")
            
            if UIApplication.shared.applicationState == UIApplicationState.background || UIApplication.shared.applicationState == UIApplicationState.inactive {
                
            } else {
                if let window = self.window {
                    if let rootViewController = window.rootViewController {
                        if rootViewController is ViewController {
                            (rootViewController as! ViewController).loadWebView()
                        }
                    }
                }
            }

        }
    }
    
    static func dataPath() -> String {
        return Bundle.main.path(forResource: "SuperView", ofType: "plist")!
    }
}

