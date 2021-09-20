//
//  MouseTracking.swift
//  MouseTracking
//
//  Created by teo on 25/08/2021.
//

import SwiftUI

// Crufty wrappers to patch SwiftUI's inability to capture mouse coordinates
// from http://web.archive.org/web/20210128040331/https://swiftui-lab.com/a-powerful-combo/

extension View {
//    func trackingMouse(onMove: @escaping (NSPoint) -> Void) -> some View {
//        TrackingAreaView(onMove: onMove) { self }
//    }
    func trackingMouse(onEvent: @escaping (NSEvent) -> Void) -> some View {
        TrackingAreaView(onEvent: onEvent) { self }
    }

}

struct TrackingAreaView<Content>: View where Content : View {
//    let onMove: (NSPoint) -> Void
    let onEvent: (NSEvent) -> Void
    let content: () -> Content
    
    init(onEvent: @escaping (NSEvent) -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.onEvent = onEvent
        self.content = content
    }

//    init(onMove: @escaping (NSPoint) -> Void, @ViewBuilder content: @escaping () -> Content) {
//        self.onMove = onMove
//        self.content = content
//    }
    
    var body: some View {
//        TrackingAreaRepresentable(onMove: onMove, content: self.content())
        TrackingAreaRepresentable(onEvent: onEvent, content: self.content())
    }
}

struct TrackingAreaRepresentable<Content>: NSViewRepresentable where Content: View {
//    let onMove: (NSPoint) -> Void
    let onEvent: (NSEvent) -> Void
    let content: Content
    
    func makeNSView(context: Context) -> NSHostingView<Content> {
//        return TrackingNSHostingView(onMove: onMove, rootView: self.content)
        return TrackingNSHostingView(onEvent: onEvent, rootView: self.content)
    }
    
    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
    }
}

class TrackingNSHostingView<Content>: NSHostingView<Content> where Content : View {
//    let onMove: (NSPoint) -> Void
    let onEvent: (NSEvent) -> Void
    
    init(onEvent: @escaping (NSEvent) -> Void, rootView: Content) {
//        self.onMove = onMove
        self.onEvent = onEvent
        
        super.init(rootView: rootView)
        
        setupTrackingArea()
    }
    
    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @MainActor required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }
    
    func setupTrackingArea() {
        let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        self.addTrackingArea(NSTrackingArea.init(rect: .zero, options: options, owner: self, userInfo: nil))
    }
          
    override func mouseMoved(with event: NSEvent) {
//        self.onMove(self.convert(event.locationInWindow, from: nil))
        self.onEvent(event)
    }
    
    override func mouseDown(with event: NSEvent) {
//        print("mouse down \(event.buttonNumber)")
        self.onEvent(event)
    }
    
    override func mouseUp(with event: NSEvent) {
//        print("mouse up")
        self.onEvent(event)
    }
    
    override func mouseDragged(with event: NSEvent) {
//        print("mouse dragging \(event.locationInWindow)")
        self.onEvent(event)
    }
    
    override func scrollWheel(with event: NSEvent) {
//        print("Scrollwheeeee \(event.scrollingDeltaX) \(event.scrollingDeltaY)")
        self.onEvent(event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
//        print("rmb down \(event.buttonNumber)")
        self.onEvent(event)
    }
    override func rightMouseUp(with event: NSEvent) {
//        print("rmb up")
        self.onEvent(event)
    }
    
    override func rightMouseDragged(with event: NSEvent) {
//        print("rmb dragging \(event.type)")
        self.onEvent(event)
    }
}
