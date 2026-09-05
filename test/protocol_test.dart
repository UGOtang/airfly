import 'package:airfly/core/protocol.dart';
import 'package:airfly/models/cloud_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeServerUrl', () {
    test('裸 IP 自动补全', () {
      expect(
        normalizeServerUrl('1.2.3.4:8080'),
        'ws://1.2.3.4:8080/ws',
      );
    });

    test('http 自动转 ws', () {
      expect(
        normalizeServerUrl('http://1.2.3.4:8080/ws'),
        'ws://1.2.3.4:8080/ws',
      );
    });

    test('https 自动转 wss', () {
      expect(
        normalizeServerUrl('https://example.com/relay'),
        'wss://example.com/relay',
      );
    });

    test('缺省路径补 /ws', () {
      expect(
        normalizeServerUrl('ws://example.com'),
        'ws://example.com/ws',
      );
    });

    test('非法输入返回 null', () {
      expect(normalizeServerUrl(''), isNull);
      expect(normalizeServerUrl('   '), isNull);
      expect(normalizeServerUrl('::::'), isNull);
    });
  });

  group('isValidSpaceId', () {
    test('合法', () {
      expect(isValidSpaceId('abc'), isTrue);
      expect(isValidSpaceId('my-space_01'), isTrue);
    });

    test('非法', () {
      expect(isValidSpaceId('ab'), isFalse); // 太短
      expect(isValidSpaceId('-abc'), isFalse); // 开头非法
      expect(isValidSpaceId('a b'), isFalse); // 空格
      expect(isValidSpaceId(''), isFalse);
    });
  });

  group('reconnectDelay', () {
    test('指数退避且有上限', () {
      expect(reconnectDelay(0), const Duration(seconds: 1));
      expect(reconnectDelay(1), const Duration(seconds: 2));
      expect(reconnectDelay(2), const Duration(seconds: 4));
      expect(reconnectDelay(99), const Duration(seconds: 30));
    });
  });

  group('friendlyError', () {
    test('已知错误有中文', () {
      expect(friendlyError('bad_space_key'), contains('密码'));
      expect(friendlyError('quota_exceeded'), isNotEmpty);
    });

    test('未知错误回显 code', () {
      expect(friendlyError('xxx_nope'), contains('xxx_nope'));
    });
  });

  group('CloudFile', () {
    test('formatSize 边界', () {
      expect(CloudFile.formatSize(0), '0 B');
      expect(CloudFile.formatSize(1023), '1023 B');
      expect(CloudFile.formatSize(1024), '1.0 KB');
      expect(CloudFile.formatSize(1024 * 1024 * 1024), '1.00 GB');
    });

    test('fromJson 缺字段不抛异常', () {
      final f = CloudFile.fromJson(const {});
      expect(f.name, 'unnamed');
      expect(f.size, 0);
    });

    test('progress 越界钳制', () {
      final t = TransferTask(
        key: 'k',
        fileId: 'f',
        fileName: 'n',
        total: 100,
        isUpload: true,
        done: 150,
      );
      expect(t.progress, 1.0);
    });
  });
}
