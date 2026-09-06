import 'package:airfly/models/cloud_file.dart';
import 'package:flutter_test/flutter_test.dart';

TransferTask _task({
  required bool download,
  required TransferState state,
  String? savedPath,
}) =>
    TransferTask(
      key: 'k1',
      fileId: 'f1',
      fileName: 'a.pdf',
      total: 10,
      isUpload: !download,
      done: state == TransferState.done ? 10 : 0,
      state: state,
      savedPath: savedPath,
    );

void main() {
  group('TransferTask.canOpen', () {
    test('仅“已完成的下载且有本地路径”可打开', () {
      // 正例
      expect(
        _task(
          download: true,
          state: TransferState.done,
          savedPath: '/x/a.pdf',
        ).canOpen,
        isTrue,
      );
      // 无路径 / 空路径
      expect(_task(download: true, state: TransferState.done).canOpen,
          isFalse);
      expect(
          _task(download: true, state: TransferState.done, savedPath: '')
              .canOpen,
          isFalse);
      // 未完成态一律不行
      for (final s in [
        TransferState.queued,
        TransferState.active,
        TransferState.paused,
        TransferState.failed,
        TransferState.cancelled,
      ]) {
        expect(_task(download: true, state: s, savedPath: '/x').canOpen,
            isFalse);
      }
      // 上传任务不行（语义是发送，且源文件可能已不在）
      expect(
          _task(download: false, state: TransferState.done, savedPath: '/x')
              .canOpen,
          isFalse);
    });
  });
}
