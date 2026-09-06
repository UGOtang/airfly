# AirFly 云中转协议 v1

单端口 WebSocket，每一帧 = 一个 JSON 对象（UTF-8 文本帧，不使用二进制帧）。

## 连接

- `GET /healthz` 健康检查；`WS /ws` 主通道。
- 连接后 15 秒内必须发送 `hello`，否则服务端断开。
- 服务端每 25s 广播 `ping`，客户端回 `pong`；90s 无任何消息视为僵尸连接并清理。
- 客户端掉线应指数退避重连（1s → 30s 上限），重连后重发 `hello`。

## Client → Server

```json
{"type":"hello","protocol":1,"spaceId":"my-space","spaceKey":"","apiKey":"",
 "device":{"id":"持久化uuid","name":"Pixel","platform":"android"}}
{"type":"ping","ts":123}
{"type":"pong","ts":123}
{"type":"clipboard_push","msgId":"uuid","text":"hello"}
{"type":"clipboard_history_request"}
{"type":"file_list_request"}
{"type":"file_announce","msgId":"uuid","fileId":"16位id","name":"a.zip","size":12345}
{"type":"file_chunk","msgId":"uuid","fileId":"…","offset":0,"dataBase64":"…","isLast":false}
{"type":"file_download_request","fileId":"…","offset":0}
{"type":"file_delete","fileId":"…"}
```

- `file_chunk` 采用 stop-and-wait：发一块、等 `file_chunk_ack` 再发下一块。
  `offset` 必须等于服务端已落盘长度，否则服务端回 `mismatch:true` + 正确 `uploadedBytes`，客户端 seek 后重发。
- 单帧上限 300KB，文件块建议 128KB 原始数据（base64 后约 175KB）。

## Server → Client

```json
{"type":"welcome","spaceId":"…","deviceId":"…(服务端确认/分配)","serverTime":123,
 "maxFileBytes":2147483648,"maxClipChars":100000}
{"type":"pong","ts":123}
{"type":"ping","ts":123}
{"type":"presence","spaceId":"…","devices":[{"id","name","platform","connectedAt"}],"serverTime":123}
{"type":"clipboard_update","item":{"id","text","deviceId","deviceName","updatedAt"},"deduped":false}
{"type":"clipboard_history","items":[…]}
{"type":"file_list","spaceId":"…","files":[{"id","name","size","uploadedBytes","complete","ownerDeviceId","ownerDeviceName","createdAt","expiresAt"}]}
{"type":"file_announced","file":{…},"resumed":false}
{"type":"file_chunk_ack","fileId":"…","uploadedBytes":123,"complete":false,"mismatch":false}
{"type":"file_progress","fileId":"…","uploadedBytes":123,"size":456,"complete":false}
{"type":"file_download_chunk","fileId":"…","offset":0,"dataBase64":"…","isLast":false,"size":456,"name":"a.zip"}
{"type":"file_deleted","fileId":"…"}
{"type":"error","code":"…","refMsgId":"…","fileId":"…"}
```

错误码：`bad_protocol|bad_space_id|bad_space_key|bad_api_key|need_hello|hello_timeout|`
`empty_clip|clip_too_large|bad_file_id|bad_file_size|file_conflict|quota_exceeded|`
`no_such_file|file_incomplete|empty_chunk|bad_base64|bad_chunk_size|chunk_overflow|`
`size_mismatch|bad_offset|disk_error|frame_too_large|rate_limited|unknown_type|internal`
`space_limit`（空间总数超限，拒绝新建空间）

## 约束

- `spaceId` 正则 `^[A-Za-z0-9][A-Za-z0-9\-_]{2,31}$`
- `fileId` 正则 `^[A-Za-z0-9\-_]{8,64}$`（客户端生成 uuid 即可）
- 文件名服务端会清洗（去路径/控制字符/限长），防路径穿越
- 剪切板保留最近 100 条；文件默认保留 7 天（`FILE_TTL_HOURS` 可调）
- 只有**完整**文件可下载；未传完的只能续传不能下载
