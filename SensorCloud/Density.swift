//
//  Density.swift
//  SensorCloud
//
//  Created by Darko on 2018/4/13.
//  Copyright © 2018年 Darko. All rights reserved.
//

import Foundation


struct SensorDensity {
    let pm2_5: Float
    let pm10: Float
}

struct DensityFrame {
    let points: [SensorDensity]
    let length: Int
}
//
struct DensityAnimation {
    let frames: [DensityFrame]
    let length: Int
}

enum DensityDelimiter {
    static let Frame = "XY"
    static let Point = ","
}

open class Density {
    
//    fileprivate var animation: XYZAnimation!
    fileprivate var sensorDensity: DensityAnimation!
    
    func measureOperation(_ description: String, operation: (() -> Void)?) {
        
        let began = Date()
        
        if let operation = operation {
            operation()
        }
        
        print("\(description): \(Float(Int(Date().timeIntervalSince(began) * 100)) / 100)s")
    }
    
    init(fromFile file: String) {
        
        measureOperation("Sensor Density Parsing") { () -> Void in
            do {
                let fileContent = try String(contentsOfFile: file)
//                self.animation = self.parseAnimation(fromFileContent: fileContent)
                self.sensorDensity = self.parseDensity(fromFileContent: fileContent)
            } catch {
                assertionFailure("Could not parse file content\(error)")
            }
        }
    }
    
    func parseDensity(fromFileContent fileContent: String) -> DensityAnimation {
        
//        let frames = fileContent.components(separatedBy: XYZDelimiter.Frame).map ({ (frame) -> XYZFrame in
//            var points: [XYZPoint] = []
//            frame.trimmingCharacters(in: CharacterSet.newlines).enumerateLines(invoking: { (line, stop) in
//                let values = line.components(separatedBy: CharacterSet(charactersIn: XYZDelimiter.Point))
//
//                if let x = Float(values[0]), let y = Float(values[1]), let z = Float(values[2]) {
//                    points.append(XYZPoint(x: Float(Int(x * 100)) / 3000,
//                                           y: Float(Int(y * 100)) / 2000,
//                                           z: Float(Int(z * 100)) / 2000))
//                }
//
//                if points.count >= 4_096 {
//                    stop = true
//                }
//            })
//
//            return XYZFrame(points: points, length: points.count)
//        })
//
//        return XYZAnimation(frames: frames, length: frames.count)
        
        let densities = fileContent.components(separatedBy: DensityDelimiter.Frame).map { (density) -> DensityFrame in
            var points: [SensorDensity] = []
            density.trimmingCharacters(in: CharacterSet.newlines).enumerateLines(invoking: { (line, stop) in
                let values = line.components(separatedBy: CharacterSet(charactersIn: DensityDelimiter.Point))
                
                if let x = Float(values[0]), let y = Float(values[1]) {
                    points.append(SensorDensity(pm2_5: x * 100 / 3000, pm10: y * 100 / 2000))
                }
                
                if points.count >= 4_096 {
                    stop = true
                }
            })
            
            return DensityFrame(points: points, length: points.count)
        }
        
        return DensityAnimation(frames: densities, length: densities.count)
    }
    
    func x(frameIndex: Int, pointIndex: Int) -> Float {
        return sensorDensity.frames[frameIndex].points[pointIndex].pm2_5
    }
    
    func y(frameIndex: Int, pointIndex: Int) -> Float {
        return sensorDensity.frames[frameIndex].points[pointIndex].pm10
    }
    
//    func z(frameIndex: Int, pointIndex: Int) -> Float {
//        return animation.frames[frameIndex].points[pointIndex].z
//    }
    
    func density(frameIndex: Int, pointIndex: Int) -> SensorDensity {
        return sensorDensity.frames[frameIndex].points[pointIndex]
    }
}

