# 手动更新与发布

G-Link 使用 Sparkle 2.10.1。用户点击帮助页、应用菜单或菜单栏中的“检查更新”才启动更新器。
自动检查、自动下载安装和系统信息收集均关闭。设计预览不会启动更新器。

更新清单地址是 `https://github.com/StevenGuo30/G-Link/releases/latest/download/appcast.xml`，
安装包和清单均作为同一 GitHub Release 的附件发布，不需要单独部署服务器或启用 Pages。
已有的 0.1.5 及更早版本没有更新器，需要手动安装一次 0.1.6 或更新版本。

## 安装行为

下载期间继续使用现有连接。Sparkle 完成签名验证和解压后，请求应用退出；
G-Link 的 `applicationShouldTerminate` 先恢复系统代理，再停止自己的 sing-box，最后允许退出。
网络恢复失败或用户取消网络授权时，应用拒绝退出，保留恢复记录和引擎供用户重试。
安装失败由 Sparkle 报错，不通过自行覆盖可执行文件或按进程名强杀来绕过失败。

OTA ZIP 只包含 `G-Link.app`，不含配置或教程文件夹；应用内仍有离线教程。
用户数据保留在应用包外的 `~/Library/Application Support/QingLink/`。
应用应从本机可写位置运行，推荐首次设置后放入用户的“应用程序”文件夹。
App Translocation、只读卷或写入权限不足可能阻止更新；按系统提示安装到正常位置后重试。
更新包签名与 Apple Developer ID 签名、公证不是同一回事，本项目仍使用本地 ad-hoc 应用签名。

## 签名密钥

官方发行的 Ed25519 私钥由 Sparkle 存入维护者的登录钥匙串，account 为 `G-Link`。
仓库只保存 `gui/Info.plist` 的 `SUPublicEDKey` 公钥。不得把私钥、钥匙串导出文件或私人配置提交到仓库。
更新 ZIP 和 appcast 都必须签名，应用在解压前验证更新包。

首次配置自己的发行渠道（fork）时：

```bash
bash gui/scripts/prepare-sparkle.sh
gui/.build/sparkle/bin/generate_keys --account YourProject
```

将生成的公钥和自己的 `SUFeedURL` 写入 `gui/Info.plist`，之后通过
`GLINK_SIGNING_ACCOUNT=YourProject` 和 `update-feed.py --repo owner/repository` 发布。
原有安装只能接受其内嵌公钥认可的更新；不要直接换掉已发行应用的公钥。
保管好钥匙串及加密备份。丢失私钥可能需要用户重新手动安装，不能用新密钥冒充旧密钥。

## 发行步骤

1. 同时提高 `CFBundleShortVersionString` 和递增的 `CFBundleVersion`。
2. 完成构建、引擎与更新测试；把版本说明写入 UTF-8 文本文件。
3. 打包并签名。`GLINK_DIST_DIR` 可指向独立目录，避免覆盖正在运行的应用。

```bash
export GLINK_DIST_DIR="$PWD/dist/v0.1.6"
bash gui/scripts/build.sh
python3 gui/tests/engine.py
python3 gui/tests/updates.py
bash gui/scripts/package.sh public
bash gui/scripts/package.sh update
cp "$GLINK_DIST_DIR/G-Link-公开应用.zip" "$GLINK_DIST_DIR/G-Link-v0.1.6-macOS.zip"
python3 gui/scripts/update-feed.py --notes /path/to/release-notes.txt
python3 gui/scripts/export-public.py
python3 gui/tests/artifacts.py
```

更新签名脚本会检查钥匙串公钥与应用公钥一致，并验证归档内容和生成的签名。
它会生成 `appcast.xml` 和包含公开安装包、OTA 包及清单的 `SHA256SUMS-v版本.txt`。
源码清单 `SOURCE-MANIFEST.json` 应同步为公开源码 ZIP 内生成的版本，然后提交代码。

将以下四个文件上传至同一个 Release，确认全部上传完成后再正式发布并设为 latest：

- `G-Link-v版本-macOS.zip`：首次手动下载使用。
- `G-Link-v版本-update.zip`：Sparkle 使用的应用包。
- `appcast.xml`：已签名版本清单。
- `SHA256SUMS-v版本.txt`：供人工验证下载文件。

私人分享包不能上传 Release。不要在签名后编辑清单或重新压缩 OTA 包；任何修改都需要重新签名。
发布前验证新版本可从旧版本更新；发布后验证 latest 清单和附件可访问，且远端 SHA256 与本地相同。

## 回归验证

`gui/tests/updates.py` 使用一次性签名密钥、本地 HTTP 服务、独立应用和配置目录，测试无更新、
用户取消、篡改清单、篡改安装包、真实替换重启及网络恢复失败阻止退出后重试。
它不会读取私人节点或修改系统代理。真实管理员授权取消、Gatekeeper 与不同安装目录需在目标 Mac 验证。
`gui/tests/artifacts.py` 另行验证签名、ZIP 解压后的框架符号链接，以及公开包不含私人配置。

参考：[Sparkle 接入文档](https://sparkle-project.org/documentation/)、
[发布更新](https://sparkle-project.org/documentation/publishing/)。
