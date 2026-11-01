import SwiftUI

enum Palette {
    static let paper = Color(red: 0.961, green: 0.973, blue: 0.984)
    static let navy = Color(red: 0.137, green: 0.235, blue: 0.353)
    static let blue = Color(red: 0.275, green: 0.427, blue: 0.612)
    static let ice = Color(red: 0.863, green: 0.910, blue: 0.953)
    static let ink = Color(red: 0.118, green: 0.161, blue: 0.220)
    static let secondary = Color(red: 0.424, green: 0.482, blue: 0.553)
    static let line = Color(red: 0.867, green: 0.894, blue: 0.929)
}

struct BrandMark: View {
    var size: CGFloat = 35
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29).fill(Palette.ice)
            Image(systemName: "link").font(.system(size: size * 0.5, weight: .semibold)).rotationEffect(.degrees(-30)).foregroundStyle(Palette.navy)
        }.frame(width: size, height: size)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var muted = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) { Text(title).font(.system(size: 15, weight: .semibold)); Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                .padding(.horizontal, 23).frame(height: 47)
                .foregroundStyle(muted ? Palette.ink : .white)
                .background(muted ? Color.white : Palette.navy, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(muted ? Palette.line : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                header
                if model.isPreview {
                    pageContent.frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView { pageContent }
                }
                Spacer(minLength: 12)
            }.frame(width: model.isPreview ? 700 : nil).frame(maxWidth: .infinity, maxHeight: .infinity).background { ConnectionBackdrop(city: model.backdropCity) }
        }.foregroundStyle(Palette.ink).frame(minWidth: 820, minHeight: 600).preferredColorScheme(.light)
    }
    private var pageContent: some View {
                    VStack(alignment: .leading, spacing: 18) {
                        if model.page == .connection { ConnectionView(model: model) }
                        else if model.page == .setup { SetupView(model: model) }
                        else { HelpView(model: model) }
                        if let message = model.message {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "info.circle.fill").foregroundStyle(Palette.blue)
                                Text(message).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
                                Spacer(minLength: 0)
                                Button { model.message = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
                            }.padding(15).background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(.horizontal, 34).padding(.bottom, 24)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) { BrandMark(size: 30); Text("G-Link").font(.system(size: 22, weight: .semibold)).tracking(-0.6).fixedSize() }
                .padding(.top, 37).padding(.bottom, 44)
            ForEach(Page.allCases, id: \.self) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page == .connection ? "power" : page == .setup ? "slider.horizontal.3" : "questionmark.circle").frame(width: 17)
                        Text(page.rawValue).font(.system(size: 13, weight: .medium)).lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 13).frame(height: 43)
                        .background(model.page == page ? Palette.navy.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(model.page == page ? Palette.navy : Palette.secondary)
                }.buttonStyle(.plain).padding(.bottom, 6)
            }
            Spacer()
            Text(model.appVersion).font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.leading, 12).padding(.bottom, 28)
        }.padding(.horizontal, 19).frame(width: 180).frame(maxHeight: .infinity).foregroundStyle(Palette.ink)
            .background(LinearGradient(colors: [Palette.ice, Palette.ice.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.65)).frame(width: 1) }
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.page.rawValue).font(.system(size: 25, weight: .semibold))
                Text("连接这件事，简单一点就好。")
                    .font(.system(size: 11)).tracking(1).foregroundStyle(Palette.secondary)
            }
            Spacer()
        }.padding(.horizontal, 34).padding(.top, 34).padding(.bottom, 23)
    }
}

struct ConnectionView: View {
    @ObservedObject var model: AppModel
    private var title: String {
        switch model.state {
        case .on: return "已开启"
        case .busy: return model.busyText
        case .recovery: return "需要恢复连接"
        case .unconfigured: return "还差一步"
        case .off: return "未开启"
        }
    }
    private var hint: String? {
        switch model.state {
        case .busy: return "如出现系统提示，请按提示确认。"
        case .recovery: return "上次连接未正常结束，请先恢复。"
        case .unconfigured: return "先完成设置，再开启连接。"
        default: return nil
        }
    }
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.white, Palette.ice.opacity(model.state == .on ? 1 : 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 112, height: 112)
                        .overlay(Circle().stroke(Palette.blue.opacity(0.12), lineWidth: 1))
                        .shadow(color: Palette.blue.opacity(0.06), radius: 14, x: 0, y: 7)
                    Circle().stroke(Palette.blue.opacity(0.08), lineWidth: 1).frame(width: 132, height: 132)
                    if model.busy { ProgressView().controlSize(.large).tint(Palette.blue) }
                    else { Image(systemName: model.state == .on ? "checkmark" : model.state == .recovery ? "arrow.counterclockwise" : "power").font(.system(size: 40, weight: .light)).foregroundStyle(Palette.blue) }
                }.frame(height: 132).padding(.top, 4)
                Text(title).font(.system(size: 27, weight: .semibold))
                if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center) }
                PrimaryButton(title: model.state == .on ? "关闭" : model.state == .recovery ? "恢复连接" : model.state == .unconfigured ? "开始设置" : "开启",
                              symbol: model.state == .recovery ? "arrow.counterclockwise" : model.state == .unconfigured ? "arrow.right" : "power",
                              muted: model.state == .on) { model.toggle() }
                    .disabled(model.busy).opacity(model.busy ? 0.5 : 1).padding(.top, 5).padding(.bottom, 8)
            }.padding(24).frame(maxWidth: 350).background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: Palette.navy.opacity(0.035), radius: 22, x: 0, y: 10)
                .frame(maxWidth: .infinity)
            if model.state == .on {
                HStack(alignment: .top, spacing: 12) {
                    Text(model.checking ? "正在检查连接…" : model.checkResult ?? "")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("检查连接") { model.diagnose() }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.blue).disabled(model.checking)
                }.padding(13).background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 0) {
                step(1, "开始"); Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 12)
                step(2, "选择配置"); Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 12)
                step(3, "完成")
            }.padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 19) {
                Image(systemName: model.setupStep == 3 ? "checkmark.seal" : model.setupStep == 2 ? "doc.badge.arrow.up" : "link")
                    .font(.system(size: 31, weight: .light)).foregroundStyle(Palette.blue)
                Text(model.setupStep == 3 ? "设置完成" : model.setupStep == 2 ? "选择连接配置" : "欢迎使用G-Link")
                    .font(.system(size: 23, weight: .semibold))
                Text(model.setupStep == 3 ? "开启时如需输入密码，请使用 Mac 的管理员密码。" : model.setupStep == 2 ? "选择随包配置，或导入收到的配置文件。" : "完成这一次设置，以后只需点一下开启。")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Palette.line)
                if model.setupStep == 1 {
                    PrimaryButton(title: "开始设置") { model.setupStep = 2 }
                } else if model.setupStep == 2 {
                    if model.hasPreset {
                        PrimaryButton(title: "使用随包配置", symbol: "checkmark") { if let url = model.presetURL { model.importConfig(url) } }.disabled(model.busy)
                        Button("选择其他文件…") { model.chooseConfig() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.blue).disabled(model.busy)
                    } else {
                        PrimaryButton(title: "选择配置文件", symbol: "folder") { model.chooseConfig() }.disabled(model.busy)
                    }
                    if model.busy { ProgressView("正在检查…").font(.system(size: 12)) }
                    if model.hasConfig { Button("使用已有配置") { model.setupStep = 3 }.buttonStyle(.plain).foregroundStyle(Palette.blue) }
                } else {
                    Label("配置已就绪", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.blue)
                    PrimaryButton(title: "完成") { model.page = .connection }
                    Button("添加到应用程序") { model.installToApplications() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.blue)
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line.opacity(0.65)))
            HStack {
                Text("更换前请先关闭连接。").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                Button("更换配置") { model.setupStep = 2; model.chooseConfig() }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size: 11))
            }
        }
    }
    private func step(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 7) {
            Text(String(number)).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22).background(model.setupStep >= number ? Palette.navy : Palette.line, in: Circle()).foregroundStyle(model.setupStep >= number ? .white : Palette.secondary)
            Text(title).font(.system(size: 11)).foregroundStyle(model.setupStep >= number ? Palette.ink : Palette.secondary)
        }
    }
}

struct HelpView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpCard("01", "第一次被 macOS 拦截？", "确认来源可信后，到“系统设置 → 隐私与安全”允许打开。")
            helpCard("02", "开启了，应用还是打不开？", "点击“检查连接”，再用 ⌘Q 退出需要联网的应用后重开。")
            helpCard("03", "上次异常退出，网络不通？", "重新打开G-Link，点击“恢复连接”，按系统提示确认。")
            HStack(spacing: 12) {
                PrimaryButton(title: "查看教程", symbol: "book") { model.openGuide() }
                Button("打开日志") { model.openLogs() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.blue)
            }.padding(.top, 3)
            Text("日志可能包含浏览记录，请勿公开分享。").font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }
    }
    private func helpCard(_ number: String, _ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Palette.blue).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(description).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
