//
//  TEMA.swift
//  TEMA
//
//  Created by teo on 24/07/2021.
//

import Foundation
import AppKit

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
        print("Registered bus: \(id) \(name) at \(id.rawValue << 4)")
        let newbus = Bus(id: id, owner: self, comms: comms)
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
    
    func tests() {
        func testStack() throws {
            try cpu.pStack.push8(42)
            let val = try cpu.pStack.pop8()
            print("stack popped \(val)")
            try cpu.pStack.push8(42)
            try cpu.pStack.push8(69)
            try cpu.pStack.push8(33)
            let a = try cpu.pStack.popCopy8()
            let b = try cpu.pStack.popCopy8()
            let c = try cpu.pStack.pop8()
            print("stack popped a: \(a), b: \(b), c: \(c)")
            
            try cpu.pStack.push8(42)
            try cpu.pStack.push8(69)
            try cpu.pStack.push8(33)
            let d = try cpu.pStack.popCopy8()
            try cpu.pStack.push8(88)
            let e = try cpu.pStack.popCopy8()
            let f = try cpu.pStack.pop8()
            print("stack popped d: \(d), e: \(e), f: \(f)")
        }
        
        func testStackLimit() throws {
            // first make sure stack size is set to 3
            try cpu.pStack.push8(42)
            try cpu.pStack.push8(42)
            try cpu.pStack.push8(69)
//            try cpu.pStack.push8(33)    // uncomment this line to get an overflow error
            
//            _ = try cpu.pStack.pop8()
//            _ = try cpu.pStack.pop8()
//            _ = try cpu.pStack.pop8()
//            _ = try cpu.pStack.pop8()   // uncomment this line to get an underflow error
            
            let _ = try cpu.pStack.popCopy8()
            let _ = try cpu.pStack.popCopy8()
            let _ = try cpu.pStack.popCopy8()
//            let _ = try cpu.pStack.popCopy8() // uncomment this line to get an underflow error
        }

        func testStackLimit16() throws {
            // first make sure stack size is set to 3
            try cpu.pStack.push16(360)
//            try cpu.pStack.push16(420)    // uncomment this line to get an overflow error
            
//            _ = try cpu.pStack.pop16()
//            _ = try cpu.pStack.pop16()   // uncomment this line to get an underflow error
            
            let _ = try cpu.pStack.popCopy16()
//            let _ = try cpu.pStack.popCopy16() // uncomment this line to get an underflow error
        }

        do {
//            try testStack()
            try testStackLimit16()
        } catch {
            print("TEma tests failed with \(error)")
        }
    }
}

/// Bus between devices
class Bus {
    let address: UInt8  // a bus is referenced via a particular address in TEma RAM: Device id * 0x10
    let owner: System
    let comms: ((Bus, UInt8, UInt8)->(Void))
    // The position in the buffer represents a particular "port" for the device we're communicating with
    // eg. on a console bus 0x2 is the read port and 0x8 is write port.
    var buffer = [UInt8](repeating: 0, count: 16)
    
    enum Device: UInt8 {
        case system
        case console
        case display
        case audio
        case controller1 = 0x8
        case mouse
        case file = 0xA0
    }
    
    init(id: Device, owner: System, comms: @escaping (Bus, UInt8, UInt8)->(Void)) {
        self.address = id.rawValue * 0x10
        self.owner = owner
        self.comms = comms
    }
    
    
    func busRead(a: UInt8) -> UInt8 {
        comms(self, a & 0x0F, 0)
        return buffer[Int(a & 0xF)]
    }
    
    func busRead16(a: UInt8) -> UInt16 {
        return UInt16(busRead(a: a)) << 8 | UInt16(busRead(a: a + 1))
    }
    
    func busWrite(a: UInt8, b: UInt8) {
        buffer[Int(a & 0xF)] = b
        comms(self, a & 0x0F, 1)
        // MARK: confirm that the 0 is not needed in the 0x0F
    }
    
    func busWrite16(a: UInt8, b: UInt16) {
        busWrite(a:a, b: UInt8(b >> 8))
        busWrite(a:a+1, b: UInt8(b & 0xFF))
    }
}

class Stack {
        
    enum StackError: Error {
        case underflow
        case overflow
    }
    
    static let stBytes = 256
    private var data = [UInt8](repeating: 0, count: stBytes)
    var count = 0
    var copyIdx = 0

    func push8(_ val: UInt8) throws {
        guard count < Stack.stBytes else { throw StackError.overflow }
        data[count] = val
        count += 1
        copyIdx = count
    }
    
    func push16(_ val: UInt16) throws {
        guard count < Stack.stBytes-1 else { throw StackError.overflow }
        try push8(UInt8(val >> 8)) ; try push8(UInt8(val & 0xFF))
    }
    
    func pop8() throws -> UInt8 {
        guard count > 0 else { throw StackError.underflow }
        count -= 1
        copyIdx = count
        return data[count]
    }
    
    func popCopy8() throws -> UInt8 {
        guard copyIdx > 0 else { throw StackError.underflow }
        copyIdx -= 1
        return data[copyIdx]
    }

    func pop16() throws -> UInt16 {
        let a = try pop8() ; let b = try pop8()
        return (UInt16(b) << 8) | UInt16(a & 0xFF)
    }
    
    func popCopy16() throws -> UInt16 {
        let a = try popCopy8() ; let b = try popCopy8()
        return (UInt16(b) << 8) | UInt16(a)
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
        case sts    // stack to stack transfer
        
        // arithmetical operations
        case add
        case sub
        case mul
        case div
        
        // bitwise logic
        case and
        case ior
        case xor
        case shi

        // logic operations
        case equ
        case neq
        case grt
        case lst
        /// there is always  a trade-off between space and time; we can have a single equality and a single greater than operator and
        /// achieve its complements by having a negation operation, but this comes at the cost of run-time complexity where each of
        /// these tests would require two ops and two cycles instead of one. After consideration i have decided, since there is room for it,
        /// to have two more operations.
//        case neg    // negate the top of the stack
        case jmp    // jump unconditinally
        case jnz    // jump on true condition
        case jsr    // jump to subroutine
        
        // memory operations (the stack can be parameter or return stack depending on the return flag of the opcode)
        case lda    // load byte value from absoute address to stack
        case sta    // store byte value on top of stack at absolute address
        case ldr    // load byte value from relative address to stack
        case str    // store byte value from top of stack at relative address
        case bsi    // bus in
        case bso    // bus out
        
        // 16 bit operations (begin at 0x20)
        case lit16 = 0x22
        case pop16
        case dup16
        case ovr16
        case rot16
        case swp16
        case sts16
        
        // arithmetical operations
        case add16
        case sub16
        case mul16
        case div16
        
        // bitwise logic
        case and16
        case ior16
        case xor16
        case shi16

        // logic operations
        case equ16
        case neq16
        case grt16
        case lst16
//        case neg16  // negate the top of the stack

        case jmp16 //= 0x2F
        case jnz16    // jump on true condition
        case jsr16    // jump to subroutine
        
        // memory operations
        case lda16      // load short value from absoute address
        case sta16      // store short value at absolute address
        case ldr16      // load short value from relative address
        case str16      // store short value at relative address
        case bsi16    // bus in
        case bso16  // bus out
    }
    
    enum CPUError: Error {
    case missingParameters
        case pcBrk
        case invalidInterrrupt
    }
    
    /// Parameter stack, 256 bytes, unsigned
    var pStack = Stack()
    
    /// Return stack  256 bytes, unsigned
    var rStack = Stack()
    
    var pc: UInt16 = 0
    
    /// Interconnects
    var sys: System!
        
    
    func reset() {
        pc = 0
        pStack.count = 0
        rStack.count = 0
        pStack.copyIdx = 0
        rStack.copyIdx = 0
    }
    
    func run(ticks: Int) {
        var tc = ticks
        while tc > 0 {
            try? clockTick()
            tc -= 1
        }
    }
    
    // the interrupt master enable is in ram so that the interrupt function can access it without needing a special opcode (like RETI on GBA)
    let interruptMasterEnable: UInt16  = 0x00B0       // just after the bus addresses - by convention, so subject to change
    var interruptFlags: UInt8 = 0
    
    // caller must ensure these are not called concurrently. Perhaps not use interrupts next time?
    func interruptEnable(bus: Bus) {
        let IME = sys.mmu.read(address: interruptMasterEnable)
        guard IME == 1 else { return }
        // signal that an interrupt is now in progress. Must be reset by the interrupt function.
        sys.mmu.write(value: 0, address: interruptMasterEnable)
        
        // set the appropriate flag for the given bus. Only one for now.
        interruptFlags = bus.address >> 4
    }
    
    var dbgTickCount = 0
    
    func clockTick() throws {
        
        // service interrupt requests
        if interruptFlags != 0 {
            let IME = sys.mmu.read(address: interruptMasterEnable)
            guard IME == 0 else { return }
            
            guard let bus = sys.bus[Int(interruptFlags & 0xFF)] else { throw CPUError.invalidInterrrupt }
            interruptFlags = 0
            
            try rStack.push16(pc)
            let intvec = read16(mem: &bus.buffer, address: 0)
            pc = intvec
        }
        
        guard pc > 0 else { throw CPUError.pcBrk }
        
        /// since we're limiting the number of opcodes to 32 we are only using the bottom 5 bits.
        /// We can use the top three as flags for byte or short ops, copy rather than pop, and return from jump.
        /// This is where we would mask out the bottom 5 with an & 0x1F or, if we've made opcodes
        /// for both byte and shorts, the bottom 6 with ^ 0x3F
        let memval = sys.mmu.read(address: pc)

        let copyFlag = (memval & 0x40 != 0)
        /// This is trying to deal with the case where a copy flag persists between non-copy calls. Is it ok that both p and r stacks are reset when either is used without the copy flag?
        if copyFlag == false { rStack.copyIdx = rStack.count ; pStack.copyIdx = pStack.count } // MARK: not sure this is 100%
        let pop8: ((Stack) throws -> UInt8) = copyFlag ? { stack in try stack.popCopy8() } : { stack in try stack.pop8() }
        let pop16: ((Stack) throws -> UInt16) = copyFlag ? { stack in try stack.popCopy16() } : { stack in try stack.pop16() }
        
        /// The opcode byte layout:
        /// bytes 0, 1, 2, 3, 4 are opcode, 5 is byte or short flag, 6 is copy, 7 is stack swap
        /// If the stack swap flag is set, swap source and destination stacks
        let stackFlag = (memval & 0x80 != 0)
        let sourceStack: Stack = stackFlag ? rStack : pStack
        let targetStack: Stack = stackFlag ? pStack : rStack
        
        /// include the short flag in the opcode memory 
        let op = OpCode(rawValue: memval & 0x3F)
        dbgTickCount += 1
//        if dbgTickCount == 195 {
//            print("stop")
//        }
//        if pc == 0x034D { //0x0310 {
//            print("break")
//        }
        //print("clockTick \(dbgTickCount): read opcode: \(String(describing: op)) at pc \(pc)")
        if op == nil { fatalError("op is nil") }
        do {
        switch op {
        case .brk:
            pc =  0
            
        case .nop:
            pc += 1

            
        /// stack operations
        case .lit:
            /// next value in memory assumed to be the value to push to pstack
            pc += 1
            let lit = sys.mmu.read(address: pc)
            try sourceStack.push8(lit)
            pc += 1
            
        case .pop:

            _ = try pop8(sourceStack)
//            let val = try pop8(sourceStack)
//            print("popped value \(String(describing: val))")
            pc += 1

        case .dup:
            let val = try pop8(sourceStack)
            try sourceStack.push8(val)
            try sourceStack.push8(val)
            pc += 1
            
        case .ovr: // ( b a -- b a b )
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8(b)
            try sourceStack.push8(a)
            try sourceStack.push8(b)
            
            pc += 1
            
        case .rot: // ( c b a -- b a c )
            
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)
            let c = try pop8(sourceStack)

            try sourceStack.push8(b)
            try sourceStack.push8(a)
            try sourceStack.push8(c)

            pc += 1
            
        case .swp:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8(a)
            try sourceStack.push8(b)
            
            pc += 1

        case .sts:  // stack to stack transfer
            let a  = try pop8(sourceStack)
            try targetStack.push8(a)
            
            pc += 1

        /// arithmetic operations
        case .add:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b &+ a )
            
            pc += 1
            
        case .sub:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b &- a )
            
            pc += 1
            
        case .mul:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b &* a )

            pc += 1
            
        case .div:

            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b / a )
            
            pc += 1
            
        /// bitwise logic
        case .and:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b & a )
            pc += 1

        case .ior:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b | a )
            pc += 1
            
        case .xor:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b ^ a )
            pc += 1
            
        case .shi: // ( value bitshift -- result )
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)
            /// use the three least significant bits of the most significant nibble of a to shift up by 0 to 7 bits (the max needed for a byte) and
            /// use the three least significant bits of the least significant nibble of a to shift down by 0 to 7 bits.
            try sourceStack.push8((b >> (a & 0x07)) << ((a & 0x70) >> 4))
            pc += 1
            
        /// logic operations
        case .equ:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b == a ? 0xFF : 0 )
            pc += 1

        case .neq:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b != a ? 0xFF : 0 )
            pc += 1

        case .grt:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b > a ? 0xFF : 0 )
            
            pc += 1

        case .lst:
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            try sourceStack.push8( b < a ? 0xFF : 0 )
            
            pc += 1

//        case .neg:
//            let a = try pStack.pop8()
//            try pStack.push8( a == 0 ? 0xFF : 0 )
//
//            pc += 1
            
        case .jmp: /// unconditional relative jump
            let a = try pop8(sourceStack)

            /// relative jump is default
            pc = UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a)))
            
        case .jnz: /// conditional (not zero) relative jump
            let a = try pop8(sourceStack)   // address offset
            let b = try pop8(sourceStack)   // condition

            pc = b != 0 ?UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a))) : pc + 1

        case .jsr:  /// jump to subroutine at offset, first storing the return address on the return stack
            let a = try pop8(sourceStack)
            
            /// store the current pc 16 bit address as 2 x 8 bits on the return stack, msb first
            try targetStack.push16(pc+1)
            
            pc = UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a)))
            
        // memory operations
// NOTE:           write 16 bit versions and use the sourcestack to allow use of the returnstack given the flag setting.
        case .lda:  // load the byte at the given absolute address onto the top of the parameter stack.
            let a = try pop16(sourceStack)
            try sourceStack.push8(sys.mmu.read(address: a))
            pc += 1
            
        case .sta:  // ( value addr -- ) store the byte on top of the parameter stack to the given absolute address.
            let a = try pop16(sourceStack)
            let b = try pop8(sourceStack)
            sys.mmu.write(value: b, address: a)
            pc += 1
            
        case .ldr:  // load the byte at the given relative address onto the top of the parameter stack.
            let a = try pop8(sourceStack)
            try sourceStack.push8(sys.mmu.read(address: UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a)))))
            pc += 1
            
        case .str: // ( value addr -- ) store the byte on top of the parameter stack to the given relative address.
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)
            sys.mmu.write(value: b, address: UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a))))
            pc += 1
            
        case .bsi:
            let a = try pop8(sourceStack)
            if let bus = sys.bus[Int(a >> 4)] {
                try sourceStack.push8(bus.busRead(a: a))
            }
            pc += 1
    
        case .bso: /// the  most significant nibble in a is the bus id and the lsn is the position in the bus.buffer (the port) that b is placed
            let a = try pop8(sourceStack)
            let b = try pop8(sourceStack)

            if let bus = sys.bus[Int(a >> 4)] {
                bus.busWrite(a: a, b: b)
            }
            pc += 1
            
        // MARK: Implement short operations below.
        case .lit16:
            /// next value in memory assumed to be the value to push to pstack
            pc += 1
            let lit = sys.mmu.read16(address: pc)
            try sourceStack.push16(lit)
            pc += 2
            // MARK: is this pc right?
            
        case .pop16:
//            _ = try pop16(sourceStack)
            let val = try pop16(sourceStack)
            print("popped short value \(String(describing: val))")
            pc += 1

        case .dup16:
            try sourceStack.push16(try sourceStack.popCopy16())
            pc += 1
            
        case .ovr16:

            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)
            
            try sourceStack.push16(b)
            try sourceStack.push16(a)
            try sourceStack.push16(b)
            
            pc += 1
            
        case .rot16:
            
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)
            let c = try pop16(sourceStack)
            
            try sourceStack.push16(b)
            try sourceStack.push16(a)
            try sourceStack.push16(c)

            pc += 1
            
        case .swp16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push16(a)
            try sourceStack.push16(b)
            
            pc += 1
            
        case .sts16: // stack to stack transfer
            let a = try pop16(sourceStack)
            try targetStack.push16(a)
            
            pc += 1


        /// arithmetic operations
        case .add16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)
            
            try sourceStack.push16(b &+ a)
            
            pc += 1
            
        case .sub16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push16( b &- a )
            
            pc += 1
            
        case .mul16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push16( b &* a )

            pc += 1
            
        case .div16:

            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push16( b / a )
            
            pc += 1

        case .and16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push16( b & a )
            pc += 1
            
        case .ior16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push16( b | a )
            pc += 1
            
        case .xor16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push16( b ^ a )
            pc += 1
            
        case .shi16: // ( value bitshift -- result )
            let a = try pop8(sourceStack)
            let b = try pop16(sourceStack)
            /// use the four least significant bits of the most significant nibble of a to shift up by 0 to f bits (the max needed for a short) and
            /// use the four least significant bits of the least significant nibble of a to shift down by 0 to f bits.
            try sourceStack.push16((b >> (a & 0x0f)) << ((a & 0xf0) >> 4))
            pc += 1
            
        /// logic operations
        case .equ16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push8( b == a ? 0xFF : 0 )
            pc += 1

        case .neq16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push8( b != a ? 0xFF : 0 )
            pc += 1

        case .grt16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push8( b > a ? 0xFF : 0 )
            
            pc += 1

        case .lst16:
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)

            try sourceStack.push8( b < a ? 0xFF : 0 )
            
            pc += 1

//        case .neg16:
//            let a = try sourceStack.pop16()
//            try sourceStack.push8( a == 0 ? 0xFF : 0 )
//
//            pc += 1
        
        case .jmp16: /// unconditional absolute jump
            pc = try pop16(sourceStack)

        case .jnz16: /// conditional (not zero) absolute jump
            let a = try pop16(sourceStack)
            let b = try pop8(sourceStack)

            pc = (b == 0) ? pc + 1 : a
            
        case .jsr16:  /// jump to subroutine at absolute address, first storing the return address on the return stack
            let a = try pop16(sourceStack)
            
            /// store the current pc 16 bit address as 2 x 8 bits on the return stack, msb first
            try targetStack.push16(pc+1)
            
            pc = a
            
        // NOTE: Test these
        case .lda16:  // load the short at the given absolute address onto the top of the parameter stack.
            let a = try pop16(sourceStack)
            try sourceStack.push16(sys.mmu.read16(address: a))
            pc += 1
            
        case .sta16:  // ( value addr -- ) store the short on top of the parameter stack to the given absolute address.
            let a = try pop16(sourceStack)
            let b = try pop16(sourceStack)
            sys.mmu.write16(value: b, address: a)
            pc += 1
            
        case .ldr16:  // load the short at the given relative address onto the top of the parameter stack.
            let a = try pop8(sourceStack)
            try sourceStack.push16(sys.mmu.read16(address: UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a)))))
            pc += 1
            
        case .str16: // ( value addr -- ) store the short on top of the parameter stack to the given relative address.
            let a = try pop8(sourceStack)
            let b = try pop16(sourceStack)
            sys.mmu.write16(value: b, address: UInt16(bitPattern: Int16(bitPattern: pc) + Int16(Int8(bitPattern: a))))
            pc += 1

        case .bsi16: // NB: untested
            let a = try pop8(sourceStack)
            if let bus = sys.bus[Int(a >> 4)] {
                try sourceStack.push16(bus.busRead16(a: a))
            }
            pc += 1

        case .bso16: /// the  most significant nibble in a is the bus id and the lsn is the position in the bus.buffer that b is placed
            let a = try pop8(sourceStack)
            let b = try pop16(sourceStack)
            
            if let bus = sys.bus[Int(a >> 4)] {
                bus.busWrite16(a: a, b: b)
            }
            pc += 1
            
        default:
            print("unimplemented opcode: \(String(describing: op))")
        }
        } catch {
            print("ERROR: \(error)")
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

            addr = opwrite(value: .neq, address: addr)
//            addr = opwrite(value: .equ, address: addr)
//
//            addr = opwrite(value: .neg, address: addr)

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

func write16(mem: inout [UInt8], value: UInt16, address: UInt16) {
    write(mem: &mem, value: UInt8(value >> 8), address: address)
    write(mem: &mem, value: UInt8(value & 0xFF), address: address+1)
}

func write(mem: inout [UInt8], value: UInt8, address: UInt16) {
    mem[Int(address)] = value
}

func read16(mem: inout [UInt8], address: UInt16) -> UInt16 {
    return (UInt16(mem[Int(address)]) << 8) | UInt16(mem[Int(address+1)])
}

func read(mem: inout [UInt8], address: UInt16) -> UInt8 {
    return mem[Int(address)]
}
