// AirFly 云中转协议 v1 —— 客户端侧常量 / 校验 / 消息构造。
// 与服务端 (server/bin/server.dart) 和 PROTOCOL.md 保持一致。
// 纯 Dart，无 Flutter 依赖，方便单测。

/// 协议版本，hello 必须为 1。
const int kProtocolVersion = 1;

/// 单个文件块原始大小：128KB（base64 后约 175KB，远小于 300KB 单帧上限）。
const int kChunkSize = 128 * 1024;

/// 单帧上限（服务端同样限制），客户端发送前自检。
const int kMaxFrameBytes = 300 * 1024;

/// 客户端上传/下载单块等待 ack 超时。
const Duration kChunkTimeout = Duration(seconds: 30);

/// announce / clipboard_push 等待超时。
const Duration kRequestTimeout = Duration(seconds: 20);

/// hello 等待 welcome 超时。
const Duration kHelloTimeout = Duration(seconds: 15);

/// 服务端静默多久则判定掉线并重连。
const Duration kSilenceTimeout = Duration(seconds: 45);

/// 重连退避：1s,2s,4s… 上限 30s。
Duration reconnectDelay(int attempt) {
  var secs = 1 << (attempt.clamp(0, 5));
  if (secs > 30) secs = 30;
  return Duration(seconds: secs);
}

final RegExp kSpaceIdExp = RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_]{2,31}$');
final RegExp kFileIdExp = RegExp(r'^[A-Za-z0-9\-_]{8,64}$');

bool isValidSpaceId(String s) => kSpaceIdExp.hasMatch(s.trim());

/// 规范化服务端地址：
/// - 允许输入裸 IP/域名（自动补 ws:// 与 /ws）
/// - 允许 http(s)://（自动换成 ws(s)://）
/// - 返回 null 表示非法。
String? normalizeServerUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('http://')) {
    s = 'ws://${s.substring(7)}';
  } else if (s.startsWith('https://')) {
    s = 'wss://${s.substring(8)}';
  } else if (!s.startsWith('ws://') && !s.startsWith('wss://')) {
    s = 'ws://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'ws' && uri.scheme != 'wss') return null;
  // 路径缺省则补 /ws
  final path = uri.path.isEmpty || uri.path == '/' ? '/ws' : uri.path;
  return uri.replace(path: path).toString();
}

/// 错误码 → 中文提示。
String friendlyError(String code) {
  switch (code) {
    case 'bad_protocol':
      return '客户端版本过旧，请升级';
    case 'bad_space_id':
      return '空间码格式不对（3-32位字母数字及-_）';
    case 'bad_space_key':
      return '空间密码错误';
    case 'bad_api_key':
      return '服务端密钥错误';
    case 'need_hello':
      return '连接未就绪，请重连';
    case 'hello_timeout':
      return '连接超时，请重连';
    case 'empty_clip':
      return '剪切板内容为空';
    case 'clip_too_large':
      return '文本太长，超出服务端限制';
    case 'bad_file_id':
      return '文件 ID 非法';
    case 'bad_file_size':
      return '文件大小非法或超出服务端上限';
    case 'file_conflict':
      return '同名文件大小不一致，无法续传';
    case 'quota_exceeded':
      return '空间配额已满';
    case 'space_limit':
      return '服务端空间数量已满，请联系管理员';
    case 'duplicate_device':
      return '该设备已在别处在线（应用数据可能被克隆），本机已停止重连';
    case 'no_such_file':
      return '文件不存在（可能已过期被清理）';
    case 'file_incomplete':
      return '文件还在上传中，稍后再下载';
    case 'empty_chunk':
      return '空数据块';
    case 'bad_base64':
      return '数据块损坏';
    case 'bad_chunk_size':
      return '数据块大小非法';
    case 'chunk_overflow':
      return '数据越界，服务端已拒绝';
    case 'size_mismatch':
      return '文件大小校验失败';
    case 'bad_offset':
      return '下载偏移非法';
    case 'disk_error':
      return '服务端磁盘错误';
    case 'frame_too_large':
      return '单帧过大';
    case 'rate_limited':
      return '操作太频繁，被服务端限流';
    default:
      return '出错了（$code）';
  }
}
