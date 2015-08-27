//
//  detector.swift
//  RecCameraSwift
//
//  Created by yuki on 2015/08/09.
//  Copyright (c) 2015年 FromF. All rights reserved.
//

import UIKit
import CoreImage

var DeviceOrientation: UIDeviceOrientation = UIDevice.currentDevice().orientation

class detector {
    class func recognizeFace(image: UIImage,orientation: Int) -> (faces: NSArray , transform: CGAffineTransform) {
    
        println("detctor orientation")
        println(orientation)
        
        // NSDictionary型のoptionを生成。顔認識の精度を追加する.
        var options : NSDictionary = [CIDetectorSmile : true, CIDetectorEyeBlink : true, CIDetectorImageOrientation :orientation]
        //var options : NSDictionary = [CIDetectorSmile : true, CIDetectorEyeBlink : true]
        
        // CIDetectorを生成。顔認識をするのでTypeはCIDetectorTypeFace.
        let detector : CIDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        
        var outputImage :CIImage = CIImage(image: image)
        
        // detectorで認識した顔のデータを入れておくNSArray.
        var faces : NSArray = detector.featuresInImage(outputImage, options: options as [NSObject : AnyObject]) as! [CIFeature]
        
        // UIKitは画面左上に原点があるが、CoreImageは画面左下に原点があるのでそれを揃えなくてはならない.
        // CoreImageとUIKitの原点を画面左上に統一する処理.
        var transform : CGAffineTransform = CGAffineTransformMakeScale(1, -1)
        //       transform = CGAffineTransformTranslate(transform, 0, -self.imageView.bounds.size.height)
        transform = CGAffineTransformTranslate(transform, 0, -UIScreen.mainScreen().bounds.size.height)
        
        return (faces,transform)
        
    }
    
}
