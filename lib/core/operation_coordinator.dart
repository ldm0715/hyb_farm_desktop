/// 写操作协调器：保证同一时间只有一个写操作流程在执行。
library;

import 'dart:async';

class OperationCoordinator {
  Future<void> _queue = Future<void>.value();

  /// 串行执行一个写操作，返回该操作的结果；失败不阻塞后续排队操作。
  Future<T> run<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
