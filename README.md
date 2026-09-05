# AirFly 2.0 · 云中转版

多端（Android / iOS / Windows / macOS / Linux / Web）通过一台云服务端同步**剪切板**与**文件**。
不再局限于局域网：只要能连上你的云服务器，在哪都能同步。也可以只当剪切板用，不传文件。

```
手机 ──┐
平板 ──┼──▶ 云服务端 (x86, 单端口 WebSocket) ── 同空间设备实时同步
电脑 ──┘         ▲ 剪切板推送/广播 · 文件分块上传/下载 · 在线设备
```

服务端与客户端都用 Dart/Flutter 技术栈：服务端是零第三方依赖的纯 Dart 程序，
`dart compile` 后一个二进制文件即可跑在 x86 云服务器上；客户端是 Flutter App。

## 目录

- `lib/` 客户端（Flutter）
- `server/` 云中转服务端（纯 Dart，见下方部署）
- `PROTOCOL.md` 同步协议 v1（排障/二次开发看它）
- `integration/check.dart` 端到端自检脚本（真起服务端跑全流程）

## 快速开始（客户端）

1. 先把服务端部署好（见下），拿到地址，如 `ws://1.2.3.4:8080/ws`。
2. 运行 App：`flutter run`（桌面/移动/网页均可）。
3. 打开「设置」填写：
   - **服务端地址**：`ws://IP:8080/ws`（有域名+证书则填 `wss://域名/ws`）
   - **空间码**：如 `my-space`（3–32 位字母数字及 `-_`；可点「随机」生成）
   - **空间密码**（可选）：首次加入即创建该空间并设定密码，之后加入必须一致
   - **服务端密钥**（可选）：与服务端 `API_KEY` 一致才允许连接
   - **本机显示名称**
4. 点「保存并重连」，顶部状态条变绿即连通。
5. 在另一台设备填**相同的服务端地址 + 空间码（+密码）**，两边就能在「设备」页看到彼此。

只当剪切板用：在「剪切板」页输入文本点「同步到云端」，或打开自动推送/自动写入，
复制即同步，完全不用碰文件功能。

本地终端：「终端」页是本机 shell 可视化（桌面端真 shell，移动/Web 为受限模式，
仅 help/echo/clear）。支持 cd（含 `~`/`cd /d`）、上下键翻历史、运行中一键停止、
输出保留最近 2000 行，历史命令持久化。

外观：「设置」→「外观」可在跟随系统 / 浅色 / 深色之间切换，即时生效并记住选择。

## 服务端部署（x86 云服务器）

### 方式一：Docker（推荐）

```bash
cd server
docker compose up -d --build
curl http://127.0.0.1:8080/healthz   # {"ok":true,...} 即正常
```

数据持久化在 `./data`（已挂载 volume），升级/重启不丢文件与剪切板记录。

### 方式二：单文件二进制

```bash
cd server
dart pub get
dart compile exe bin/server.dart -o airfly-server
PORT=8080 DATA_DIR=/srv/airfly/data ./airfly-server
```

### 方式三：systemd 常驻

```ini
# /etc/systemd/system/airfly.service
[Unit]
Description=AirFly relay
After=network.target

[Service]
ExecStart=/srv/airfly/airfly-server
Environment=PORT=8080 DATA_DIR=/srv/airfly/data FILE_TTL_HOURS=168
# Environment=API_KEY=换成强随机串
Restart=always
User=airfly

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl enable --now airfly
```

### 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | 8080 | 监听端口 |
| `HOST` | 0.0.0.0 | 监听地址 |
| `DATA_DIR` | ./data | 数据目录（文件+元数据） |
| `MAX_FILE_MB` | 2048 | 单文件上限 |
| `SPACE_QUOTA_MB` | 5120 | 单空间配额 |
| `FILE_TTL_HOURS` | 168 | 文件保留时长（7天），过期自动清理 |
| `API_KEY` | 空 | 全局密钥，设置后客户端必须填一致 |
| `MAX_CLIP_CHARS` | 100000 | 剪切板单条字符上限 |

### 公网访问与 HTTPS（推荐 Nginx 反代出 wss）

云控制台安全组放行 80/443（服务端本身只需监听内网 8080）。
Nginx 示例：

```nginx
server {
  listen 443 ssl;
  server_name fly.example.com;
  ssl_certificate     /path/fullchain.pem;
  ssl_certificate_key /path/privkey.pem;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 3600s;
  }
}
```

客户端地址填 `wss://fly.example.com/ws`。注意反代超时要设大，
否则大文件传一半会被掐断（客户端会自动重连续传，但体验差）。

## 行为与限制

- 剪切板保留最近 100 条；新设备加入自动补全历史。
- 文件落盘在服务端，**上传一半断线可重连续传**（上传走 stop-and-wait + 偏移校验，
  错位块会被服务端纠正）。
- 只有**传完**的文件才能下载；未传完的显示上传进度。
- 客户端掉线指数退避重连（1s→30s），服务端 90s 无心跳清理僵尸连接。
- Web 端建议传 100MB 以内文件（浏览器内存限制），桌面/移动端走流式读写无此顾虑。
- 空间密码即房间钥匙：空间码+密码只告诉自己人；对外服务建议再启用 `API_KEY`。

## 排错

| 现象 | 查什么 |
|---|---|
| 一直「未连接」 | 先 `curl 服务端/healthz`；地址是否 `ws(s)://` 开头、带 `/ws`；安全组/防火墙 |
| `空间密码错误` | 同空间第一台设备定的密码为准，后加入的必须一致 |
| `空间配额已满` | 删旧文件，或调大 `SPACE_QUOTA_MB` 后重启服务端 |
| 文件卡在「上传中」 | 网络抖动时正常，点「重试」会自动续传；反代超时设大些 |
| `文件不存在` | 可能已过期被清理（默认 7 天），或被同空间设备删除 |

## 开发

```bash
flutter pub get
flutter analyze          # 静态检查（须零问题）
flutter test             # 单测 + widget 冒烟
dart integration/check.dart  # 端到端：真起服务端验 presence/剪切板/上传/下载/续传/重启恢复
flutter build web        # Web 构建验证
```

打 Android 包需要 JDK 17（`JAVA_HOME` 指向它），release 清单已内置
`INTERNET` 权限与明文流量允许（`ws://` 用）：

```powershell
$env:JAVA_HOME = "C:\Users\<你>\jdk-17\jdk-17.0.20.1+1"
flutter build apk --release  # 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 独立二进制终端（dist/airfly-term-*）

`tool/terminal.dart` 编译出的单文件终端，不依赖 Flutter App：

```bash
dart compile exe tool/terminal.dart -o airfly-term  # Linux 云服务器上同样命令产出 Linux 版
```

- 有 TTY 时默认**真 shell 模式**：控制台直接交给系统 shell
  （Windows 默认 PowerShell，`--cmd/--ps/--pwsh` 可选；Unix 用 `$SHELL`），
  补全、交互程序、Ctrl+C 全是原生行为，退出码透传。
  若 shell 瞬间退出（多见于个别终端输入继承失败），程序会直接提示，
  用 `airfly-term --new-window` 可在全新控制台窗口打开（兜底）。
- 无 TTY（管道/重定向）自动降级**行模式**（`--line` 强制），内置
  help/echo/cd/clear，适合脚本。
- 本程序自身输出为 UTF-8；旧版 cmd 若显示乱码请先执行 `chcp 65001`
 （真 shell 模式不受影响，子进程直写控制台）。

## 云空间 TUI 客户端（dist/airfly-tui-*，btop 风格）

直连云服务端的可视化终端面板（Linux/macOS 同样命令编译即用）：

```bash
airfly-tui --server ws://host:port/ws --space 空间码 [--key 密码]
# 也可用环境变量：AIRFLY_SERVER / AIRFLY_SPACE / AIRFLY_KEY / AIRFLY_NAME / AIRFLY_API
```

- 三面板：在线设备 / 文件（含上传下载进度条）/ 剪切板历史
- 键盘：Tab 切换面板，↑↓/jk 选择，Enter 动作，p 推送剪切板，
  u 上传（输本地路径），d 下载到 `./airfly-downloads/`，x 删除（需确认），
  c 取消传输，v 复制到系统剪切板，r 刷新，? 帮助，q 退出
- 鼠标：点面板聚焦、点行选中（点文件行直接下载）、滚轮滚动、
  点底部按钮（`--no-mouse` 可关闭）
- 自测：`dart tool/check_tui_core.dart`（原语）
  `dart tool/check_tui.dart`（渲染对齐/键鼠/输入条）
  `dart tool/check_relay.dart`（真起服务端联调纯 Dart 客户端）
