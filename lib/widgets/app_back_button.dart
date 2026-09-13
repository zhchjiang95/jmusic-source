import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 适配 macOS 沉浸式红黄绿交通灯的通用返回/关闭按钮
///
/// 在 macOS 沉浸式无标题栏窗口模式下，左上角红黄绿按钮宽度约占 70px。
/// 使用此组件作为 AppBar.leading 或自定义导航行左侧按钮时，会自动进行避让。
class AppLeadingBackButton extends StatelessWidget {
  /// 点击回调，默认执行 Navigator.of(context).pop()
  final VoidCallback? onPressed;

  /// 图标数据，默认为 Icons.arrow_back
  final IconData icon;

  /// 图标大小，默认为 20
  final double iconSize;

  /// 图标颜色
  final Color? color;

  /// 提示文本
  final String? tooltip;

  const AppLeadingBackButton({
    super.key,
    this.onPressed,
    this.icon = Icons.arrow_back,
    this.iconSize = 20,
    this.color,
    this.tooltip,
  });

  /// 适用于 AppBar.leadingWidth 的自适应宽度
  static double? get leadingWidth =>
      (!kIsWeb && Platform.isMacOS) ? 124 : null;

  @override
  Widget build(BuildContext context) {
    final isMac = !kIsWeb && Platform.isMacOS;

    final button = IconButton(
      icon: Icon(icon, size: iconSize, color: color),
      tooltip: tooltip ?? '返回',
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
    );

    if (isMac) {
      return Padding(
        padding: const EdgeInsets.only(left: 76),
        child: button,
      );
    }

    return button;
  }
}
