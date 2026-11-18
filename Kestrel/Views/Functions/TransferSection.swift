import SwiftUI
import UniformTypeIdentifiers
import KestrelCore

nonisolated extension UTType { static let kestrelTransfer = UTType(exportedAs: "dev.kestrel.transfer") }

nonisolated struct TransferDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.kestrelTransfer]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// PREF → Transfer: move watchlists, alerts and the paper book between iPad and Mac with an
/// encrypted file (AirDrop, Files, iCloud Drive, USB: any route works, the file is sealed).
struct TransferSection: View {
    @Environment(UserData.self) private var user
    @Environment(PaperBroker.self) private var broker
    @Environment(Theme.self) private var theme

    @State private var passphrase = ""
    @State private var working = false
    @State private var message: (String, Bool)?
    @State private var exportDoc: TransferDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: TransferBundle?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move this account's watchlists, alerts and paper book to your other device. The file is encrypted with the passphrase below; type the same passphrase when importing.")
                .font(.ui(11)).foregroundStyle(Theme.dim)
            HStack(spacing: 8) {
                SecureField("", text: $passphrase)
                    .placeholder("Transfer passphrase (10+ characters)", when: passphrase.isEmpty)
                    .font(.mono(12)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                    .padding(.horizontal, 8).frame(height: 30).background(Theme.canvas).overlay(Rectangle().stroke(Theme.rule))
                button(working ? "Working…" : "Export…", enabled: passphrase.count >= 10 && !working) { export() }
                button("Import…", enabled: passphrase.count >= 10 && !working) { importing = true }
            }
            if let b = pending {
                HStack(spacing: 8) {
                    Text("Import \(b.watchlists.count) watchlists, \(b.alerts.active.count) alerts and a paper book with \(Fmt.money(b.account.cash)) cash, exported \(b.exported.formatted(.dateTime.month(.abbreviated).day().hour().minute())). This replaces the data in this account.")
                        .font(.mono(10)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    button("Replace", enabled: true, destructive: true) {
                        user.replace(with: b); broker.replace(account: b.account)
                        pending = nil; message = ("Imported.", true)
                    }
                    button("Cancel", enabled: true) { pending = nil }
                }
            }
            if let (text, ok) = message {
                Text(text).font(.mono(10, .medium)).foregroundStyle(ok ? theme.up : Theme.cancel)
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .kestrelTransfer,
                      defaultFilename: "Kestrel-\(Date().formatted(.iso8601.year().month().day()))") { result in
            if case .success = result { message = ("Exported. Open it on your other device and import with the same passphrase.", true) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.kestrelTransfer, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= TransferBundle.maxFileSize,
                  let data = try? Data(contentsOf: url) else { message = ("That file is too large or unreadable.", false); return }
            open(data)
        }
    }

    private func export() {
        let bundle = TransferBundle(watchlists: user.watchlists, activeID: user.activeID, alerts: user.alerts, account: broker.account)
        let pass = passphrase
        working = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, TransferBundle.Failure> in
                do throws(TransferBundle.Failure) { return .success(try bundle.seal(passphrase: pass)) } catch { return .failure(error) }
            }.value
            working = false
            switch result {
            case .success(let data): exportDoc = TransferDocument(data: data); exporting = true
            case .failure(let e): message = (e.errorDescription ?? "Export failed", false)
            }
        }
    }

    private func open(_ data: Data) {
        let pass = passphrase
        working = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<TransferBundle, TransferBundle.Failure> in
                do throws(TransferBundle.Failure) { return .success(try TransferBundle.open(data, passphrase: pass)) } catch { return .failure(error) }
            }.value
            working = false
            switch result {
            case .success(let b): pending = b; message = nil
            case .failure(let e): message = (e.errorDescription ?? "Import failed", false); securityLog.notice("transfer import rejected")
            }
        }
    }

    private func button(_ title: String, enabled: Bool, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.mono(11, .bold)).foregroundStyle(destructive ? Theme.canvas : Theme.text)
                .padding(.horizontal, 12).frame(height: 30)
                .background(destructive ? Theme.cancel : Theme.header, in: .rect(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.rule))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}
