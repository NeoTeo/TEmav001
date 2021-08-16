//
//  ContentView.swift
//  TEMAv001
//
//  Created by teo on 18/07/2021.
//

import SwiftUI

// Constants
fileprivate let winWidth = 640
fileprivate let winHeight = 480
fileprivate let nanosPerSecond = 1_000_000_000                          // number of nanoseconds in a second
fileprivate let targetPPUHz = 60                                        // the target Hz of the ppu
fileprivate let nanoPPURate = nanosPerSecond / targetPPUHz              // The number of nanoseconds in each ppu tick
fileprivate let targetTEMAVirtualHz = 4_000_000                         // the target Hz of TEMA
fileprivate let tickAllocation = targetTEMAVirtualHz / targetPPUHz      // the number of ticks each TEMA run gets per ppu tick

struct ContentView: View {
    
    @State private var windowDims = CGSize(width: winWidth, height: winHeight)
    let cycleQ = DispatchQueue.global(qos: .userInitiated)
    
    var system: System
    @ObservedObject
    var ppu: PPU

    @State var fps: Int = 0
    @State var cycleRate: Int = 0
    
    @State var displayBus: Bus?

    @State var scaleLabel = "2x"
    @State var viewScale = 1.0
    @State var prevTime: DispatchTime = DispatchTime.now()
    @State var debugTestFirstRun = true
    

    @State var fpsTimes: Int = 0
    @State var cyclesSeq: Int = 0

    let objPath = "/Users/teo/Downloads/"
    
    init() {
        system = System()
        ppu = PPU(width: winWidth, height: winHeight)
        loadMemory(filepath: objPath + "test.teo")
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
            
            //print("set a pixel at \(x),\(y)")
        }
    }
        
    func loadMemory(filepath: String) {
        
            do {
                guard FileManager.default.fileExists(atPath: filepath) else {
                    print("error loading binary from disk")
                    return
                }
                
                let binary = try Data(contentsOf: URL(fileURLWithPath: filepath), options: .mappedIfSafe)
                try system.loadRam(destAddr: 0x0, ram: Array(binary))

            } catch {
                print("Data load error \(error)")
            }
    }
        
    func TEmuCycle() {
    
        // set pc to 0x100 for first run (bodge)
        if debugTestFirstRun == true { system.cpu.pc = 0x100 ; debugTestFirstRun = false }
        
        /// step through ram and execute allocated number of opcodes
        system.cpu.run(ticks: tickAllocation)
        
        if fpsTimes == 30 {
            fpsTimes = 0
            fps = (nanosPerSecond / (cyclesSeq / 30)) //>> 6
            cyclesSeq = 0
        }
        fpsTimes += 1
        
        
        ppu.refresh()
        
        let nowTime = DispatchTime.now()
        /// nanodelta is the number of nanoseconds the last emu cycle has taken
        let nanodelta = Int(nowTime.uptimeNanoseconds - prevTime.uptimeNanoseconds)
        prevTime = nowTime
//        fps = nanosPerSecond / nanodelta
        // add up cycle timings for an average every second.
        cyclesSeq += nanodelta
        
        /// calculate how much our actual cycle time differs from what it should be to hit the target. Negative number means a cycle is taking longer than targeted.
        let arse = nanoPPURate-nanodelta
        
        let newcyc = arse < 0 ? nanoPPURate + arse : nanoPPURate
//        print("newcyc is \(newcyc)")
//        let nextCycle = DispatchTime.now().advanced(by: DispatchTimeInterval.nanoseconds(newcyc))
        let nCycle = DispatchTime.now().advanced(by: .nanoseconds(newcyc))
        if newcyc > nanoPPURate {
            print("WTF")
            
        }
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
                    Button(scaleLabel) {
                        let twox = scaleLabel == "2x"
                        
                        scaleLabel = twox ? "1x" : "2x"
                        viewScale = twox ? 0.5 : 1
                        windowDims.width = twox ? 1280 : 640
                        windowDims.height = twox ? 960 : 480
                    }
                }
            }
            if ppu.display != nil {
    //            TimelineView(.animation) {_ in
    //            let disp = Image(ppu.display!, scale: 1, label: Text("raster display"))
                Canvas { context, size in
                    let disp = context.resolve(Image(ppu.display!, scale: viewScale, label: Text("raster display")))
                    context.draw(disp, at: CGPoint(x: 0,y: 0), anchor: .topLeading)
                }
            }
//        }
        }
//        .frame(minWidth: windowDims.width, minHeight: windowDims.height)
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
