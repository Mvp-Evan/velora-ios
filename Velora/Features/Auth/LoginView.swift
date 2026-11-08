import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var inviteCode = ""
    @State private var needsInvite = false
    @State private var sending = false
    @State private var cooldown = 0
    @State private var loggingIn = false
    @State private var agreed = true
    @State private var legalDoc: LegalDocument?
    @FocusState private var focus: Field?
    enum Field { case phone, code, invite }

    private var canLogin: Bool {
        phone.isPhone && code.count >= 4 && agreed && (!needsInvite || !inviteCode.isBlank)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.vBackground.ignoresSafeArea()
            VGradient.brand.frame(height: 260).ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(.white.opacity(0.2), in: Circle())
                    }
                }
                .padding(.horizontal, VSpace.l).padding(.top, VSpace.m)

                VStack(alignment: .leading, spacing: 6) {
                    Text("欢迎来到 \(AppConfig.brandDisplayName)").font(.vLargeTitle).foregroundStyle(.white)
                    Text("赛车模型实时拍卖社区 · 手机号登录").font(.vBody).foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, VSpace.xl).padding(.top, VSpace.xl)

                VCard(padding: VSpace.xl, radius: VRadius.xl) {
                    VStack(spacing: VSpace.l) {
                        field(icon: "iphone", placeholder: "请输入手机号", text: $phone, keyboard: .numberPad, focused: .phone)
                            .onChange(of: phone) { _, v in if v.count > 11 { phone = String(v.prefix(11)) } }

                        HStack(spacing: 10) {
                            field(icon: "lock", placeholder: "验证码", text: $code, keyboard: .numberPad, focused: .code)
                                .onChange(of: code) { _, v in if v.count > 6 { code = String(v.prefix(6)) } }
                            Button(action: sendCode) {
                                Text(cooldown > 0 ? "\(cooldown)s" : "获取验证码")
                                    .font(.vCaptionMedium)
                                    .foregroundStyle(cooldown > 0 || !phone.isPhone ? Color.vTextTertiary : Color.vPrimary)
                                    .frame(width: 92, height: 48)
                                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            }
                            .disabled(cooldown > 0 || !phone.isPhone || sending)
                        }

                        if needsInvite {
                            VStack(alignment: .leading, spacing: 6) {
                                field(icon: "ticket", placeholder: "邀请码", text: $inviteCode, keyboard: .asciiCapable, focused: .invite)
                                    .textInputAutocapitalization(.characters)
                                Text("新用户注册需填写有效邀请码")
                                    .font(.vMicro)
                                    .foregroundStyle(Color.vTextSecondary)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        VPrimaryButton(title: "登录 / 注册", loading: loggingIn, disabled: !canLogin, action: login)

                        HStack(alignment: .top, spacing: 6) {
                            Button { agreed.toggle() } label: {
                                Image(systemName: agreed ? "checkmark.circle.fill" : "circle").foregroundStyle(agreed ? Color.vPrimary : Color.vTextTertiary)
                            }
                            .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("已阅读并同意").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                                HStack(spacing: 8) {
                                    Button("《使用说明》") { legalDoc = .appGuide }
                                    Button("《拍卖规则》") { legalDoc = .auctionRules }
                                    Button("《免责声明》") { legalDoc = .disclaimer }
                                }
                                .font(.vCaption).foregroundStyle(Color.vPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        #if DEBUG
                        Text("开发环境：验证码固定为 123456，可用 13800000001–10 登录种子账号")
                            .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        #endif
                    }
                }
                .padding(.horizontal, VSpace.l)
                .padding(.top, VSpace.xl)
                .vFloatingShadow()

                Spacer()
            }
        }
        .onAppear { focus = .phone }
        .onTapGesture { hideKeyboard() }
        .sheet(item: $legalDoc) { LegalDocumentView(document: $0) }
        .animation(.easeInOut(duration: 0.2), value: needsInvite)
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType, focused: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.vTextTertiary).frame(width: 18)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textContentType(focused == .code ? .oneTimeCode : (focused == .phone ? .telephoneNumber : .none))
                .font(.vMono(17, weight: .medium))
                .focused($focus, equals: focused)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }

    private func sendCode() {
        sending = true
        Task {
            defer { sending = false }
            do {
                let resp = try await API.sendSms(phone: phone)
                #if DEBUG
                if let dev = resp.devCode, !dev.isEmpty { code = dev }
                #endif
                ToastCenter.shared.show("验证码已发送", .success)
                focus = .code
                let seconds = resp.cooldownSeconds
                cooldown = seconds > 0 ? seconds : 60
                while cooldown > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    cooldown -= 1
                }
            } catch let e as APIError {
                switch e.authCode {
                case .smsTooFrequent, .tooManyRequests:
                    ToastCenter.shared.show(e.message, .info)
                    if cooldown == 0 { cooldown = 60 }
                case .smsDailyLimit, .smsLocked, .smsUnavailable:
                    ToastCenter.shared.show(e.message, .error)
                default:
                    ToastCenter.shared.error(e)
                }
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func login() {
        loggingIn = true
        Task {
            defer { loggingIn = false }
            do {
                let invite = needsInvite ? inviteCode.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                try await session.login(phone: phone, code: code, inviteCode: invite)
                ToastCenter.shared.show("登录成功", .success)
                dismiss()
            } catch let e as APIError where e.authCode == .inviteRequired {
                needsInvite = true
                focus = .invite
                ToastCenter.shared.show(e.message.isEmpty ? "新用户需填写邀请码" : e.message, .info)
            } catch let e as APIError where e.authCode == .inviteInvalid {
                ToastCenter.shared.show(e.message.isEmpty ? "邀请码无效" : e.message, .error)
            } catch let e as APIError where e.authCode == .accountFrozen || e.restrictionCode == .accountFrozen {
                session.handleAccountFrozen(message: e.restrictionMessage)
                dismiss()
            } catch let e as APIError where e.authCode == .accountBlocked {
                ToastCenter.shared.show(e.message.isEmpty ? "账号不可用，请联系客服" : e.message, .error)
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }
}
