import StoreKit
import SwiftUI

/// Cove Pro: a one-time purchase (no subscription) that unlocks speaker identification.
/// Everything else (recording, transcription, minutes, chat, export) stays free.
/// Builds made with `COVE_UNLOCKED` (the sideloaded CI build, or anyone building the
/// open source themselves) have it unlocked, since they can't buy through the App Store.
@MainActor @Observable
final class Pro {
    static let shared = Pro()

    /// "<bundle id>.pro", from Info.plist, so it follows whatever bundle id the build is signed with.
    nonisolated static var productID: String {
        let id = Bundle.main.object(forInfoDictionaryKey: "CoveProProductID") as? String ?? ""
        return id.isEmpty || id.hasPrefix("$(") ? "com.jhdehao.cove.pro" : id
    }

    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    private(set) var isPurchasing = false
    var message: String?
    @ObservationIgnored private var updates: Task<Void, Never>?

    private static let cacheKey = "pro.unlocked"

    private init() {
        #if COVE_UNLOCKED
        isUnlocked = true
        #else
        // Last known state, so Pro features don't flicker off at launch while StoreKit answers.
        isUnlocked = UserDefaults.standard.bool(forKey: Self.cacheKey)
        updates = Task { [weak self] in
            for await result in Transaction.updates { await self?.handle(result) }
        }
        Task {
            await refresh()
            await loadProduct()
        }
        #endif
    }

    /// "US$0.99" in the buyer's own currency, once the App Store has answered.
    var price: String? { product?.displayPrice }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    /// Re-reads what this Apple Account owns.
    func refresh() async {
        #if !COVE_UNLOCKED
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID, transaction.revocationDate == nil {
                owned = true
            }
        }
        set(owned)
        #endif
    }

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else {
            message = String(localized: "暂时连不上 App Store，请稍后再试。")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    set(true)
                    message = String(localized: "已解锁 Cove Pro，谢谢支持！")
                } else {
                    message = String(localized: "无法验证这次购买，请稍后点「恢复购买」。")
                }
            case .pending:
                message = String(localized: "购买等待批准（例如需要家长同意），批准后会自动解锁。")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = error.localizedDescription
            return
        }
        await refresh()
        message = isUnlocked ? String(localized: "已恢复 Cove Pro。") : String(localized: "这个 Apple 账号没有购买过 Cove Pro。")
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        if transaction.productID == Self.productID { set(transaction.revocationDate == nil) }
    }

    private func set(_ unlocked: Bool) {
        isUnlocked = unlocked
        UserDefaults.standard.set(unlocked, forKey: Self.cacheKey)
    }
}

/// What Pro adds, and the buttons to buy or restore it.
struct ProView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pro = Pro.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cove Pro")
                            .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        Text("一次性买断，没有订阅。")
                            .foregroundStyle(.secondary)
                    }
                    feature("person.2.wave.2", title: "识别说话人", detail: "会后在手机上分出「说话人 1 / 2 / 3」，长按改成真名；纪要和对话能说清谁说了什么、谁负责什么。")
                    feature("number", title: "指定人数", detail: "知道有几个人参会时直接指定，多人会议分得更准。")
                    feature("lock.shield", title: "同样只在本机", detail: "声音不上传，模型下载一次（约 35 MB）后离线运行。")
                    feature("heart", title: "支持独立开发", detail: "以后新增的 Pro 功能一并解锁。")
                    Text("录音、实时字幕、纪要、对话、导出等其余功能全部免费，不受影响。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if pro.isUnlocked {
                        Label("已解锁", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(CoveColor.accent)
                    } else {
                        Button {
                            Task { await pro.purchase() }
                        } label: {
                            HStack {
                                if pro.isPurchasing { ProgressView().tint(.white) }
                                Text(pro.price.map { String(localized: "解锁 Cove Pro · \($0)") } ?? String(localized: "解锁 Cove Pro"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CoveColor.accent)
                        .disabled(pro.isPurchasing)
                    }
                    Button("恢复购买") { Task { await pro.restore() } }
                        .frame(maxWidth: .infinity)
                    if let message = pro.message {
                        Text(message).font(.callout).frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
            }
            .coveCanvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .task { if pro.product == nil { await pro.loadProduct() } }
        }
    }

    private func feature(_ symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(CoveColor.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
