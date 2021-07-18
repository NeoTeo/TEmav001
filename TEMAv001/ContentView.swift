//
//  ContentView.swift
//  TEMAv001
//
//  Created by teo on 18/07/2021.
//

import SwiftUI

fileprivate let winWidth = 640
fileprivate let winHeight = 480

struct ContentView: View {
    
    @State private var windowDims = CGSize(width: winWidth, height: winHeight)

    var system: System
    @ObservedObject var ppu: PPU

    init() {
        system = System()
        ppu = system.ppu
        system.runCycle()
    }
    
    var body: some View {

        VStack {
            Text("updated \(Date.now)")
                .onTapGesture {
                    system.debugTest()
                }
        if ppu.display != nil {
            let disp = Image(ppu.display!, scale: 1, label: Text("raster display"))
            Canvas { context, size in

                context.draw(disp, at: CGPoint(x: 0,y: 0), anchor: .topLeading)
                
            }
//                .frame(width: windowDims.width, height: windowDims.height)
        
        }
        }
            .frame(width: windowDims.width, height: windowDims.height)
    }
}

let bootROM: [CPU.OpCode] = [
    .pop, .push
]
    

/// Central Processing Unit
class CPU {
    
    enum OpCode: UInt16 {
        case nop
        case pop
        case push
    }
    
    /// Parameter stack, 2 bytes * 256 = 512 bytes, signed
    var pStack = [Int16](repeating: 0, count: 2^8)
    var pStackCounter = 0
    
    /// Return stack  2 bytes * 256 = 512 bytes, unsigned
    var rStack = [UInt16](repeating: 0, count: 2^8)
    var rStackCounter = 0
    
    var pc: UInt16 = 0
    
    /// Interconnects
    var mmu: MMU!
        
    func reset() {
        pc = 0
        pStackCounter = 0
        rStackCounter = 0
    }
    
    func clockTick() {
        /// halt at 0xFFFF
        guard pc < 65535 else { return }
        
        let op = OpCode(rawValue: mmu.read(address: pc))

        switch op {
        case .pop:
            print("pop value")
        case .push:
            print("push value")
        case .nop:
            break
        default:
            print("unimplemented opcode")
        }
        pc += 1
    }
}

/// Memory Management Unit
class MMU {
    /// 65536 bytes of memory
    var bank = [UInt16](repeating: 0, count: 65536)
    
    func debugInit() {
        write(value: CPU.OpCode.push.rawValue, address: 0)
        write(value: CPU.OpCode.push.rawValue, address: 1)
        write(value: CPU.OpCode.pop.rawValue, address: 2)
    }
    
    func write(value: UInt16, address: UInt16) {
        bank[Int(address)] = value
    }
    
    func read(address: UInt16) -> UInt16 {
        return bank[Int(address)]
    }
}

/// Pixel processing unit
class PPU : ObservableObject {
    public var pixelBuffer: [UInt8]
    private let bytesPerRow = winWidth
    private let bitsPerPixel = 8
    
    private let clut: [UInt8] =     [0xE0, 0xF8, 0xD0,
                                     0x88, 0xC0, 0x70,
                                     0x34, 0x68, 0x56,
                                     0x8, 0x18, 0x20]

    private var imageDataProvider: CGDataProvider!
    private var colorSpace: CGColorSpace!
    @Published var display: CGImage?

    public var horizontalPixels: Int
    public var verticalPixels: Int
    
    init(width: Int, height: Int) {
        
        horizontalPixels = width
        verticalPixels = height
        
        pixelBuffer = [UInt8](repeating: 0, count: width * height)
        imageDataProvider = CGDataProvider(data: Data(pixelBuffer) as NSData)
        guard imageDataProvider != nil else { fatalError("PPU init failed with nil imageDataProvider") }
        colorSpace = CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(),
                                  last: 3,
                                  colorTable: UnsafePointer<UInt8>(clut))
        guard colorSpace != nil else { fatalError("PPU init failed with nil colorSpace") }

    }
    
    func refresh() {

        imageDataProvider = CGDataProvider(data: Data(pixelBuffer) as NSData)
        DispatchQueue.main.async {
            self.display = CGImage(width: self.horizontalPixels,
                              height: self.verticalPixels,
                          bitsPerComponent: 8,
                              bitsPerPixel: self.bitsPerPixel,
                              bytesPerRow: self.bytesPerRow,
                              space: self.colorSpace!,
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: self.imageDataProvider!,
                          decode: nil,
                          shouldInterpolate: false,
                          intent: CGColorRenderingIntent.defaultIntent)
            if self.display == nil { fatalError("display is nil") }
        }
        
    }

//    func refresh() -> CGImage {
//
//        imageDataProvider = CGDataProvider(data: Data(pixelBuffer) as NSData)
//
//        display = CGImage(width: horizontalPixels,
//                          height: verticalPixels,
//                          bitsPerComponent: 8,
//                          bitsPerPixel: bitsPerPixel,
//                          bytesPerRow: bytesPerRow,
//                          space: colorSpace!,
//                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
//                          provider: imageDataProvider!,
//                          decode: nil,
//                          shouldInterpolate: false,
//                          intent: CGColorRenderingIntent.defaultIntent)
//        if display == nil { fatalError("display is nil") }
//        return display!
//    }
}

//class ObservableSystem: ObservableObject {
//    var system: System!
//    @Published var displayImage: CGImage!
//
//    init() {
//        system = System()
//        displayImage = system.ppu.display
//        system.runCycle()
//    }
//}

class System {
    
    static public let displayHResolution = 640
    static public let displayVResolution = 480
    
    var cpu: CPU
    var mmu: MMU
    var ppu : PPU
    
    let cycleQ = DispatchQueue.global(qos: .userInitiated)
   
    init() {
        cpu = CPU()
        mmu = MMU()
        ppu = PPU(width: System.displayHResolution, height: System.displayVResolution)
        
        // connect the components
        cpu.mmu = mmu
    }
    // We want our cycle allowance (time given to each cycle of the emulator) to be calculated from 60 hz
    let emuAllowanceNanos: Double = 1_000_000_000 / 60
        
    func debugTest() {
        var buf = [UInt8](repeating: 0, count: System.displayHResolution * System.displayVResolution)
        
        let o: [UInt8] = [
            0, 0, 2, 2, 2, 2, 0, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 0, 2, 2, 2, 2, 0, 0
        ]
        
        let k: [UInt8] = [
            0, 2, 2, 0, 0, 0, 0, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 2, 2, 0, 2, 2, 2, 0,
            0, 2, 2, 2, 2, 2, 0, 0,
            0, 2, 2, 2, 2, 2, 0, 0,
            0, 2, 2, 0, 2, 2, 0, 0,
            0, 2, 2, 0, 0, 2, 2, 0,
            0, 2, 2, 0, 0, 2, 2, 0
        ]

        var y = 10
        var xpos = 50

        for r in 0 ..< 8 {
            let yoff = y * System.displayHResolution
            for c in 0 ..< 8 {
                buf[yoff+xpos+c] = o[r*8+c]
            }
            y += 1
        }

        xpos += 8
        y = 10
        
        for r in 0 ..< 8 {
            let yoff = y * System.displayHResolution
            for c in 0 ..< 8 {
                buf[yoff+xpos+c] = k[r*8+c]
            }
            y += 1
        }

        ppu.pixelBuffer = buf
        
        mmu.debugInit()
        cpu.reset()
    }
        
    func runCycle() {
//        print("run cycle \(Date.now)")
        /// step through ram and execute opcodes
        cpu.clockTick()
        /// update the display
        
            ppu.refresh()
        
        
        let nextCycle = DispatchTime.now() + .nanoseconds(Int(emuAllowanceNanos))
        
        cycleQ.asyncAfter(deadline: nextCycle, execute: runCycle)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
