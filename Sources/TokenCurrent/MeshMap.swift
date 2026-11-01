#if os(macOS)
import SwiftUI
import TokenCurrentCore

struct MeshMap: View {
    @Bindable var mesh: MeshController
    private var visible: [NetworkMachine] { Array(mesh.machines.prefix(6)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Machines").font(.headline)
                Spacer()
                Text("\(mesh.machines.filter { $0.isOnline(at: .now) }.count) online")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: 64)
                ZStack {
                    Canvas { context, size in
                        for index in visible.indices {
                            var path = Path()
                            path.move(to: center)
                            path.addLine(to: point(index, width: size.width))
                            context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                        }
                    }
                    Image(systemName: mesh.mode == .relay ? "server.rack" : "point.3.connected.trianglepath.dotted")
                        .font(.title3).padding(10).background(.regularMaterial, in: Circle())
                        .position(center)
                        .accessibilityLabel(mesh.mode == .relay ? "Relay connection" : "Direct Tailscale connections")
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, machine in
                        Button {
                            mesh.selectedID = mesh.selectedID == machine.id ? "all" : machine.id
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: machine.platform == "darwin" ? "laptopcomputer" : "desktopcomputer")
                                    .font(.body).foregroundStyle(machine.isOnline(at: .now) ? .primary : .secondary)
                                Text(machine.name).font(.system(size: 9)).lineLimit(1).frame(width: 70)
                            }
                            .padding(.vertical, 5)
                            .background(mesh.selectedID == machine.id ? Color.accentColor.opacity(0.15) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .position(point(index, width: geometry.size.width))
                        .accessibilityLabel("\(machine.name), \(machine.isOnline(at: .now) ? "online" : "offline")")
                        .accessibilityAddTraits(mesh.selectedID == machine.id ? [.isSelected] : [])
                    }
                }
            }
            .frame(height: 132)
            Picker("Meter machines", selection: $mesh.selectedID) {
                Text("All machines").tag("all")
                ForEach(mesh.machines) { machine in Text(machine.name).tag(machine.id) }
            }
            .labelsHidden()
            if mesh.machines.count > 6 {
                Text("Showing 6 nodes. Select any machine in the menu above.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func point(_ index: Int, width: Double) -> CGPoint {
        let angle = Double(index) / Double(max(visible.count, 1)) * .pi * 2 - .pi / 2
        return CGPoint(x: width / 2 + cos(angle) * (width / 2 - 37), y: 64 + sin(angle) * 46)
    }
}
#endif
