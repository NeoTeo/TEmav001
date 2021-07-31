//
//  TEMA.swift
//  TEMA
//
//  Created by teo on 24/07/2021.
//

import Foundation

class System {
    
    enum SystemError: Error {
    case memoryLoading
    }
    static public let displayHResolution = 640
    static public let displayVResolution = 480
    
    var cpu: CPU
    var mmu: MMU
    
    var bus: [Bus?]
   
    init() {
        cpu = CPU()
        mmu = MMU()

        /// The bus ids are as follows:
        /// 0 - system
        /// 1 - console
        /// 2 - display
        /// 3 - audio
        /// 4 - controller 1
        /// 5 - controller 2
        /// 6 - mouse
        
        bus = [Bus?](repeating: nil, count: 16)
        cpu.sys = self
    }
    
    func registerBus(id: Bus.Device, name: String, comms: @escaping (Bus, UInt8, UInt8)->Void) -> Bus {
        print("Registered bus: \(id) \(name) at ")
        let newbus = Bus(owner: self, comms: comms)
        bus[Int(id.rawValue)] = newbus
        return newbus
    }
    
    func loadRam(destAddr: UInt16, ram: [UInt8]) throws {
        
        guard ram.count+Int(destAddr) <= mmu.bank.count else { throw SystemError.memoryLoading }
        /// Would be faster with pointer juggling
        for idx in 0 ..< ram.count {
            mmu.bank[Int(destAddr)+idx] = ram[idx]
        }
    }
}

/// Bus between devices
class Bus {
    let owner: System
    let comms: ((Bus, UInt8, UInt8)->(Void))
    var buffer = [UInt8](repeating: 0, count: 16)
    
    enum Device: UInt8 {
        case system
        case console
        case display
        case audio
        case controller1 = 0x08
        case controller2
        case mouse
        case file = 0xA0
    }
    
    init(owner: System, comms: @escaping (Bus, UInt8, UInt8)->(Void)) {
        self.owner = owner
        self.comms = comms
    }
    
    func read(a: UInt8) -> UInt8 {
        comms(self, a & 0x0F, 0)
        return buffer[Int(a & 0xF)]
    }
    
    func read16(a: UInt8) -> UInt16 {
        return UInt16(read(a: a)) << 8 | UInt16(read(a: a + 1))
    }
    
    func write(a: UInt8, b: UInt8) {
        buffer[Int(a & 0xF)] = b
        comms(self, a & 0x0F, 1)
        // MARK: confirm that the 0 is not needed in the 0x0F
    }
    
    func write16(a: UInt8, b: UInt16) {
        write(a:a, b: UInt8(b >> 8))
        write(a:a+1, b: UInt8(b & 0xFF))
    }
}

class Stack {
    
    enum StackError: Error {
        case underflow
        case overflow
    }
    
    private var data = [UInt8]()
    func push8(_ val: UInt8) throws { guard data.count < 256 else { throw StackError.overflow }
        data.append(val)
    }
    
    func push16(_ val: UInt16) throws {
        guard data.count < 255 else { throw StackError.overflow }
        data.append(UInt8(val >> 8)) ; data.append(UInt8(val & 0xFF))
    }
    
    func pop8() throws -> UInt8 {
        guard let a = data.popLast() else { throw StackError.underflow }
        return a
    }
    
    func last8() throws -> UInt8 {
        guard let a = data.last else { throw StackError.underflow }
        return a
    }

    func pop16() throws -> UInt16 {
        guard let a = data.popLast(), let b = data.popLast() else { throw StackError.underflow }
            return (UInt16(b) << 8) | UInt16(a & 0xFF)
    }
    
    func last16() throws -> UInt16 {
        guard data.count > 1 else { throw StackError.underflow }
        return (UInt16(data[data.count-2]) << 8) | UInt16(data[data.count-1])
    }

}

/// Central Processing Unit
class CPU {
        
    /// A possible alternative is to define each operation as a method and then
    /// have an array of methods whose position matches their opcode.
    /// The clock tick method would then just read an opcode from memory and use it as an index into the operation array.
    /// With the retrieved method you can then just call it
    /// (using op(CPU)() because methods are curried. see http://web.archive.org/web/20201225064902/https://oleb.net/blog/2014/07/swift-instance-methods-curried-functions/)
    
    // NOTE: Any changes in the number or order of the opcodes needs to be reflected in the TEas assembler.
    // Also, exactly duplicate short opcodes so each is a fixed (0x20) offset from its byte counterpart.
    // Eg. lit16 (0x22) is exactly 0x20 from lit (0x02) and so are all the other short ops.
    enum OpCode: UInt8 {
        case brk
        case nop
        
        // stack operations
        case lit
        case pop
        case dup
        case ovr
        case rot
        case swp
        
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
        case jnz    // jump on true condition
        case jsr    // jump to subroutine
        
        // memory operations
        case bsi    // bus in
        case bso    // bus out
        
        // 16 bit operations (begin at 0x20)
        case lit16 = 0x22
        case pop16
        case dup16
        case ovr16
        case rot16
        case swp16
        
        // arithmetical operations
        case add16
        case sub16
        case mul16
        case div16
        
        // logic operations
        case equ16
        case grt16
        case neg16  // negate the top of the stack

        case jmp16 = 0x2F
        case jnz16    // jump on true condition
        case jsr16    // jump to subroutine
        
        // memory operations
        case bsi16    // bus in
        case bso16  // bus out
    }
    
    enum CPUError: Error {
    case missingParameters
    }
    
    /// Parameter stack, 256 bytes, unsigned
//    var pStack = [UInt8]()
    var pStack = Stack()
    
    /// Return stack  256 bytes, unsigned
//    var rStack = [UInt8]()
    var rStack = Stack()
    
    var pc: UInt16 = 0
    
    /// Interconnects
    var sys: System!
        
//    init(sys: System) {
//        self.sys = sys
//    }
    
    func reset() {
        pc = 0
//        pStackCounter = 0
//        rStackCounter = 0
    }
    
    func run(ticks: Int) {
        var tc = ticks
        while tc > 0 {
            try? clockTick()
            tc -= 1
        }
    }
    
    func clockTick() throws {
        
        guard pc > 0 else { return }
        
        /// since we're limiting the number of opcodes to 32 we are only using the bottom 5 bits.
        /// We can use the top three as flags for byte or short ops, copy rather than pop, and return from jump.
        /// This is where we would mask out the bottom 5 with an & 0x1F or, if we've made opcodes
        /// for both byte and shorts, the bottom 6 with ^ 0x3F
        let memval = sys.mmu.read(address: pc)

        let copyFlag = (memval & 0x40 != 0)
        /// The opcode byte layout:
        /// bytes 0, 1, 2, 3, 4 are opcode, 5 is byte or short flag, 6 is copy, 7 is stack swap
        /// If the stack swap flag is set, swap source and destination stacks
        let stackFlag = (memval & 0x80 != 0)
        var sourceStack: Stack = stackFlag ? rStack : pStack
        var targetStack: Stack = stackFlag ? pStack : rStack
        
        /// include the short flag in the opcode memory 
        let op = OpCode(rawValue: memval & 0x3F)
        if pc == 38 {
            print("stop")
        }
        print("clockTick read opcode: \(String(describing: op)) at pc \(pc)")
        if op == nil {
            print("ffs")
        }
        do {
        switch op {
        case .brk:
            pc = 0
            
        case .nop:
            pc += 1

        /// stack operations
        case .lit:
            /// next value in memory assumed to be the value to push to pstack
            pc += 1
            let lit = sys.mmu.read(address: pc)
            try pStack.push8(lit)
            pc += 1
            
        case .pop:
            let val = copyFlag ? try pStack.last8() : try pStack.pop8()
            print("popped value \(String(describing: val))")
            pc += 1

        case .dup:
            try pStack.push8(try pStack.last8())
            pc += 1
            
        case .ovr:

            let a = try pStack.pop8()
            let b = try pStack.pop8()
            
            try pStack.push8(b)
            try pStack.push8(a)
            try pStack.push8(b)
            
            pc += 1
            
        case .rot:
            
            let a = try pStack.pop8()
            let b = try pStack.pop8()
            let c = try pStack.pop8()
            
            try pStack.push8(b)
            try pStack.push8(a)
            try pStack.push8(c)

            pc += 1
            
        case .swp:
            let a = try pStack.pop8()
            let b = try pStack.pop8()

            try pStack.push8(a)
            try pStack.push8(b)
            
            pc += 1
            
        /// arithmetic operations
        case .add:
            let a = try pStack.pop8()
            let b = try pStack.pop8()

            try pStack.push8( b &+ a )
            
            pc += 1
            
        case .sub:
            let a = try pStack.pop8()
            let b = try pStack.pop8()

            try pStack.push8( b &- a )
            
            pc += 1
            
        case .mul:
            let a = try pStack.pop8()
            let b = try pStack.pop8()

            try pStack.push8( b &* a )

            pc += 1
            
        case .div:

            let a = try pStack.pop8()
            let b = try pStack.pop8()

            try pStack.push8( b / a )
            
            pc += 1
            
        /// logic operations
        case .equ:
            let a = try pStack.pop8()
            let b = try pStack.pop8()

            try pStack.push8( b == a ? 0xFF : 0 )
        
            pc += 1
            
        case .grt:
            let a = try pStack.pop8()
            let b = try pStack.pop8()

            try pStack.push8( b > a ? 0xFF : 0 )
            
            pc += 1
            
        case .neg:
            let a = try pStack.pop8()
            try pStack.push8( a == 0 ? 0xFF : 0 )
            
            pc += 1
            
        case .jmp: /// unconditional relative jump
            let a = try pStack.pop8()

            /// relative jump is default
            pc = UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a)))
            
        case .jnz: /// conditional (not zero) relative jump
            let a = try pStack.pop8()   // address offset
            let b = try pStack.pop8()   // condition

            pc = b != 0 ?UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a))) : pc + 1

        case .jsr:  /// jump to subroutine, first storing the return address on the return stack
            let a = try pStack.pop8()
            
            pc += 1 // Set the return pc to after this address.
            /// store the current pc 16 bit address as 2 x 8 bits on the return stack, msb first
            try rStack.push16(pc)
            
            pc = UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a)))
            
        // memory operations
        case .bsi:
            let a = try pStack.pop8()
            pc += 1
    
        case .bso: /// the  most significant nibble in a is the bus id and the lsn is the position in the bus.buffer that b is placed
            let a = try pStack.pop8()
            let b = try pStack.pop8()

            if let bus = sys.bus[Int(a >> 4)] {
                bus.write(a: a, b: b)
            }
            pc += 1
            
        // MARK: Implement short operations below.
        case .lit16:
            /// next value in memory assumed to be the value to push to pstack
            pc += 1
            let lit = sys.mmu.read16(address: pc)
            try pStack.push16(lit)
            pc += 2
            // MARK: is this pc right?
            
        case .pop16:
            let val = copyFlag ? try pStack.last16() : try pStack.pop16()
            
            print("popped short value \(String(describing: val))")
            pc += 1

        case .dup16:
            try pStack.push16(try pStack.last16())
            pc += 1
            
        case .ovr16:

            let a = try pStack.pop16()
            let b = try pStack.pop16()
            
            try pStack.push16(b)
            try pStack.push16(a)
            try pStack.push16(b)
            
            pc += 1
            
        case .rot16:
            
            let a = try pStack.pop16()
            let b = try pStack.pop16()
            let c = try pStack.pop16()
            
            try pStack.push16(b)
            try pStack.push16(a)
            try pStack.push16(c)

            pc += 1
            
        case .swp16:
            let a = try pStack.pop16()
            let b = try pStack.pop16()

            try pStack.push16(a)
            try pStack.push16(b)
            
            pc += 1
            
        /// arithmetic operations
        case .add16:
            let a = try pStack.pop16()
            let b = try pStack.pop16()
            
            try pStack.push16(b &+ a)
            
            pc += 1
            
        case .sub16:
            let a = try pStack.pop16()
            let b = try pStack.pop16()

            try pStack.push16( b &- a )
            
            pc += 1
            
        case .mul16:
            let a = try pStack.pop16()
            let b = try pStack.pop16()

            try pStack.push16( b &* a )

            pc += 1
            
        case .div16:

            let a = try pStack.pop16()
            let b = try pStack.pop16()

            try pStack.push16( b / a )
            
            pc += 1

        case .jmp16: /// unconditional absolute jump
            pc = try pStack.pop16()

        case .jnz16: /// conditional (not zero) absolute jump
            let a = try pStack.pop16()
            let b = try pStack.pop8()

            pc = (b == 0) ? pc + 1 : a
            
        case .jsr16:  /// jump to subroutine, first storing the return address on the return stack
            let a = try pStack.pop16()
            
            pc += 1 // Set the return pc to after this address.
            /// store the current pc 16 bit address as 2 x 8 bits on the return stack, msb first
            try rStack.push16(pc)
            
            pc = a


        case .bso16: /// the  most significant nibble in a is the bus id and the lsn is the position in the bus.buffer that b is placed
            let a = try pStack.pop8()
            let b = try pStack.pop16()
            
            if let bus = sys.bus[Int(a >> 4)] {
                bus.write16(a: a, b: b)
            }
            pc += 1
            
        default:
            print("unimplemented opcode: \(String(describing: op))")
        }
        } catch { print("ERROR: \(error)") }
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
            
            /// code will soon be generated by my TEMAsm compiler
            /// until then we place TEMA machine code directly into memory
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
            
            infLoop(addr: addr)
        }
        
        func infLoop(addr: UInt16) {
            
            
            var adr = opwrite(value: .lit, address: addr)
            
            let offset = UInt8(bitPattern: Int8(-2))
            write(value: offset, address: adr)
            adr += 1

            opwrite(value: .jmp, address: adr)
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
            
            infLoop(addr: addr)
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
            addr = opwrite(value: .jnz, address: addr)
            
            addr = opwrite(value: .pop, address: addr)
            
            infLoop(addr: addr)
        }

        func testReadWrite16() {
            clear()
            var addr: UInt16 = 0
            
            addr = opwrite(value: .lit16, address: addr)
            let writeVal: UInt16 = 365
            /// The second value is .buo's b parameter
            write16(value: writeVal, address: addr)
            

            let val = read16(address: addr)
            assert(val == writeVal)
            infLoop(addr: addr)
        }

        func testReadWrite8() {
            clear()
            var addr: UInt16 = 0
            
            addr = opwrite(value: .lit, address: addr)
            let writeVal: UInt8 = 42
            /// The second value is .buo's b parameter
            write(value: writeVal, address: addr)
            

            let val = read(address: addr)
            assert(val == writeVal)
            infLoop(addr: addr)
        }

        func testBus() {
            clear()
            var addr: UInt16 = 0

            /// --------- set x coord
            
            addr = opwrite(value: .lit16, address: addr)
            /// The second value is .buo's b parameter
            write16(value: 250, address: addr)
            addr += 2

            addr = opwrite(value: .lit, address: addr)
            /// The first value is buo's first parameter:
            /// The top 4 bits of a are the bus id, bottom 4 bits are the index in the bus.buffer
            /// Since we're writing to the display we know it expects the x parameter in bus.buffer[0x8]
            /// and the y parameter in bus.buffer[0xA]
            /// 0x8 is the pixel x position
            write(value: (Bus.Device.display.rawValue << 4) | 0x8, address: addr)
            addr += 1
            
            // expects a byte and a short on the stack
            addr = opwrite(value: .bso16, address: addr)

            /// --------- set y coord
            
            addr = opwrite(value: .lit16, address: addr)
            write16(value: 150, address: addr)
            addr += 2

            addr = opwrite(value: .lit, address: addr)
            
            /// 0xA is the pixel y position
            write(value: (Bus.Device.display.rawValue << 4) | 0xA, address: addr)
            addr += 1

            addr = opwrite(value: .bso16, address: addr)

            /// ---------  set the pixel color
            
            addr = opwrite(value: .lit, address: addr)
            write(value: 2, address: addr)
            addr += 1

            addr = opwrite(value: .lit, address: addr)
            /// 0xE is the pixel value and the signal to the display to push the pixel
            write(value: (Bus.Device.display.rawValue << 4) | 0xE, address: addr)
            addr += 1

            addr = opwrite(value: .bso, address: addr)

            infLoop(addr: addr)
        }
//        test42()
//        testRot()
//        testOvr()
//        testLoop()
//        testReadWrite8()
        testBus()
    }

    func clear() {
        bank = [UInt8](repeating: 0, count: 65536)
    }
    
    func write16(value: UInt16, address: UInt16) {
        write(value: UInt8(value >> 8), address: address)
        write(value: UInt8(value & 0xFF), address: address+1)
    }
    
    func write(value: UInt8, address: UInt16) {
        bank[Int(address)] = value
    }

    func read16(address: UInt16) -> UInt16 {
        return (UInt16(bank[Int(address)]) << 8) | UInt16(bank[Int(address+1)])
    }

    func read(address: UInt16) -> UInt8 {
        return bank[Int(address)]
    }
}
