import SwiftUI
import Combine
import Network
import UIKit

// MARK: - MOTORE DI RETE (Versione Corazzata 360°)
class XPlaneConnection: ObservableObject {
    @Published var xplaneIP: String = UserDefaults.standard.string(forKey: "xplaneIP_Saved") ?? "127.0.0.1" {
        didSet {
            UserDefaults.standard.set(xplaneIP, forKey: "xplaneIP_Saved")
            restartNetwork()
        }
    }
    
    let targetPort: NWEndpoint.Port = 49000
    let localPort: NWEndpoint.Port = 49050
    
    private var connection: NWConnection?
    private var listener: NWListener?
    
    // TELEMETRIA
    @Published var elevatorTrim: Double = 0.0
    @Published var altitudeDial: Double = 0.0
    @Published var aircraftHeading: Double = 0.0
    @Published var targetHeading: Double = 0.0
    
    @Published var apMode: Int = 0
    @Published var hdgStatus: Int = 0
    @Published var navStatus: Int = 0
    @Published var aprStatus: Int = 0
    @Published var altStatus: Int = 0
    @Published var vsStatus: Int = 0

    private var lastHeading: Double = 0.0

    init() { restartNetwork() }

    private func restartNetwork() {
        connection?.cancel()
        listener?.cancel()
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: params, on: localPort)
            listener?.newConnectionHandler = { [weak self] newConn in
                newConn.start(queue: .global())
                self?.receiveLoop(on: newConn)
            }
            listener?.start(queue: .global())
        } catch { print("🔴 ERRORE RICEVITORE") }
        
        let sendParams = NWParameters.udp
        sendParams.allowLocalEndpointReuse = true
        sendParams.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.any), port: localPort)
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(xplaneIP), port: targetPort)
        connection = NWConnection(to: endpoint, using: sendParams)
        connection?.stateUpdateHandler = { [weak self] state in
            if state == .ready { self?.subscribeAll() }
        }
        connection?.start(queue: .global())
    }

    func sendCommand(_ command: String) {
        guard let conn = connection else { return }
        var data = "CMND\0".data(using: .utf8)!
        data.append(command.data(using: .utf8)!)
        conn.send(content: data, completion: .idempotent)
    }

    func sendDREF(_ dataref: String, value: Float) {
        guard let conn = connection else { return }
        var data = "DREF\0".data(using: .utf8)!
        var val = value
        withUnsafeBytes(of: val) { data.append(contentsOf: $0) }
        var nameData = dataref.data(using: .utf8)!
        nameData.append(0)
        data.append(nameData)
        let padding = 509 - data.count
        if padding > 0 { data.append(contentsOf: [UInt8](repeating: 0, count: padding)) }
        conn.send(content: data, completion: .idempotent)
    }

    private func subscribeAll() {
        let list = [
            ("sim/cockpit2/controls/elevator_trim", 1),
            ("sim/cockpit2/autopilot/flight_director_mode", 2),
            ("sim/cockpit2/autopilot/heading_status", 3),
            ("sim/cockpit2/autopilot/nav_status", 4),
            ("sim/cockpit2/autopilot/approach_status", 5),
            ("sim/cockpit2/autopilot/altitude_hold_status", 6),
            ("sim/cockpit2/autopilot/vvi_status", 7),
            ("sim/cockpit2/autopilot/altitude_dial_ft", 8),
            ("sim/cockpit2/gauges/indicators/heading_vacuum_deg_mag", 9),
            ("sim/cockpit2/autopilot/heading_dial_deg_mag_pilot", 10)
        ]
        for item in list { sendSubscribe(item.0, index: Int32(item.1)) }
    }

    private func sendSubscribe(_ dataref: String, index: Int32) {
        guard let conn = connection else { return }
        var packet = Data("RREF\0".utf8)
        var freq = Int32(15).littleEndian // Alzata frequenza per fluidità
        var idx = index.littleEndian
        packet.append(Data(bytes: &freq, count: 4))
        packet.append(Data(bytes: &idx, count: 4))
        var name = dataref.data(using: .utf8)!
        name.append(0)
        name.append(Data(repeating: 0, count: 400 - name.count))
        packet.append(name)
        conn.send(content: packet, completion: .idempotent)
    }

    private func receiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data = data, data.count >= 5 {
                var offset = 5
                while offset + 8 <= data.count {
                    let idx = data[offset..<(offset+4)].withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
                    let val = data[(offset+4)..<(offset+8)].withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
                    
                    DispatchQueue.main.async {
                        switch idx {
                        case 1: self?.elevatorTrim = Double(val)
                        case 2: self?.apMode = Int(val)
                        case 3: self?.hdgStatus = Int(val)
                        case 4: self?.navStatus = Int(val)
                        case 5: self?.aprStatus = Int(val)
                        case 6: self?.altStatus = Int(val)
                        case 7: self?.vsStatus = Int(val)
                        case 8: self?.altitudeDial = Double(val)
                        case 9:
                            // FILTRO RUMORE: Se X-Plane manda uno zero improvviso (e non siamo a Nord), ignoralo
                            if val == 0 && self?.lastHeading ?? 0 > 10 && self?.lastHeading ?? 0 < 350 { return }
                            self?.aircraftHeading = Double(val)
                            self?.lastHeading = Double(val)
                        case 10: self?.targetHeading = Double(val)
                        default: break
                        }
                    }
                    offset += 8
                }
            }
            if error == nil { self?.receiveLoop(on: conn) }
        }
    }
}

// MARK: - UI PRINCIPALE
struct ContentView: View {
    @StateObject var xplane = XPlaneConnection()
    @State private var showSettings = false
    let panelColor = Color(red: 0.22, green: 0.23, blue: 0.25)

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.13, blue: 0.15).ignoresSafeArea()
            
            VStack(spacing: 15) {
                HStack {
                    Text("BENDIX MASTER CONTROL").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.gray)
                    Spacer()
                    Button(action: { showSettings = true }) { Image(systemName: "gear").foregroundColor(.gray) }
                }.padding(.horizontal).padding(.top, 5)

                // 1. AUTOPILOTA
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        HardwareButton(title: "AP", isOn: xplane.apMode == 2) { xplane.sendCommand("sim/autopilot/servos_toggle") }
                        HardwareButton(title: "HDG", isOn: xplane.hdgStatus > 0) { xplane.sendCommand("sim/autopilot/heading") }
                        HardwareButton(title: "NAV", isOn: xplane.navStatus > 0) { xplane.sendCommand("sim/autopilot/NAV") }
                        HardwareButton(title: "APR", isOn: xplane.aprStatus > 0) { xplane.sendCommand("sim/autopilot/approach") }
                    }
                    HStack(spacing: 8) {
                        HardwareButton(title: "ALT", isOn: xplane.altStatus > 0) { xplane.sendCommand("sim/autopilot/altitude_hold") }
                        HardwareButton(title: "VS", isOn: xplane.vsStatus > 0) { xplane.sendCommand("sim/autopilot/vertical_speed") }
                        HardwareButton(title: "UP", isOn: false) { xplane.sendCommand("sim/autopilot/nose_up") }
                        HardwareButton(title: "DN", isOn: false) { xplane.sendCommand("sim/autopilot/nose_down") }
                    }
                }
                .padding(12).background(panelColor).cornerRadius(15).shadow(radius: 10).padding(.horizontal)

                // 2. ALTITUDINE E TRIM (RIPRISTINATI)
                HStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Text("ALTITUDE").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                        HStack(spacing: 6) {
                            AltStepControl(label: "1000", step: 1000, xplane: xplane)
                            VStack {
                                Text("\(Int(xplane.altitudeDial))").font(.system(size: 18, weight: .black, design: .monospaced)).foregroundColor(.orange).shadow(color: .orange.opacity(0.8), radius: 4)
                            }
                            .frame(width: 70, height: 45).background(Color.black).cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.3)))
                            AltStepControl(label: "100", step: 100, xplane: xplane)
                        }
                    }.padding(10).background(panelColor).cornerRadius(15).shadow(radius: 5)
                    
                    InteractiveTrimView(xplane: xplane)
                }.padding(.horizontal)

                // 3. BUSSOLA HSI (FIX 360°)
                VStack(spacing: 8) {
                    CompassView(xplane: xplane)
                    HStack(spacing: 10) {
                        Button("-10°") { updateHdg(-10) }.buttonStyle(SmallHardwareButtonStyle())
                        Button("-1°") { updateHdg(-1) }.buttonStyle(SmallHardwareButtonStyle())
                        Text(String(format: "%03d°", Int(xplane.targetHeading))).foregroundColor(.orange).font(.system(size: 18, weight: .bold, design: .monospaced))
                        Button("+1°") { updateHdg(1) }.buttonStyle(SmallHardwareButtonStyle())
                        Button("+10°") { updateHdg(10) }.buttonStyle(SmallHardwareButtonStyle())
                    }
                }
                .padding(12).background(panelColor).cornerRadius(20).shadow(radius: 15).padding(.horizontal)
                
                Spacer()
            }
        }.sheet(isPresented: $showSettings) { SettingsView(xplane: xplane) }
    }
    
    func updateHdg(_ delta: Double) {
        var newHdg = xplane.targetHeading + delta
        if newHdg < 0 { newHdg += 360 }
        if newHdg >= 360 { newHdg -= 360 }
        xplane.sendDREF("sim/cockpit2/autopilot/heading_dial_deg_mag_pilot", value: Float(newHdg))
    }
}

// MARK: - COMPASS VIEW (Sincronizzazione Angolare Continua)
struct CompassView: View {
    @ObservedObject var xplane: XPlaneConnection
    
    // Calcoliamo la rotazione continua per evitare lo "spin" a 360 gradi
    @State private var continuousRotation: Double = 0.0
    @State private var lastRawHeading: Double = 0.0

    var body: some View {
        ZStack {
            Circle().fill(.black).frame(width: 150, height: 150).overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 2))
            
            ZStack {
                // ROSA DEI VENTI
                ForEach(0..<12) { i in
                    let angle = Double(i) * 30
                    Text(getHeadingLabel(angle)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white).offset(y: -55).rotationEffect(.degrees(angle))
                }
                ForEach(0..<72) { i in
                    Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: i % 6 == 0 ? 8 : 4).offset(y: -68).rotationEffect(.degrees(Double(i) * 5))
                }
                // BUG HDG
                VStack {
                    Rectangle().fill(.orange).frame(width: 10, height: 6)
                    Image(systemName: "triangle.fill").resizable().frame(width: 10, height: 6).foregroundColor(.orange).rotationEffect(.degrees(180))
                    Spacer()
                }.frame(height: 140).rotationEffect(.degrees(xplane.targetHeading))
            }
            .rotationEffect(.degrees(continuousRotation))
            .onAppear { continuousRotation = -xplane.aircraftHeading }
            .onChange(of: xplane.aircraftHeading) { newHeading in
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Logica per trovare la strada più breve (Shortest Path Rotation)
                    let diff = newHeading - lastRawHeading
                    var delta = diff
                    if diff > 180 { delta -= 360 }
                    else if diff < -180 { delta += 360 }
                    continuousRotation -= delta
                    lastRawHeading = newHeading
                }
            }
            
            Image(systemName: "airplane").resizable().scaledToFit().frame(width: 30, height: 30).foregroundColor(.yellow).rotationEffect(.degrees(-90))
            Rectangle().fill(.yellow).frame(width: 2, height: 12).offset(y: -68)
        }
    }
    
    func getHeadingLabel(_ angle: Double) -> String {
        let dict = [0:"N", 90:"E", 180:"S", 270:"W"]
        return dict[Int(angle)] ?? "\(Int(angle/10))"
    }
}

// MARK: - ALTRI COMPONENTI
struct AltStepControl: View {
    let label: String; let step: Double; @ObservedObject var xplane: XPlaneConnection
    var body: some View {
        VStack(spacing: 4) {
            Button(action: { xplane.sendDREF("sim/cockpit2/autopilot/altitude_dial_ft", value: Float(xplane.altitudeDial + step)) }) {
                Image(systemName: "chevron.up").font(.caption.bold())
            }.buttonStyle(SmallHardwareButtonStyle())
            Text(label).font(.system(size: 7, weight: .black)).foregroundColor(.gray)
            Button(action: { xplane.sendDREF("sim/cockpit2/autopilot/altitude_dial_ft", value: Float(max(0, xplane.altitudeDial - step))) }) {
                Image(systemName: "chevron.down").font(.caption.bold())
            }.buttonStyle(SmallHardwareButtonStyle())
        }
    }
}

struct InteractiveTrimView: View {
    @ObservedObject var xplane: XPlaneConnection
    @State private var dragAccumulator: CGFloat = 0
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [.black, .gray.opacity(0.3), .black], startPoint: .leading, endPoint: .trailing)).frame(width: 40, height: 100)
                VStack(spacing: 8) { ForEach(0..<6) { _ in Rectangle().fill(Color.black.opacity(0.4)).frame(height: 2) } }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                let delta = val.translation.height - dragAccumulator
                dragAccumulator = val.translation.height
                if abs(delta) > 2 {
                    if delta < 0 { xplane.sendCommand("sim/flight_controls/pitch_trim_down") }
                    else { xplane.sendCommand("sim/flight_controls/pitch_trim_up") }
                }
            }.onEnded { _ in dragAccumulator = 0 })
            ZStack(alignment: .top) {
                Capsule().fill(Color.black).frame(width: 8, height: 100)
                Rectangle().fill(.white).frame(width: 18, height: 4).cornerRadius(1).offset(y: 50 + CGFloat(xplane.elevatorTrim * 50))
            }
        }.padding(8).background(Color(white: 0.22)).cornerRadius(12)
    }
}

struct HardwareButton: View {
    let title: String; var isOn: Bool; let action: () -> Void
    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); action() }) {
            VStack(spacing: 4) {
                Rectangle().fill(isOn ? Color.green : Color.black).frame(width: 18, height: 3).cornerRadius(2).shadow(color: isOn ? .green : .clear, radius: 4)
                Text(title).font(.system(size: 12, weight: .black)).foregroundColor(.white)
            }
            .frame(width: 62, height: 45).background(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)).cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 1.5))
        }
    }
}

struct SmallHardwareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 32, height: 26).background(Color(white: 0.3)).cornerRadius(4).foregroundColor(.white).scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var xplane: XPlaneConnection
    var body: some View {
        NavigationView {
            Form { TextField("Indirizzo IP X-Plane", text: $xplane.xplaneIP).keyboardType(.numbersAndPunctuation) }
            .navigationTitle("Setup").toolbar { Button("OK") { presentationMode.wrappedValue.dismiss() } }
        }
    }
}
