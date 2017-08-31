# Uncomment this line to define a global platform for your project
# platform :ios, '9.0'

target 'SuperView' do
	use_frameworks!

	pod 'MBProgressHUD', '~> 1.0.0'
    pod 'Firebase/Core'
    pod 'Firebase/AdMob'
    pod 'Firebase/Messaging'
    pod 'OneSignal'
    pod 'SwiftyUserDefaults'
    pod 'SwiftyStoreKit'
    pod 'WKBridge'
end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['SWIFT_VERSION'] = '3.0'
        end
    end
end
