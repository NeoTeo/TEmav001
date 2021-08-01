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

    let cycleQ = DispatchQueue.global(qos: .userInitiated)
    
    var system: System
    @ObservedObject
    var ppu: PPU

    @State var fps: Double = 0
    @State var cycleRate: Double = 0
    
    @State var displayBus: Bus?

    
    let objPath = "/Users/teo/Downloads/"
    
    init() {
        system = System()
        ppu = PPU(width: winWidth, height: winHeight)
        loadMemory(filepath: objPath + "test.obj")
    }
    
    // We want our cycle allowance (time given to each cycle of the emulator) to be calculated from 60 hz
    // 1 second = 1_000_000_000 nanoseconds
//    let emuAllowanceNanos: Double = 1_000_000_000 / 60
       
    func displayComms(bus: Bus, a: UInt8, b: UInt8) {
        if b != 0 && (a == 0xe) {
            let x = Int(bus.read16(a: 0x8))
            let y = Int(bus.read16(a: 0xA))
            let colIdx = bus.read(a: 0xE)
            ppu.pixelBuffer[y*winWidth+x] = colIdx
            
            print("set a pixel at \(x),\(y)")
        }
    }
        
    func loadMemory(filepath: String) {
        let fileurl = URL(fileURLWithPath: filepath)
        
            do {
//                let binary = try Data(contentsOf: fileurl, options: .mappedIfSafe)
//                let dat = Array(binary)
//                print("done")
        
                guard FileManager.default.fileExists(atPath: filepath),
                        let binary = try? Data(contentsOf: URL(fileURLWithPath: filepath), options: .mappedIfSafe),
                        let _ = try? system.loadRam(destAddr: 0x0, ram: Array(binary))
                else {
                    print("error loading binary from disk")
                    return
                }
            } catch {
                print("Data error \(error)")
            }

    }
    
    @State var prevTime: DispatchTime = DispatchTime.now()
    @State var prevPPURefreshTime: DispatchTime = DispatchTime.now()
    static let secondInNanos: Double = 1_000_000_000
    let PPURefreshRate: Double = secondInNanos / 60
    
    @State var debugTestFirstRun = true
    
    let targetTEMAVirtualHz = 4_000_000
    
    func TEmuCycle() {
    
        // set pc to 0x100 for first run (bodge)
        if debugTestFirstRun == true { system.cpu.pc = 0x100 ; debugTestFirstRun = false }
        
        /// step through ram and execute opcodes
        let tickAllocation = targetTEMAVirtualHz / 60
        system.cpu.run(ticks: tickAllocation)
        
            ppu.refresh()
        
        let nowTime = DispatchTime.now()
        let delta = Double(nowTime.uptimeNanoseconds - prevTime.uptimeNanoseconds)
        let dt = nowTime.uptimeNanoseconds - prevTime.uptimeNanoseconds
        prevTime = nowTime
        cycleRate = 1_000_000_000 / delta
 
        let targetHz = 60//500
        let nanoRate = 1_000_000_000 / targetHz
        let arse = nanoRate-Int(dt)
        
        let newcyc = arse < 0 ? nanoRate + arse : nanoRate
//        print("newcyc is \(newcyc)")
        let nextCycle = DispatchTime.now().advanced(by: DispatchTimeInterval.nanoseconds(newcyc))
        let nCycle = DispatchTime.now() + .nanoseconds(newcyc)
        cycleQ.asyncAfter(deadline: nCycle, qos: .userInteractive, execute: TEmuCycle)
        
    }

    
    var body: some View {

        VStack {
            HStack {
                if displayBus == nil {
                    Button("Run TEMA") {
                        displayBus = system.registerBus(id: .display, name: "screen", comms: displayComms)
                        Task.init(priority: .high) {
                            TEmuCycle()
                        }
                    }
                }
                
                HStack {
                    Text("TEMAv1")
                        .onTapGesture {
                            system.mmu.debugInit()
                        }
                    Text("cpu rate: \(cycleRate)").monospacedDigit()
                    Text("fps: \(fps)").monospacedDigit()
                }
            }
        if ppu.display != nil {
//            TimelineView(.animation) {_ in
//            let disp = Image(ppu.display!, scale: 1, label: Text("raster display"))
            Canvas { context, size in
                let disp = Image(ppu.display!, scale: 1, label: Text("raster display"))
                context.draw(disp, at: CGPoint(x: 0,y: 0), anchor: .topLeading)
                
            }//.compositingGroup()
//                .frame(width: windowDims.width, height: windowDims.height)
            }
//        }
        }
            .frame(width: windowDims.width, height: windowDims.height)
    }
    
    func debugOK(x: UInt16, y: UInt16) {
        var buf = [UInt8](repeating: 0, count: winWidth * winHeight)
        
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

        var ypos = Int(y)
        var xpos = Int(x)

        for r in 0 ..< 8 {
            let yoff = ypos * winWidth
            for c in 0 ..< 8 {
                buf[yoff+xpos+c] = o[r*8+c]
            }
            ypos += 1
        }

        xpos += 8
        ypos = Int(y)
        
        for r in 0 ..< 8 {
            let yoff = ypos * winWidth
            for c in 0 ..< 8 {
                buf[yoff+xpos+c] = k[r*8+c]
            }
            ypos += 1
        }

        ppu.pixelBuffer = buf
    }
}

let bootROM: [CPU.OpCode] = [
    .pop, .lit //,.bla, .bla
]

/// Pixel processing unit
class PPU: ObservableObject {
    public var pixelBuffer: [UInt8]
    private let bytesPerRow = winWidth
    private let bitsPerPixel = 8
    
    private let clut: [UInt8] =     [0xE0, 0xF8, 0xD0,
                                     0x88, 0xC0, 0x70,
                                     0x34, 0x68, 0x56,
                                     0x8, 0x18, 0x20]

    private var imageDataProvider: CGDataProvider!
    private var colorSpace: CGColorSpace!
    @Published
    var display: CGImage?

    public var horizontalPixels: Int
    public var verticalPixels: Int
    
    init(width: Int, height: Int) {
        print("PPU init")
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
        let img = CGImage(width: self.horizontalPixels,
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
        
        DispatchQueue.main.async {
            self.display = img
            if self.display == nil { fatalError("display is nil") }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
