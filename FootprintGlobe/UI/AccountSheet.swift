import SwiftUI
import UIKit
import PhotosUI

/// 圆形头像：有图就显示图，没图就用昵称首字 + 品牌渐变兜底。
/// 首页、设置、账号页共用这一个，省得三处各画一遍。
struct AvatarView: View {
    var name: String
    var image: UIImage?
    var size: CGFloat = Theme.Layout.avatar

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.brand.opacity(0.95), Theme.brandLight.opacity(0.70)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
    }
}

/// 账号页：不注册也能用 App，这一页只负责「注册 / 登录 / 换头像改昵称」。
struct AccountSheet: View {
    @ObservedObject private var service = AccountService.shared
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case register
        case signIn
        var id: String { rawValue }
        var title: String { self == .register ? "注册" : "登录" }
    }

    @State private var mode: Mode = .register
    @State private var phone = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var nickname = ""
    @State private var errorText: String?
    @State private var tipText: String?
    @State private var showSignOutConfirm = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionGap) {
                    if service.signedIn, let account = service.account {
                        profileCard(account)
                        securityCard
                        signOutRow
                    } else {
                        authCard
                        securityCard
                    }
                }
                .padding(.horizontal, Theme.Layout.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.oceanDeep.ignoresSafeArea())
            .navigationTitle(service.signedIn ? "我的账号" : "账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
            .onAppear {
                mode = service.hasAccount ? .signIn : .register
                nickname = service.account?.nickname ?? ""
            }
            .onChange(of: pickerItem) { _, _ in loadAvatar() }
            .confirmationDialog("退出登录？", isPresented: $showSignOutConfirm,
                                titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    service.signOut()
                    mode = .signIn
                    password = ""
                    confirm = ""
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("记录和头像都会留在本机，重新登录就能看到。")
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    // MARK: - 注册 / 登录

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            field(title: "手机号", text: $phone, placeholder: "11 位手机号",
                  keyboard: .numberPad, secure: false,
                  contentType: .telephoneNumber)

            field(title: "密码", text: $password, placeholder: "至少 6 位",
                  keyboard: .default, secure: true,
                  contentType: mode == .register ? .newPassword : .password)

            if mode == .register {
                field(title: "再输一次", text: $confirm, placeholder: "确认密码",
                      keyboard: .default, secure: true, contentType: .newPassword)
                field(title: "昵称（可不填）", text: $nickname, placeholder: "比如：小宇",
                      keyboard: .default, secure: false, contentType: .nickname)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(Theme.pending)
            }
            if let tipText {
                Text(tipText)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(Theme.wish)
            }

            Button {
                submit()
            } label: {
                Text(mode == .register ? "注册" : "登录")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Layout.controlHeight + 4)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(phone.isEmpty || password.isEmpty)

            Text("不注册也能正常用，记录、备份、海报都跟账号无关。注册只是为了让头像和昵称显示在首页。")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Theme.textTertiary)
        }
        .themeCard(padding: 16)
    }

    private func field(title: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType, secure: Bool,
                       contentType: UITextContentType?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15, design: .rounded))
            .foregroundColor(Theme.textPrimary)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Theme.oceanDeep, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
    }

    private func submit() {
        errorText = nil
        tipText = nil
        do {
            switch mode {
            case .register:
                try service.register(phone: phone, password: password,
                                     confirm: confirm, nickname: nickname)
                tipText = "注册好了，可以换个头像。"
            case .signIn:
                try service.signIn(phone: phone, password: password)
                tipText = "欢迎回来。"
            }
            password = ""
            confirm = ""
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - 已登录：资料

    private func profileCard(_ account: AccountService.LocalAccount) -> some View {
        // 先取出来存成局部常量：PhotosPicker 的 label 闭包不是主线程隔离的，
        // 在里面直接读 service.avatar 会编译告警。
        let avatarImage = service.avatar
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(name: account.nickname, image: avatarImage, size: 62)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.brand, in: Circle())
                            .overlay(Circle().stroke(Theme.oceanDeep, lineWidth: 1.5))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.nickname)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Text(account.maskedPhone)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                    Text("注册于 \(account.createdAt.formatted(.dateTime.year().month().day()))")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("昵称")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                HStack(spacing: 8) {
                    TextField("昵称", text: $nickname)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Theme.oceanDeep,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Theme.hairline, lineWidth: 1)
                        )
                    Button("保存") { saveNickname() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Theme.brandDim,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .foregroundColor(Theme.brandLight)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(Theme.pending)
            }
            if let tipText {
                Text(tipText)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(Theme.wish)
            }

            if service.avatar != nil {
                Button("移除头像") {
                    service.removeAvatar()
                    tipText = "头像已移除。"
                }
                .font(.system(size: 11.5, design: .rounded))
                .foregroundColor(Theme.textTertiary)
            }
        }
        .themeCard(padding: 16)
    }

    private var signOutRow: some View {
        Button(role: .destructive) {
            showSignOutConfirm = true
        } label: {
            HStack {
                Text("退出登录")
                Spacer()
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(Theme.pending)
        }
        .themeCard(padding: 16)
    }

    // MARK: - 安全说明

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("账号只存在这台手机上", systemImage: "lock.shield.fill")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textSecondary)
            Text("现在没有服务器，手机号、昵称、头像都写在 App 自己的目录里。密码不存明文，用随机盐做 PBKDF2-SHA256（12 万轮）之后放进钥匙串，只在本机解锁后可读、不进 iCloud 备份。所以换手机后用备份恢复，档案会回来，密码需要重设。")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .themeCard(padding: 16)
    }

    // MARK: - 动作

    private func saveNickname() {
        errorText = nil
        tipText = nil
        do {
            try service.saveProfile(nickname: nickname)
            tipText = "昵称改好了。"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadAvatar() {
        guard let pickerItem else { return }
        errorText = nil
        Task {
            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorText = "这张图读不出来，换一张试试。"
                return
            }
            do {
                try service.saveAvatar(image)
                tipText = "头像换好了。"
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
