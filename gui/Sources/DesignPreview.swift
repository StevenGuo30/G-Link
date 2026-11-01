import SwiftUI

// Deliberately separate from QingLinkApp: no network delegate, timer or menu-bar actions.
struct DesignPreviewApp: App {
    var body: some Scene {
        WindowGroup("G-Link · 设计预览") {
            DesignPreviewView()
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 880, height: 700)
    }
}

struct DesignPreviewView: View {
    @State private var city = 1
    @State private var connected = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("设计预览").font(.system(size: 12, weight: .semibold))
                Picker("建筑", selection: $city) {
                    Text("深圳").tag(0); Text("上海").tag(1)
                    Text("纽约").tag(2); Text("芝加哥").tag(3)
                }.labelsHidden().frame(width: 120)
                Picker("展示状态", selection: $connected) {
                    Text("关闭效果").tag(false); Text("开启效果").tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 185)
                Spacer()
                Text("仅展示界面，不操作网络").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).frame(height: 50).background(Color(red: 0.95, green: 0.96, blue: 0.98))
            DesignPreviewScene(city: city, connected: connected)
                .id(city)
        }.frame(minWidth: 880, minHeight: 700).preferredColorScheme(.light)
    }
}

private struct DesignPreviewScene: View {
    let connected: Bool
    @StateObject private var model: AppModel
    init(city: Int, connected: Bool) {
        self.connected = connected
        let model = AppModel(preview: connected ? .on : .off, previewCity: city, animatePreview: true)
        model.checkResult = "连接正常"
        _model = StateObject(wrappedValue: model)
    }
    var body: some View {
        RootView(model: model)
            // Review controls above are the only interactive controls in this app.
            .allowsHitTesting(false)
            .onChange(of: connected) { value in
                withAnimation(.easeInOut(duration: 0.65)) { model.state = value ? .on : .off }
            }
    }
}
