//
//  LiveView.swift
//  AirWink
//
//  Created by yuki on 2015/08/27.
//  Copyright (c) 2015年 higegiraffe. All rights reserved.
//

import UIKit
import AVFoundation

class LiveView: UIViewController , OLYCameraLiveViewDelegate , OLYCameraRecordingSupportsDelegate , AVCaptureVideoDataOutputSampleBufferDelegate{
    @IBOutlet weak var liveViewImage: UIImageView!
    
    //顔認識用のsecretView
    var secretView: UIImageView!
    
    //顔認識関連の定義
    var onlyFireNotificatonOnStatusChange : Bool = true
    var RightEyeClosedCount = 0
    var leftEyeClosed : Bool?
    var rightEyeClosed : Bool?
    var isWinking : Bool?
    var isBlinking : Bool?
    var faceDetected : Bool?
    
    let notificationCenter : NSNotificationCenter = NSNotificationCenter.defaultCenter()
    let LeftEyeClosedNotification = NSNotification(name: "LeftEyeClosedNotification", object: nil)
    let RightEyeClosedNotification = NSNotification(name: "RightEyeClosedNotification", object: nil)
    let LeftEyeOpenNotification = NSNotification(name: "LeftEyeOpenNotification", object: nil)
    let RightEyeOpenNotification = NSNotification(name: "RightEyeOpenNotification", object: nil)
    let WinkingNotification = NSNotification(name: "WinkingNotification", object: nil)
    let NotWinkingNotification = NSNotification(name: "NotWinkingNotification", object: nil)
    let BlinkingNotification = NSNotification(name: "BlinkingNotification", object: nil)
    let NotBlinkingNotification = NSNotification(name: "NotBlinkingNotification", object: nil)
    let NoFaceDetectedNotification = NSNotification(name: "NoFaceDetectedNotification", object: nil)
    let FaceDetectedNotification = NSNotification(name: "FaceDetectedNotification", object: nil)
    
    let emojiLabel : UILabel = UILabel(frame: UIScreen.mainScreen().bounds)
    
    var orientation = 0
    
    //AppDelegate instance
    var appDelegate: AppDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        //Notification Regist
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "NotificationApplicationBackground:", name: UIApplicationDidEnterBackgroundNotification , object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "NotificationCameraKitDisconnect:", name: appDelegate.NotificationCameraKitDisconnect as String, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "NotificationRechabilityDisconnect:", name: appDelegate.NotificationNetworkDisconnected as String, object: nil)
        
        let camera = AppDelegate.sharedCamera
        camera.liveViewDelegate = self
        camera.recordingSupportsDelegate = self
        
        camera.connect(OLYCameraConnectionTypeWiFi, error: nil)
        
        if (camera.connected) {
            camera.changeRunMode(OLYCameraRunModeRecording, error: nil)
            camera.changeLiveViewSize(OLYCameraLiveViewSizeXGA, error: nil)
            camera.setCameraPropertyValue("TAKEMODE", value: "<TAKEMODE/P>", error: nil)
            
            //顔認識関連の関数
            detectFaces()
            
            //顔認識の状態表示
            emojiLabel.text = "💤"
            emojiLabel.font = UIFont.systemFontOfSize(50)
            emojiLabel.textAlignment = .Left
            self.view.addSubview(emojiLabel)
            
            
            //顔認識表示の処理
            NSNotificationCenter.defaultCenter().addObserverForName("FaceDetectedNotification", object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: { notification in
                //顔認識の状態表示
                self.emojiLabel.text = "😊"
            })
            //非顔認識表示の処理
            NSNotificationCenter.defaultCenter().addObserverForName("NoFaceDetectedNotification", object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: { notification in
                self.emojiLabel.text = "💤"
            })
            
            //RightEyeClosedNotification通知時の処理
            NSNotificationCenter.defaultCenter().addObserverForName("RightEyeClosedNotification", object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: { notification in
                //RightEyeClosedNotificationの通知回数カウント
                self.RightEyeClosedCount++   //self.LeftEyeClosedCount + 1
                println(self.RightEyeClosedCount)
                
                //ウインクでレリーズ
                //通知3回来るとレリーズ
                if (self.RightEyeClosedCount == 3) {
                    println("faceDetected =")
                    println(self.faceDetected)
                    println("isWinking =")
                    println(self.isWinking)
                    
                    let camera = AppDelegate.sharedCamera
                    println("takePicture")
                    camera.takePicture(nil, progressHandler: nil, completionHandler: nil, errorHandler: nil)
                }
            })
            
            //RightEyeOpenNotification通知時の処理
            NSNotificationCenter.defaultCenter().addObserverForName("RightEyeOpenNotification", object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: { notification in
                //RightEyeClosedNotificationの通知回数カウントのリセット
                self.RightEyeClosedCount = 0
                println(self.RightEyeClosedCount)
            })
            
            
            //let inquire = camera.inquireHardwareInformation(nil) as NSDictionary
            //let modelname = inquire.objectForKey(OLYCameraHardwareInformationCameraModelNameKey) as? String
            //let version = inquire.objectForKey(OLYCameraHardwareInformationCameraFirmwareVersionKey) as? String
            //infomation.text = modelname! + " Ver." + version!
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        let camera = AppDelegate.sharedCamera
        
        camera.disconnectWithPowerOff(false, error: nil)
        
        //カメラの停止とメモリ解放
        self.mySession.stopRunning()
        for output in self.mySession.outputs {
            self.mySession.removeOutput(output as! AVCaptureOutput)
        }
        for input in self.mySession.inputs {
            self.mySession.removeInput(input as! AVCaptureInput)
        }
        self.mySession = nil
        
    }
    
    // セッション
    var mySession : AVCaptureSession!
    // カメラデバイス
    var myDevice : AVCaptureDevice!
    // 出力先
    var myOutput : AVCaptureVideoDataOutput!
    
    func detectFaces() {
        var q_global: dispatch_queue_t = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        var q_main: dispatch_queue_t  = dispatch_get_main_queue()
        
        dispatch_async(q_global, {
            //secretViewの生成
            self.initDisplay()
            
            // カメラを準備
            if self.initCamera() {
                
                // 撮影開始
                self.mySession.startRunning()
            }
        })
        
    }
    
    // secretViewの生成処理
    func initDisplay() {
        //スクリーンの幅
        let screenWidth = UIScreen.mainScreen().bounds.size.width;
        //スクリーンの高さ
        let screenHeight = UIScreen.mainScreen().bounds.size.height;
        
        secretView = UIImageView(frame: CGRectMake(0.0, 0.0, screenWidth, screenHeight))
        
    }
    
    // カメラの準備処理
    func initCamera() -> Bool {
        // セッションの作成.
        mySession = AVCaptureSession()
        
        // 解像度の指定.
        mySession.sessionPreset = AVCaptureSessionPresetMedium
        
        
        // デバイス一覧の取得.
        let devices = AVCaptureDevice.devices()
        
        // フロントカメラをmyDeviceに格納.
        for device in devices {
            if(device.position == AVCaptureDevicePosition.Front){
                myDevice = device as! AVCaptureDevice
            }
        }
        if myDevice == nil {
            return false
        }
        
        // フロントカメラからVideoInputを取得.
        let myInput = AVCaptureDeviceInput.deviceInputWithDevice(myDevice, error: nil) as! AVCaptureDeviceInput
        
        
        // セッションに追加.
        if mySession.canAddInput(myInput) {
            mySession.addInput(myInput)
        } else {
            return false
        }
        
        // 出力先を設定
        myOutput = AVCaptureVideoDataOutput()
        myOutput.videoSettings = [ kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA ]
        
        // FPSを設定
        var lockError: NSError?
        if myDevice.lockForConfiguration(&lockError) {
            if let error = lockError {
                println("lock error: \(error.localizedDescription)")
                return false
            } else {
                myDevice.activeVideoMinFrameDuration = CMTimeMake(1, 10)
                myDevice.unlockForConfiguration()
            }
        }
        
        // デリゲートを設定
        let facequeue: dispatch_queue_t = dispatch_queue_create("myqueue",  nil)
        myOutput.setSampleBufferDelegate(self, queue: facequeue)
        
        
        
        // 遅れてきたフレームは無視する
        myOutput.alwaysDiscardsLateVideoFrames = true
        
        
        // セッションに追加.
        if mySession.canAddOutput(myOutput) {
            mySession.addOutput(myOutput)
        } else {
            return false
        }
        
        // カメラの向きを合わせる
        if (UIDeviceOrientationIsLandscape(UIDevice.currentDevice().orientation)) {
            println("landscape")
        }
        if (UIDeviceOrientationIsPortrait(UIDevice.currentDevice().orientation)) {
            println("Portrait")
        }
        println("DeviceOrientation")
        println(UIDevice.currentDevice().orientation)
        
        for connection in myOutput.connections {
            if let conn = connection as? AVCaptureConnection {
                if conn.supportsVideoOrientation {
                    switch(UIDevice.currentDevice().orientation) {
                    case UIDeviceOrientation.Portrait:
                        println("Portrait")
                        orientation = 2
                        conn.videoOrientation = AVCaptureVideoOrientation.Portrait
                    case UIDeviceOrientation.PortraitUpsideDown:
                        println("PortraitUpsideDown")
                        orientation = 4
                        conn.videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
                    case UIDeviceOrientation.LandscapeLeft:
                        println("LandscapeLeft")
                        orientation = 7
                        //conn.videoOrientation = AVCaptureVideoOrientation.LandscapeLeft
                        conn.videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
                    case UIDeviceOrientation.LandscapeRight:
                        println("LandscapeRight")
                        orientation = 5
                        //conn.videoOrientation = AVCaptureVideoOrientation.LandscapeRight
                        conn.videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
                    default:
                        break
                    }
                    println("conn.videoOrientation")
                    println(conn.videoOrientation)
                }
            }
        }
        return true
    }
    
    // 毎フレーム実行される処理
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
        // UIImageへ変換
        let image = CameraUtil.imageFromSampleBuffer(sampleBuffer)
        
        // 顔認識
        let detectFace = detector.recognizeFace(image,orientation: orientation)
        
        // 検出された顔のデータをCIFaceFeatureで処理
        if (detectFace.faces.count != 0) { //顔認識ある場合
            println("count =",detectFace.faces.count)
            if (self.onlyFireNotificatonOnStatusChange == true) {
                if (self.faceDetected == false) {
                    self.notificationCenter.postNotification(self.FaceDetectedNotification)
                }
            } else {
                self.notificationCenter.postNotification(self.FaceDetectedNotification)
            }
            self.faceDetected = true
            println("faceDetected true")
            
            for feature in detectFace.faces as! [CIFaceFeature] {
                var faceBounds : CGRect = feature.bounds
                if (feature.hasLeftEyePosition) {
                    var leftEyePosition : CGPoint = feature.leftEyePosition
                }
                
                if (feature.hasRightEyePosition) {
                    var rightEyePosition : CGPoint = feature.rightEyePosition
                }
                
                if (feature.hasMouthPosition) {
                    var mouthPosition : CGPoint = feature.mouthPosition
                }
                
                if ((feature.leftEyeClosed == true) || (feature.rightEyeClosed == true)) { //目閉じがある場合
                    println("feature.leftEyeClosed =")
                    println(feature.leftEyeClosed)
                    println("feature.rightEyeClosed =")
                    println(feature.rightEyeClosed)
                    
                    if (self.onlyFireNotificatonOnStatusChange == true) {
                        if (self.isWinking == false) {
                            self.notificationCenter.postNotification(self.WinkingNotification)
                        }
                    } else {
                        self.notificationCenter.postNotification(self.WinkingNotification)
                    }
                    self.isWinking = true
                    println("isWinking = true")
                    
                    if (feature.leftEyeClosed == true) {
                        if (self.onlyFireNotificatonOnStatusChange == true) {
                            if (self.leftEyeClosed == false) {
                                self.notificationCenter.postNotification(self.LeftEyeClosedNotification)
                            } else {
                                self.notificationCenter.postNotification(self.LeftEyeClosedNotification)
                            }
                        } else {
                            self.notificationCenter.postNotification(self.LeftEyeClosedNotification)
                        }
                        self.leftEyeClosed = true
                        println("leftEyeClosed = true")
                    } else {
                        self.leftEyeClosed = false
                        println("leftEyeClosed = false")
                        self.notificationCenter.postNotification(self.LeftEyeOpenNotification)
                    }
                    
                    if (feature.rightEyeClosed == true) {
                        if (self.onlyFireNotificatonOnStatusChange == true) {
                            if (self.rightEyeClosed == false) {
                                self.notificationCenter.postNotification(self.RightEyeClosedNotification)
                            } else {
                                self.notificationCenter.postNotification(self.RightEyeClosedNotification)
                            }
                        } else {
                            self.notificationCenter.postNotification(self.RightEyeClosedNotification)
                        }
                        self.rightEyeClosed = true
                        println("rightEyeClosed = true")
                    } else {
                        self.rightEyeClosed = false
                        println("rightEyeClosed = false")
                        self.notificationCenter.postNotification(self.RightEyeOpenNotification)
                    }
                    
                    if ((feature.leftEyeClosed == true) && (feature.rightEyeClosed == true)) {
                        if (self.onlyFireNotificatonOnStatusChange == true) {
                            if (self.isBlinking == false) {
                                self.notificationCenter.postNotification(self.BlinkingNotification)
                            }
                        } else {
                            self.notificationCenter.postNotification(self.BlinkingNotification)
                        }
                        self.isBlinking = true
                        println("isBlinking = true")
                    }
                } else { //目閉じがない場合
                    if (self.onlyFireNotificatonOnStatusChange == true) {
                        if (self.isBlinking == true) {
                            self.notificationCenter.postNotification(self.NotBlinkingNotification)
                        }
                        if (self.isWinking == true) {
                            self.notificationCenter.postNotification(self.NotWinkingNotification)
                        }
                        if (self.rightEyeClosed == true) {
                            self.notificationCenter.postNotification(self.RightEyeOpenNotification)
                        }
                        if (self.leftEyeClosed == true) {
                            self.notificationCenter.postNotification(self.LeftEyeOpenNotification)
                        }
                    } else {
                        self.notificationCenter.postNotification(self.NotBlinkingNotification)
                        self.notificationCenter.postNotification(self.NotWinkingNotification)
                        self.notificationCenter.postNotification(self.LeftEyeOpenNotification)
                        self.notificationCenter.postNotification(self.RightEyeOpenNotification)
                    }
                    self.isBlinking = false
                    self.isWinking = false
                    self.leftEyeClosed = false
                    self.rightEyeClosed = false
                    println("isBlinking = false")
                    println("isWinking = false")
                    println("leftEyeClosed = false")
                    println("rightEyeClosed = false")
                    
                }
            }
        } else { //顔認識ない場合
            println("count =",detectFace.faces.count)
            if (self.onlyFireNotificatonOnStatusChange == true) {
                if (self.faceDetected == true) {
                    self.notificationCenter.postNotification(self.NoFaceDetectedNotification)
                }
            } else {
                self.notificationCenter.postNotification(self.NoFaceDetectedNotification)
            }
            self.faceDetected = false
            self.isBlinking = false
            self.isWinking = false
            self.leftEyeClosed = false
            self.rightEyeClosed = false
            println("isBlinking = false")
            println("isWinking = false")
            println("leftEyeClosed = false")
            println("rightEyeClosed = false")
            
        }
    }
    
    //デバイスの向きが変わった時
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        println("viewWillTransitionToSize")
        var q_global: dispatch_queue_t = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        var q_main: dispatch_queue_t  = dispatch_get_main_queue()
        
        dispatch_async(q_global, {
            //カメラの停止とメモリ解放
            self.mySession.stopRunning()
            for output in self.mySession.outputs {
                self.mySession.removeOutput(output as! AVCaptureOutput)
            }
            for input in self.mySession.inputs {
                self.mySession.removeInput(input as! AVCaptureInput)
            }
            self.mySession = nil
            println("カメラの停止とメモリ解放")
            // カメラを準備
            self.initCamera()
            println("initCamera")
            // 撮影開始
            self.mySession.startRunning()
            
        })
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        
    }
    
    // MARK: - Button Action
/*    @IBAction func shutterButtonAction(sender: AnyObject) {
        let camera = AppDelegate.sharedCamera
        
        camera.takePicture(nil, progressHandler: nil, completionHandler: nil, errorHandler: nil)
    }
*/
    // MARK: - 露出補正
/*    @IBAction func exprevSlider(sender: AnyObject) {
        let slider = sender as! UISlider
        let index = Int(slider.value + 0.5)
        slider.value = Float(index)
        
        var value = NSString(format: "%+0.1f" , slider.value)
        if (slider.value == 0) {
            value = NSString(format: "%0.1f" , slider.value)
        }
        
        let camera = AppDelegate.sharedCamera
        
        camera.setCameraPropertyValue("EXPREV", value: "<EXPREV/" + (value as String) + ">", error: nil)
        
    }
*/

    // MARK: - LiveView Update
    func camera(camera: OLYCamera!, didUpdateLiveView data: NSData!, metadata: [NSObject : AnyObject]!) {
        let image : UIImage = OLYCameraConvertDataToImage(data,metadata)
        self.liveViewImage.image = image
    }
    
    // MARK: - Recview
/*    func camera(camera: OLYCamera!, didReceiveCapturedImagePreview data: NSData!, metadata: [NSObject : AnyObject]!) {
        let image : UIImage = OLYCameraConvertDataToImage(data,metadata)
        recviewImage.image = image
    }
*/
    
    // MARK: - Notification
    func NotificationApplicationBackground(notification : NSNotification?) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    func NotificationCameraKitDisconnect(notification : NSNotification?) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    func NotificationRechabilityDisconnect(notification : NSNotification?) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }
}