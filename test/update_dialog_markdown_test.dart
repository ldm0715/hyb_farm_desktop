/// 更新说明对话框的 markdown 渲染回归测试。
///
/// 更新说明（`UpdateInfo.body`）是 GitHub Releases 的 markdown 原文，必须经
/// `MarkdownBody` 渲染（标题/列表被解析、可选中），而非原样显示 `##` 等裸字符。
/// 不点「下载/安装」按钮，避免触碰 `UpdateService`/`TrayManager` Provider。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/services/update_service.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/update_dialog.dart';

void main() {
  testWidgets('更新说明经 MarkdownBody 渲染标题与列表而非裸字符', (tester) async {
    const info = UpdateInfo(
      tagName: 'v0.1.4',
      name: '',
      body: '## 新特性\n- 支持 markdown 渲染\n\n**加粗**文本',
      htmlUrl: '',
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showUpdateDialog(context, info),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    // 标题「新特性」被解析为独立文本块；原样显示时会是「## 新特性」。
    expect(find.text('新特性', findRichText: true), findsOneWidget);
    // 列表项「- 支持 markdown 渲染」解析后只留文本。
    expect(find.text('支持 markdown 渲染', findRichText: true), findsOneWidget);
    // 更新说明原文（含裸 `##`/`-`）不应整体出现。
    expect(find.textContaining('##', findRichText: true), findsNothing);
  });
}
