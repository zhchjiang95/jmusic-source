import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/webdav_provider.dart';
import 'package:jmusic/services/webdav_service.dart';

/// WebDAV 音乐源管理底部弹窗
class WebDavSheet extends ConsumerStatefulWidget {
  const WebDavSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const WebDavSheet(),
    );
  }

  @override
  ConsumerState<WebDavSheet> createState() => _WebDavSheetState();
}

class _WebDavSheetState extends ConsumerState<WebDavSheet> {
  bool _showAddForm = false;
  final _nameController = TextEditingController(text: 'WebDAV');
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webDav = ref.watch(webDavProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 标题
          Row(
            children: [
              const Icon(Icons.cloud_outlined, color: Colors.white70),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'WebDAV 音乐源',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!_showAddForm)
                IconButton(
                  onPressed: () => setState(() => _showAddForm = true),
                  icon: const Icon(Icons.add, color: Colors.white70),
                  tooltip: '添加',
                ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            '添加 WebDAV 地址后，可直接播放云端音乐文件',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),

          // 错误提示
          if (webDav.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      webDav.error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // 已有配置列表
          if (webDav.configs.isNotEmpty) ...[
            ...webDav.configs.asMap().entries.map((entry) {
              final idx = entry.key;
              final config = entry.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_shared,
                    color: Colors.white54),
                title: Text(config.name,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  config.url,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  onPressed: () =>
                      ref.read(webDavProvider.notifier).removeConfig(idx),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.white38, size: 20),
                ),
              );
            }),
            // 歌曲数量 + 扫描状态
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${webDav.songs.length} 首云端歌曲',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (webDav.isScanning)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton(
                      onPressed: () =>
                          ref.read(webDavProvider.notifier).scanAll(),
                      child: const Text('刷新',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],

          // 添加表单
          if (_showAddForm) ...[
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),
            _buildTextField(_nameController, '名称', '如: 坚果云音乐'),
            const SizedBox(height: 10),
            _buildTextField(
                _urlController, 'WebDAV 地址', 'https://dav.example.com/music'),
            const SizedBox(height: 10),
            _buildTextField(_userController, '用户名', ''),
            const SizedBox(height: 10),
            _buildTextField(_passController, '密码', '', obscure: true),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _showAddForm = false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isAdding ? null : _addConfig,
                    child: _isAdding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('添加'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, String hint,
      {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Future<void> _addConfig() async {
    final url = _urlController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();
    final name = _nameController.text.trim();

    if (url.isEmpty || user.isEmpty || pass.isEmpty) return;

    setState(() => _isAdding = true);

    final config = WebDavConfig(
      url: url,
      username: user,
      password: pass,
      name: name.isEmpty ? 'WebDAV' : name,
    );

    final ok = await ref.read(webDavProvider.notifier).addConfig(config);

    if (mounted) {
      setState(() => _isAdding = false);
      if (ok) {
        setState(() => _showAddForm = false);
        _urlController.clear();
        _userController.clear();
        _passController.clear();
        _nameController.text = 'WebDAV';
      }
    }
  }
}
