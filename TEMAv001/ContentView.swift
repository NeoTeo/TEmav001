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
    .pop, .lit //,.bla, .bla
]
    

/// Central Processing Unit
class CPU {
        
    /// A possible alternative is to define each operation as a method and then
    /// have an array of methods whose position matches their opcode.
    /// The clock tick method would then just read an opcode from memory and use it as an index into the operation array.
    /// With the retrieved method you can then just call it
    /// (using op(CPU)() because methods are curried. see http://web.archive.org/web/20201225064902/https://oleb.net/blog/2014/07/swift-instance-methods-curried-functions/)
    
    enum OpCode: UInt8 {
        case nop
        // stack operations
        case pop
        case lit
        case dup
        case ovr
        case rot
        
        // arithmetical operations
        case add
        case sub
        case mul
        case div
        
        // logic operations
        case equ
        case grt
        case neg    // negate the top of the stack
        case jmp    // jump unconditinally
        case jot    // jump on true condition
    }
    
    enum CPUError: Error {
    case missingParameters
    }
    /// Parameter stack, 256 bytes, unsigned
    var pStack = [UInt8]()//(repeating: 0, count: 256)
//    var pStackCounter = 0
    
    /// Return stack  256 bytes, unsigned
    var rStack = [UInt8]()//(repeating: 0, count: 256)
//    var rStackCounter = 0
    
    var pc: UInt16 = 0
    
    /// Interconnects
    var mmu: MMU!
        
    func reset() {
        pc = 0
//        pStackCounter = 0
//        rStackCounter = 0
    }
    
    func clockTick() throws {
        /// halt at 0xFFFF
        guard pc < 65535 else { return }
        
        /// since we're limiting the number of opcodes to 32 we are only using the bottom 5 bits.
        /// We can use the top three as flags for byte or short ops, copy rather than pop, and return from jump.
        /// This is where we would mask out the bottom 5 with an & 0x1F or, if we've made opcodes
        /// for both byte and shorts, the bottom 6 with ^ 0x3F
        let op = OpCode(rawValue: mmu.read(address: pc))

        switch op {
        case .nop:
            pc += 1
            break

        /// stack operations
        case .pop:
            let val = pStack.popLast()
            print("popped value \(String(describing: val))")
            pc += 1
            
        case .lit:
            /// next value in memory assumed to be the value to push to pstack
            pc += 1
            let val = mmu.read(address: pc)
            pStack.append(val)
            pc += 1
            
        case .dup:
            guard let a = pStack.last else { throw CPUError.missingParameters }
            pStack.append(a)
            pc += 1
            
        case .ovr:
            guard pStack.count > 1 else { throw CPUError.missingParameters }
            let a = pStack[pStack.count - 2]
            pStack.append(a)
            pc += 1
            
        case .rot:
            guard pStack.count > 2 else { throw CPUError.missingParameters }
            let a = pStack.remove(at: pStack.count - 3)
            pStack.append(a)
            pc += 1
            
        /// arithmetic operations
        case .add:
            guard let b = pStack.popLast(), let a = pStack.popLast() else { throw CPUError.missingParameters }
            pStack.append( a + b )
            pc += 1
            
        case .sub:
            guard let b = pStack.popLast(), let a = pStack.popLast() else { throw CPUError.missingParameters }
            pStack.append( a - b )
            pc += 1
            
        case .mul:
            guard let b = pStack.popLast(), let a = pStack.popLast() else { throw CPUError.missingParameters }
            pStack.append( a * b )
            pc += 1
            
        case .div:
            guard let b = pStack.popLast(), let a = pStack.popLast() else { throw CPUError.missingParameters }
            pStack.append( a / b )
            pc += 1
            
        /// logic operations
        case .equ:
            guard let b = pStack.popLast(), let a = pStack.popLast() else { throw CPUError.missingParameters }
            pStack.append( a == b ? 0xFF : 0 )
            pc += 1
            
        case .grt:
            guard let b = pStack.popLast(), let a = pStack.popLast() else { throw CPUError.missingParameters }
            pStack.append( a > b ? 0xFF : 0 )
            pc += 1
            
        case .neg:
            guard let a = pStack.popLast() else { throw CPUError.missingParameters }
            pStack.append( a == 0 ? 0xFF : 0 )
            pc += 1
            
        case .jmp:
            guard let a = pStack.popLast() else { throw CPUError.missingParameters }
            /// relative jump is default
            pc = UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a)))
            
        case .jot:
            guard let a = pStack.popLast(), let b = pStack.popLast() else { throw CPUError.missingParameters }
            /// relative jump is default
            
            
//            rStack.append( a )
            pc = b != 0 ?UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a))) : pc + 1

        default:
            print("unimplemented opcode: \(String(describing: op))")
        }
        
    }
}

/// Memory Management Unit
class MMU {
    /// 65536 bytes of memory
    var bank = [UInt8](repeating: 0, count: 65536)
    
    func debugInit() {
        
        func opwrite(value: CPU.OpCode, address: UInt16) -> UInt16{
            bank[Int(address)] = value.rawValue
            return address + 1
        }

        func test42() {
            clear()
            var addr: UInt16 = 0
            
            addr = opwrite(value: .lit, address: addr)
            write(value: 4, address: addr)
            addr += 1
            addr = opwrite(value: .lit, address: addr)
            
            write(value: 3, address: addr)
            addr += 1
            addr = opwrite(value: .add, address: addr)
            
            addr = opwrite(value: .lit, address: addr)
            
            write(value: 6, address: addr)
            addr += 1
            addr = opwrite(value: .mul, address: addr)
            
            addr = opwrite(value: .pop, address: addr)

        }
        
        func testRot() {
            
            clear()
            var addr: UInt16 = 0

            addr = opwrite(value: .lit, address: addr)
            write(value: 1, address: addr)
            addr += 1
            
            addr = opwrite(value: .lit, address: addr)
            write(value: 2, address: addr)
            addr += 1
            
            addr = opwrite(value: .lit, address: addr)
            write(value: 3, address: addr)
            addr += 1

            addr = opwrite(value: .rot, address: addr)
            
            addr = opwrite(value: .pop, address: addr)
            addr = opwrite(value: .pop, address: addr)
            addr = opwrite(value: .pop, address: addr)
        }
        
        func testOvr() {
            
            clear()
            var addr: UInt16 = 0

            addr = opwrite(value: .lit, address: addr)
            write(value: 1, address: addr)
            addr += 1
            
            addr = opwrite(value: .lit, address: addr)
            write(value: 2, address: addr)
            addr += 1
            
            addr = opwrite(value: .ovr, address: addr)
            
            addr = opwrite(value: .pop, address: addr)
            addr = opwrite(value: .pop, address: addr)
            addr = opwrite(value: .pop, address: addr)
        }
        
        func testLoop() {
            clear()
            var addr: UInt16 = 0
            
            addr = opwrite(value: .lit, address: addr)
            write(value: 0, address: addr)
            addr += 1
            
            /// label to jump to here
            let beginLabel = addr

            addr = opwrite(value: .lit, address: addr)
            write(value: 1, address: addr)
            addr += 1

            addr = opwrite(value: .add, address: addr)

            addr = opwrite(value: .dup, address: addr)
            
            addr = opwrite(value: .lit, address: addr)
            write(value: 7, address: addr)
            addr += 1

            addr = opwrite(value: .equ, address: addr)

            addr = opwrite(value: .neg, address: addr)

            addr = opwrite(value: .lit, address: addr)
            let offset = UInt8(bitPattern: Int8(Int16(beginLabel) - Int16(addr + 1)))
            write(value: offset, address: addr)
            addr += 1
            addr = opwrite(value: .jot, address: addr)
            
            addr = opwrite(value: .pop, address: addr)

        }

//        test42()
//        testRot()
//        testOvr()
        testLoop()
    }

    func clear() {
        bank = [UInt8](repeating: 0, count: 65536)
    }
    
    func write(value: UInt8, address: UInt16) {
        bank[Int(address)] = value
    }
    
    func read(address: UInt16) -> UInt8 {
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
        
        try! cpu.clockTick()
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
