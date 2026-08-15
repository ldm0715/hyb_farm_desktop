/// OperationCoordinator 串行化测试：写操作互斥与失败恢复。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/core/operation_coordinator.dart';

void main() {
  test('串行执行：第二个操作等待第一个完成', () async {
    final coord = OperationCoordinator();
    final order = <String>[];
    final gate = Completer<void>();

    final f1 = coord.run(() async {
      order.add('start1');
      await gate.future;
      order.add('end1');
      return 1;
    });
    final f2 = coord.run(() async {
      order.add('start2');
      return 2;
    });

    // 让 f1 先跑起来，f2 仍排队等待。
    await Future<void>.delayed(Duration.zero);
    expect(order, ['start1']);

    gate.complete();
    expect(await f1, 1);
    expect(await f2, 2);
    expect(order, ['start1', 'end1', 'start2']);
  });

  test('返回值与类型透传', () async {
    final coord = OperationCoordinator();
    expect(await coord.run(() async => 'ok'), 'ok');
    expect(await coord.run(() async => 42), 42);
  });

  test('失败的操作不阻塞后续排队操作', () async {
    final coord = OperationCoordinator();
    final order = <String>[];

    final f1 = coord.run(() async {
      order.add('1');
      throw Exception('boom');
    });
    final f2 = coord.run(() async {
      order.add('2');
      return 42;
    });

    await expectLater(f1, throwsException);
    expect(await f2, 42);
    expect(order, ['1', '2']);
  });
}
