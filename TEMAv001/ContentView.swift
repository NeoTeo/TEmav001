//
//  ContentView.swift
//  TEMAv001
//
//  Created by teo on 18/07/2021.
//

import SwiftUI
import Combine

fileprivate let keysPublisher = PassthroughSubject<String, Never>()

// Constants
fileprivate let ppuWidth = 640
fileprivate let ppuHeight = 480
fileprivate let nanosPerSecond = 1_000_000_000                          // number of nanoseconds in a second
fileprivate let targetPPUHz = 60                                        // the target Hz of the ppu
fileprivate let nanoPPURate = nanosPerSecond / targetPPUHz              // The number of nanoseconds in each ppu tick
fileprivate let targetTEMAVirtualHz = 1_000_000                         // the target Hz of TEMA
fileprivate let tickAllocation = targetTEMAVirtualHz / targetPPUHz      // the number of ticks each TEMA run gets per ppu tick



struct ContentView: View {
    
    @State private var windowDims = CGSize(width: ppuWidth, height: ppuHeight)
    let cycleQ = DispatchQueue.global(qos: .userInitiated)
    
    var tema: System
    @ObservedObject
    var ppu: PPU

    @State var fps: Int = 0
    @State var cycleRate: Int = 0
    
    @State var displayBus: Bus?
    @State var consoleBus: Bus?
    @State var mouseBus: Bus?
    
    @State var scaleLabel = "2x"
    @State var viewScale = 1.0
    @State var prevTime: DispatchTime = DispatchTime.now()
    @State var debugTestFirstRun = true
    

    @State var fpsTimes: Int = 0
    @State var cyclesSeq: Int = 0

    let stdin = FileHandle.standardInput
        
    let objPath = "/Users/teo/Downloads/"
    
    init() {
        tema = System()
        ppu = PPU(width: ppuWidth, height: ppuHeight)
        loadMemory(filepath: objPath + "test.teo")
    }
    
    // We want our cycle allowance (time given to each cycle of the emulator) to be calculated from 60 hz
    // 1 second = 1_000_000_000 nanoseconds
//    let emuAllowanceNanos: Double = 1_000_000_000 / 60
       
    func noComms(bus: Bus, a: UInt8, b: UInt8) { }
    
    func displayComms(bus: Bus, a: UInt8, b: UInt8) {
        guard b != 0 else { return }
        switch a {
        case 0xe:
            let x = Int(bus.busRead16(a: 0x8))
            let y = Int(bus.busRead16(a: 0xA))
            let colIdx = bus.busRead(a: 0xE)
            ppu.pixelBuffer[y*ppuWidth+x] = colIdx
        case 0xf:
            let x = Int(bus.busRead16(a: 0x8))
            let y = Int(bus.busRead16(a: 0xA))
            let addr = Int(bus.busRead16(a: 0xC))
            //let addr = tema.mmu.bank[idx]

            /// for now assuming 8x8 pixels and no clutidx
            for row in 0 ..< 8 {
                let rowdat = tema.mmu.bank[Int(addr)+row]
                for col in 0 ..< 8 {
                    let off = (y+row)*ppuWidth+x+col
                    ppu.pixelBuffer[off] = (rowdat & (0x80 >> col)) == 0 ? 0 : 0x2
                }
            }
        default: break
        }
    }
    
    // a encodes the device id in its most significant nibble and a port address in its lsn
    // b is non zero when there is data to write
    func consoleComms(bus: Bus, a: UInt8, b: UInt8) {
        if (b != 0) && (a > 0x7) {
            if (a - 0x7) == 1 {
                let char = Array(arrayLiteral: bus.buffer[Int(a)])
                if let dat = String(bytes: char , encoding: .ascii)?.data(using: .ascii) {
                    try? FileHandle.standardOutput.write(contentsOf: dat)
                }
            } else {
                let dat = FileHandle.standardInput.readData(ofLength: 1)
                if let chars = String(data: dat, encoding: .utf8)?.utf8 {
                    bus.buffer[Int(a)] = [UInt8](chars)[0]
                }
            }
        }
    }
    
    
    func loadMemory(filepath: String) {
        
            do {
                guard FileManager.default.fileExists(atPath: filepath) else {
                    print("error loading binary from disk")
                    return
                }
                
                let binary = try Data(contentsOf: URL(fileURLWithPath: filepath), options: .mappedIfSafe)
                try tema.loadRam(destAddr: 0x0, ram: Array(binary))

            } catch {
                print("Data load error \(error)")
            }
    }
        
    func TEmuCycle() {
    
        // set pc to 0x100 for first run (bodge)
        if debugTestFirstRun == true { tema.cpu.pc = 0x100 ; debugTestFirstRun = false }
        
        /// step through ram and execute allocated number of opcodes
        tema.cpu.run(ticks: tickAllocation)
        
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
        // add up cycle timings for an average every second.
        cyclesSeq += nanodelta
        
        /// calculate how much our actual cycle time differs from what it should be to hit the target. Negative number means a cycle is taking longer than targeted.
        let arse = nanoPPURate-nanodelta
        
        let newcyc = arse < 0 ? nanoPPURate + arse : nanoPPURate
        let nCycle = DispatchTime.now().advanced(by: .nanoseconds(newcyc))
        if newcyc > nanoPPURate { fatalError("newcyc is > nonPPURate") }
        
        cycleQ.asyncAfter(deadline: nCycle, qos: .userInteractive, execute: TEmuCycle)
    }
    
    
    var body: some View {

        VStack {
            HStack {
                if displayBus == nil {
                    Button("Run TEMA") {
                        
                        stdin.readabilityHandler = { pipe in
                            let message = String(data: pipe.availableData, encoding: .utf8)!

                            if let cb = consoleBus {
                                // 0x2 is the read "port" of the console bus buffer, where TEma reads new console data from.
                                cb.buffer[0x2] = UInt8(Array(message.utf8)[0])  // MARK: should use write for consistency? (or not for speed)
                                // MARK: exec this on a serial queue to avoid concurrency issues.
                                tema.cpu.interruptEnable(bus: cb)
                            }

//                            print("readabilityHandler: \(message)")
                        }

                        consoleBus = tema.registerBus(id: .console, name: "console", comms: consoleComms)
                        // The display bus assumes the following port mappings:
                        // 0x00 interrupt vector
                        // 0x02 display width
                        // 0x04 display height
                        // 0x08 x coordinate
                        // 0x0A y coordinate
                        // 0x0C address for DMA
                        // 0x0E clut index
                        
                        displayBus = tema.registerBus(id: .display, name: "screen", comms: displayComms)
                        
                        // If we have a display, pass its resolution to TEma
                        if displayBus != nil {
                            // ports 0x2 and 0x4 represent the width and height of the TEma display.
                            write16(mem: &displayBus!.buffer, value: UInt16(ppuWidth), address: 0x2)
                            write16(mem: &displayBus!.buffer, value: UInt16(ppuHeight), address: 0x4)
                        }
                        
                        // The mouse bus assumes the following mappings:
                        // 0x00 interrupt vector
                        // 0x02 x position
                        // 0x04 y position
                        // 0x06 button state (0x10 signals lmb down, 0x01 signals rmb down)
                        mouseBus = tema.registerBus(id: .mouse, name: "mouse", comms: noComms)
                        
                        Task.init(priority: .high) {
                            TEmuCycle()
                        }
                    }
                }
                
                HStack {
                    Text("TEMAv1")
                        .onTapGesture {
                                                        
                            // test to see if writing to stdout actually displays. It does.
//                            let data = Data([68])
//                            if let dat = String(bytes: data , encoding: .ascii)?.data(using: .ascii) {
//                            try? FileHandle.standardOutput.write(contentsOf: dat)
//                            }
                            //tema.mmu.debugInit()
                            tema.tests()
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
            
                Canvas { context, size in
                    let disp = context.resolve(Image(ppu.display!, scale: viewScale, label: Text("raster display")).interpolation(.none))
                    context.draw(disp, at: CGPoint(x: 0,y: 0), anchor: .topLeading)
                }
                    .frame(width: windowDims.width, height: windowDims.height)
            }
        }
        .onReceive(keysPublisher) { keys in
            if let cb = consoleBus {
                // 0x2 is the read "port" of the console bus buffer, where TEma reads new console data from.
                cb.buffer[0x2] = UInt8(Array(keys.utf8)[0])
                // MARK: exec this on a serial queue to avoid concurrency issues.
                tema.cpu.interruptEnable(bus: cb)
            }
        }
        .overlay(
            EmptyView()
                .trackingMouse { event in
                    if let mb = mouseBus {
                        
                        switch event.type {
                        case .mouseMoved:
                            let position = event.locationInWindow
                            //print("mouse is at \(position.x),\(position.y)")
                            let x = min(max(0, Int(position.x)), ppuWidth-1)
                            let y = min(max(0, ppuHeight-Int(position.y)), ppuHeight-1)
                            // ports 0x2 and 0x4 represent the x and y of the TEma mouse interface.
                            write16(mem: &mb.buffer, value: UInt16(x), address: 0x2)
                            write16(mem: &mb.buffer, value: UInt16(y), address: 0x4)
                            
                            
                        case .leftMouseDown:    mb.buffer[0x06] |= 0x10
                        case .leftMouseUp:      mb.buffer[0x06] &= ~0x10
                        case .rightMouseDown:   mb.buffer[0x06] |= 0x01
                        case .rightMouseUp:     mb.buffer[0x06] &= ~0x01
                        default:
                            print("mouse did summink. dunno?!")
                        }
                        tema.cpu.interruptEnable(bus: mb)
                    }
                }

        )
            .background(KeyEventHandling())
        
    }
}

/// Pixel processing unit
class PPU: ObservableObject {
    public var pixelBuffer: [UInt8]
    private let bytesPerRow = ppuWidth
    private let bitsPerPixel = 8
    
    private let clut: [UInt8] =     [0xFF, 0xFF, 0xFF,  // r, g, b
                                     0x8C, 0xDB, 0xC4,
                                     0x00, 0x00, 0x00,
                                     0xFF, 0xC6, 0x33]
    // MARK: Expand clut to 16 colors.

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
                                  last: (clut.count/3)-1,
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

struct KeyEventHandling: NSViewRepresentable {
    
    class KeyView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            //print(">> key \(event.charactersIgnoringModifiers ?? "")")
            let keys = event.charactersIgnoringModifiers
            keysPublisher.send(keys!)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        DispatchQueue.main.async { // wait till next event cycle
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        //print("updateNSview")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

