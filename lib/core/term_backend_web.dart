// Web 平台的终端后端：没有本地 shell，固定受限模式。

import 'term_backend_interface.dart';

TermBackend createBackend() => const RestrictedBackend();
