import 'dart:math';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../controllers/app_controller.dart';
import '../core/protocol.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';

/// 设置页：服务端地址 / 空间码 / 密码 / 设备名。
class SettingsScreen extends StatefulWidget {
  final AppController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _server;
  late final TextEditingController _space;
  late final TextEditingController _spaceKey;
  late final TextEditingController _apiKey;
  late final TextEditingController _name;
  bool _saving = false;

  /// 各输入框在 init 时的快照：控制器异步读完磁盘后，只把
  /// “用户没碰过”（仍等于快照）的框补成最新值，绝不覆盖用户输入。
  late final Map<TextEditingController, String> _snapshot;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _server = TextEditingController(text: c.serverUrl);
    _space = TextEditingController(text: c.spaceId);
    _spaceKey = TextEditingController(text: c.spaceKey);
    _apiKey = TextEditingController(text: c.apiKey);
    _name = TextEditingController(text: c.deviceName);
    _snapshot = {
      _server: c.serverUrl,
      _space: c.spaceId,
      _spaceKey: c.spaceKey,
      _apiKey: c.apiKey,
      _name: c.deviceName,
    };
    c.addListener(_syncFromController);
    _syncFromController();
  }

  void _syncFromController() {
    if (!mounted) return;
    final c = widget.controller;
    if (!c.isInitialized) return;
    // 延迟到帧后：build 过程中直接改 TextEditingController 会抛异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fresh = {
        _server: c.serverUrl,
        _space: c.spaceId,
        _spaceKey: c.spaceKey,
        _apiKey: c.apiKey,
        _name: c.deviceName,
      };
      fresh.forEach((ctrl, value) {
        if (ctrl.text == _snapshot[ctrl] && ctrl.text != value) {
          ctrl.text = value;
        }
        _snapshot[ctrl] = ctrl.text;
      });
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _server.dispose();
    _space.dispose();
    _spaceKey.dispose();
    _apiKey.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => ListView(
              key: const Key('settings_list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _buildConnCard(),
                const SizedBox(height: 12),
                _buildAppearanceCard(),
                const SizedBox(height: 12),
                _buildAboutCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: CardDecoration.gradient(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF9575CD), Color(0xFF7E57C2)],
              ),
              radius: 16,
            ),
            child: const Icon(
              Icons.settings_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.of(context).text,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                '连接你的云端空间',
                style: TextStyle(
                    fontSize: 13, color: AppPalette.of(context).sub),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnCard() {
    final c = widget.controller;
    return Container(
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _connStateRow(c),
          const SizedBox(height: 12),
          _buildRecordRows(c),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('f_server'),
            control: FTextFieldControl.managed(controller: _server),
            label: const Text('服务端地址'),
            hint: 'ws://你的云服务器IP:8080/ws',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FTextField(
                  key: const Key('f_space'),
                  control: FTextFieldControl.managed(controller: _space),
                  label: const Text('空间码'),
                  hint: '如 my-space',
                ),
              ),
              const SizedBox(width: 8),
              FButton(
                variant: .outline,
                onPress: () {
                  _space.text = _randomSpace();
                },
                child: const Text('随机'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FTextField.password(
            key: const Key('f_space_key'),
            control: FTextFieldControl.managed(controller: _spaceKey),
            label: const Text('空间密码（可选）'),
            hint: '首次加入即创建，之后须一致',
          ),
          const SizedBox(height: 12),
          FTextField.password(
            key: const Key('f_api_key'),
            control: FTextFieldControl.managed(controller: _apiKey),
            label: const Text('服务端密钥（可选）'),
            hint: '与服务端 API_KEY 一致',
          ),
          const SizedBox(height: 12),
          FTextField(
            key: const Key('f_name'),
            control: FTextFieldControl.managed(controller: _name),
            label: const Text('本机显示名称'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FButton(
              onPress: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存并重连'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FButton(
              variant: .outline,
              onPress: () => c.disconnect(),
              child: const Text('断开连接'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connStateRow(AppController c) {
    final svc = c.service;
    final Color color;
    final String label;
    switch (svc.state) {
      case ConnState.connected:
        color = const Color(0xFF4CAF50);
        label = '已连接 · ${svc.devices.length} 台在线';
        break;
      case ConnState.connecting:
        color = AppTheme.accentOrange;
        label = '连接中…';
        break;
      case ConnState.disconnected:
        color = const Color(0xFFF44336);
        label = '未连接';
        break;
    }
    String? err;
    if (svc.lastErrorCode != null) {
      err = svc.lastErrorMessage ?? friendlyError(svc.lastErrorCode!);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (err != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    err,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppPalette.of(context).sub,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _randomSpace() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// 当前记录（只读）：上次连接用的值都在这里，一眼可查。
  Widget _buildRecordRows(AppController c) {
    final rows = [
      (Icons.dns_rounded, '服务端', c.serverUrl),
      (Icons.meeting_room_rounded, '空间', c.spaceId),
      (Icons.badge_rounded, '本机', c.deviceName),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppPalette.of(context).chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final (icon, label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppPalette.of(context).faint),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.of(context).sub,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value.isEmpty ? '未填写' : value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: value.isEmpty
                            ? AppPalette.of(context).faint
                            : AppPalette.of(context).text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final server = _server.text.trim();
    final space = _space.text.trim();
    if (server.isEmpty || space.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('服务端地址和空间码都要填'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (normalizeServerUrl(server) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('服务端地址格式不对，如 ws://1.2.3.4:8080/ws'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!isValidSpaceId(space)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('空间码格式不对（3-32位字母数字及 -_）'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveSettings(
        serverUrl: server,
        spaceId: space,
        spaceKey: _spaceKey.text,
        apiKey: _apiKey.text.trim(),
        deviceName: _name.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保存，正在重连…'),
          duration: Duration(seconds: 1),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 外观切换：跟随系统 / 浅色 / 深色，即时生效并持久化。
  Widget _buildAppearanceCard() {
    final c = widget.controller;
    return Container(
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.palette_rounded,
                color: AppTheme.primaryBlue,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '外观',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.of(context).text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded, size: 18),
                  label: Text('跟随系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded, size: 18),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded, size: 18),
                  label: Text('深色'),
                ),
              ],
              selected: {c.themeMode.value},
              showSelectedIcon: false,
              onSelectionChanged: (s) => c.setThemeMode(s.first),
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_rounded,
                color: AppTheme.accentOrange,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '关于 AirFly',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.of(context).text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'AirFly 2.0 · 云中转版\n多端通过云服务端同步剪切板与文件，不再局限于局域网。同一空间码的设备共享剪切板和文件，文件支持断点续传。',
            style: TextStyle(
              fontSize: 14,
              color: AppPalette.of(context).sub,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '提示：空间码 + 密码就是你们的房间钥匙，别告诉外人。',
            style: TextStyle(fontSize: 13, color: AppPalette.of(context).text),
          ),
        ],
      ),
    );
  }
}
