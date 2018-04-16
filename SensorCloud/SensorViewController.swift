//
//  SensorViewController.swift
//  SensorCloud
//
//  Created by Darko on 2018/2/7.
//  Copyright © 2018年 Darko. All rights reserved.
//

import UIKit
import Metal
import MetalKit


private let RADIUS = Float(0.7)
private var DELTA = Float(0.0000)
private let SOFTENING = Float(0.4)

struct ComputeParams {
    var numberOfObjects: UInt32 = 0
    var delta: Float = 0
    var softening: Float = 0
}

class SensorViewController: UIViewController {
    
//    var numberOfObjects = 4_096
    var numberOfObjects = 1600
    
    fileprivate var queue: MTLCommandQueue?
    fileprivate var library: MTLLibrary?
    fileprivate var computePipelineState: MTLComputePipelineState!
    fileprivate var renderPipelineState: MTLRenderPipelineState!
    fileprivate var buffer: MTLCommandBuffer?
    
    fileprivate var positionsIn: MTLBuffer?
    fileprivate var positionsOut: MTLBuffer?
    fileprivate var velocities: MTLBuffer?
    
    fileprivate var computeParams: MTLBuffer!
    fileprivate var renderParams: MTLBuffer!
    
    var xyz: XYZ?
    var metalKitView: MTKView? { return view as? MTKView }
    var camera: Camera?
    
    var lastFrameTime: TimeInterval = 0.0
    var kVelocityScale: CGFloat = 0.005
    var kRotationDamping: CGFloat = 0.98
    var angularVelocity: CGPoint = .zero
    var angle: CGPoint = .zero
    
    var xyzDensity: [XYZFrame] = []
    var sensorDensity: Density?
    var densityBuffer: MTLBuffer?
    
    
    override func loadView() {
        view = MTKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        metalKitView?.delegate = self
        camera = Camera()
        
        initializeMetal()
        initializePointCloud()
        
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(SensorViewController.panGestureRecognized(_:)))
        view.addGestureRecognizer(panGestureRecognizer)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(SensorViewController.tapGestureRecognized(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)
        
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: 40))
        label.font = UIFont.systemFont(ofSize: 15, weight: UIFont.Weight(rawValue: -0.5))
        label.text = "drag to rotate\ntap to play/pause"
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        view.addSubview(label)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 3, animations: {
                label.alpha = 0.0
            })
        }
    }
    
    @objc func panGestureRecognized(_ panGestureRecognizer: UIPanGestureRecognizer) {
        let velocity = panGestureRecognizer.velocity(in: panGestureRecognizer.view)
        angularVelocity = CGPoint(x: velocity.x * kVelocityScale, y: velocity.y * kVelocityScale)
    }
    
//    var animationTimer: Timer?
    var displayLink: CADisplayLink?
    
    var stop = false
    
    @objc func tapGestureRecognized(_ tapGestureRecognizer: UITapGestureRecognizer) {
        if DELTA == 0.0 && !stop {
            print("DELTA 0 tapped")
//            DELTA = Float(0.0003)
            stop = !stop

            self.displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
            self.displayLink?.preferredFramesPerSecond = 1
            self.displayLink?.add(to: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
            
        } else if DELTA != 0.0 || stop {
            print("DELTA 1 tapped")
            
            self.displayLink?.invalidate()
            self.displayLink = nil
            DELTA = Float(0.0)
            
            stop = !stop
        }
    }
    
    @objc func handleDisplayLink() {
        if DELTA == 0.0 {
            print("displayLink delta 0 tapped")
            DELTA = 0.0003
        } else {
            print("displayLink delta 1 tapped")
            DELTA = 0.0
        }
    }
    
    func initializePointCloud() {
        
        if let file1 = Bundle.main.path(forResource: "sensor1", ofType: "xyz"), let file2 = Bundle.main.path(forResource: "density", ofType: "xyz") {
            xyz = XYZ(fromFile: file1)
            sensorDensity = Density(fromFile: file2)
        }
        
        update()
    }
    
    func initComputePipelineState(_ device: MTLDevice) {
        
        do {
            if let compute = library?.makeFunction(name: "compute") {
                computePipelineState = try device.makeComputePipelineState(function: compute)
            }
        } catch {
            print("Failed to create compute pipeline state")
        }
    }
    
    func initRenderPipelineState(_ device: MTLDevice) {
        
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .half4
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        
        vertexDescriptor.layouts[0].stride = 12
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        vertexDescriptor.layouts[1].stride = 8
        vertexDescriptor.layouts[1].stepRate = 1
        vertexDescriptor.layouts[1].stepFunction = .perVertex
        
        let renderPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineStateDescriptor.label = "densityRenderPipeline"
        renderPipelineStateDescriptor.vertexFunction = library?.makeFunction(name: "vert")
        renderPipelineStateDescriptor.fragmentFunction = library?.makeFunction(name: "frag")
        renderPipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        renderPipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.one
        renderPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.one
        renderPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
        renderPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineStateDescriptor)
        } catch {
            print("Failed to create render pipeline state2")
        }
    }
    
    func initializeMetal() {
        
        metalKitView?.device = MTLCreateSystemDefaultDevice()
        guard let device = metalKitView?.device else { return }
        
        queue = device.makeCommandQueue()
        library = device.makeDefaultLibrary()
        
//        initComputePipelineState(device)
        initRenderPipelineState(device)
        
        let datasize = MemoryLayout<float4>.size * numberOfObjects
        print("datasize: \(datasize), MemoryLayout<float4>.size: \(MemoryLayout<float4>.size), MemoryLayout<float4>.stride: \(MemoryLayout<float4>.stride), MemoryLayout<float4>.alignment: \(MemoryLayout<float4>.alignment)")
        positionsIn = device.makeBuffer(length: datasize, options: .storageModeShared)
        positionsOut = device.makeBuffer(length: datasize, options: .storageModeShared)
        velocities = device.makeBuffer(length: datasize, options: .storageModeShared)
        densityBuffer = device.makeBuffer(length: datasize, options: MTLResourceOptions.storageModeShared)
    }
    
    func update() {
        
        guard let xyz = xyz else { return }
        guard let sensorDensity = sensorDensity else { return }
        
        buffer?.waitUntilCompleted()
        
        //        let _velocities = velocities!.contents().bindMemory(to: Float.self, capacity: )
        //        let positions = unsafeBitCast(positionsIn!.contents(), to: UnsafeMutablePointer<Float>.self)
        let positions = positionsIn!.contents().assumingMemoryBound(to: Float.self)
        let _velocities = unsafeBitCast(velocities!.contents(), to: UnsafeMutablePointer<Float>.self)
        let densities = densityBuffer!.contents().assumingMemoryBound(to: Float.self)
        
        for i in 0...(numberOfObjects - 1) {
            
            let scaleFactor: Float = 200.0
            let positionIndex = i * 4
            
            let point = sensorDensity.density(frameIndex: 0, pointIndex: i)
            
            densities[positionIndex + 0] = (point.pm2_5 / scaleFactor)
            densities[positionIndex + 1] = (point.pm10 / scaleFactor)
            densities[positionIndex + 2] = 1.0
            densities[positionIndex + 3] = 1.0
        }
        
        for i in 0...(numberOfObjects - 1) {
            
//            let scaleFactor: Float = 17.0
            let scaleFactor: Float = 15.0
            let positionIndex = i * 4
            
            let point = xyz.point(frameIndex: 0, pointIndex: i)
            
            positions[positionIndex + 0] = (point.x / scaleFactor) - 0.0
            positions[positionIndex + 1] = (point.z / scaleFactor) - 0.0
            positions[positionIndex + 2] = (point.y / scaleFactor) - 0.0
            positions[positionIndex + 3] = 1.0
            
            _velocities[positionIndex + 0] = 0.0
            _velocities[positionIndex + 1] = 0.0
            _velocities[positionIndex + 2] = 0.0
            _velocities[positionIndex + 3] = 0.0
        }
    }
    
    func updateMotion() {
    
        let frameTime = CFAbsoluteTimeGetCurrent()
//        print("frameTime: \(frameTime)")
        let deltaTime: TimeInterval = frameTime - lastFrameTime
        lastFrameTime = frameTime
        
        if (deltaTime > 0) {
            
            let angleX = angle.x + angularVelocity.x * CGFloat(deltaTime)
            let angleY = angle.y + angularVelocity.y * CGFloat(deltaTime)
            
            angle.x = angleX
            angle.y = min(max(angleY, -1.0), 1.0)
            
            angularVelocity = CGPoint(x: angularVelocity.x * kRotationDamping, y: angularVelocity.y * kRotationDamping)
            angularVelocity.y *= 0.95
        }
    }
    
    func updateCamera() {
        
        guard let camera = camera else { return }
        camera.setProjectionMatrix()
        camera.translate(x: 0.0, y: 0.0, z: -2.0)
        camera.rotate(x: Float(angle.y), y: Float(angle.x), z: nil)
        
        guard let device = metalKitView?.device else { return }
        
        var _computeParams = ComputeParams(numberOfObjects: UInt32(numberOfObjects), delta: DELTA, softening: SOFTENING)
        computeParams = device.makeBuffer(bytes: &_computeParams, length: MemoryLayout<ComputeParams>.size, options: MTLResourceOptions.cpuCacheModeWriteCombined)
//        print("ComputeParams.size stride: \(MemoryLayout<ComputeParams>.size), \(MemoryLayout<ComputeParams>.stride), \(MemoryLayout<ComputeParams>.alignment)")
//        print("MemoryLayout<matrix_float4x4>.size: \(MemoryLayout<matrix_float4x4>.size), MemoryLayout<Float>.size: \(MemoryLayout<Float>.size)")
        
        let renderParamsSize = MemoryLayout<matrix_float4x4>.size + MemoryLayout<Float>.size * 4
        renderParams = device.makeBuffer(length: renderParamsSize, options: .cpuCacheModeWriteCombined)
        
        memcpy(renderParams.contents(), camera.matrix, MemoryLayout<matrix_float4x4>.size)
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}

extension SensorViewController: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    
    func draw(in view: MTKView) {
        
        updateMotion()
        updateCamera()
        
        buffer = queue?.makeCommandBuffer()
        
//        // Compute kernel
//        let groupsize = MTLSizeMake(512, 1, 1)
//        let numgroups = MTLSizeMake(numberOfObjects / 512, 1, 1)
//
//        let computeEncoder = buffer!.makeComputeCommandEncoder()
//        computeEncoder?.setComputePipelineState(computePipelineState)
//        computeEncoder?.setBuffer(positionsIn, offset: 0, index: 0)
//        computeEncoder?.setBuffer(positionsOut, offset: 0, index: 1)
//        computeEncoder?.setBuffer(velocities, offset: 0, index: 2)
//        computeEncoder?.setBuffer(computeParams, offset: 0, index: 3)
//        computeEncoder?.dispatchThreadgroups(numgroups, threadsPerThreadgroup: groupsize)
//        computeEncoder?.endEncoding()
        
        // Vertex and fragment shaders
        let renderPassDescriptor = view.currentRenderPassDescriptor
        renderPassDescriptor!.colorAttachments[0].loadAction = .clear
        renderPassDescriptor!.colorAttachments[0].clearColor = MTLClearColorMake(0.15, 0.15, 0.3, 1.0)
//
        let renderEncoder = buffer!.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
        renderEncoder?.setRenderPipelineState(renderPipelineState)
        renderEncoder?.setVertexBuffer(densityBuffer, offset: 0, index: 0)
        renderEncoder?.setVertexBuffer(positionsOut, offset: 0, index: 1)
        renderEncoder?.setVertexBuffer(renderParams, offset: 0, index: 2)
        renderEncoder?.setVertexBuffer(computeParams, offset: 0, index: 3)
        renderEncoder?.drawPrimitives(type: MTLPrimitiveType.point, vertexStart: 0, vertexCount: numberOfObjects)
        renderEncoder?.endEncoding()

        buffer!.present(view.currentDrawable!)
        buffer!.commit()
        
        swap(&positionsIn, &positionsOut)
    }
}
