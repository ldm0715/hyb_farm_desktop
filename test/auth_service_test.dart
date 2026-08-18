/// AuthService 账户统计（VIP / 余额）测试：加载填充、失败静默、换账号清旧值重拉。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/api_client.dart';
import 'package:hyb_farm_desktop/api/farm_api.dart';
import 'package:hyb_farm_desktop/api/models.dart';
import 'package:hyb_farm_desktop/auth/auth_service.dart';

/// 内存 FarmApi 子类：覆盖用户信息与账户统计，可注入数据/异常并记录调用次数，不碰 HTTP。
class _FakeApi extends FarmApi {
  _FakeApi() : super(ApiClient());

  UserInfo userInfo = const UserInfo(username: 'Alice');
  DashboardStats stats =
      const DashboardStats(walletBalance: 18542118626, isVip: true);
  Exception? statsError;
  int statsCalls = 0;

  @override
  Future<UserInfo> fetchUserInfo() async => userInfo;

  @override
  Future<DashboardStats> fetchDashboardStats() async {
    statsCalls++;
    final e = statsError;
    if (e != null) throw e;
    return stats;
  }
}

void main() {
  test('loadDashboardStats 成功填充 isVip / walletBalance', () async {
    final api = _FakeApi();
    final auth = AuthService(client: ApiClient(), api: api);

    expect(auth.isVip, isFalse);
    expect(auth.walletBalance, 0);

    await auth.loadDashboardStats();
    expect(auth.isVip, isTrue);
    expect(auth.walletBalance, 18542118626);
    expect(api.statsCalls, 1);
  });

  test('拉取失败静默：保持旧值、不改变认证状态', () async {
    final api = _FakeApi();
    final auth = AuthService(client: ApiClient(), api: api);

    await auth.loadDashboardStats();
    expect(auth.isVip, isTrue);
    final statusBefore = auth.status;

    api.statsError = Exception('network');
    await auth.loadDashboardStats(); // 不抛异常
    expect(auth.isVip, isTrue); // 保持旧值
    expect(auth.walletBalance, 18542118626);
    expect(auth.status, statusBefore); // 认证状态不变
  });

  test('换账号（saveCookie）清旧值并重新拉取新账号统计', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _FakeApi();
    final auth = AuthService(client: ApiClient(), api: api);

    // 登录 A（VIP）。
    await auth.saveCookie('a=1');
    await pumpEventQueue();
    expect(auth.isVip, isTrue);
    expect(auth.walletBalance, 18542118626);
    expect(auth.username, 'Alice');
    final callsAfterA = api.statsCalls;

    // 切到 B（非 VIP）：换 Cookie 登录，只更新登录态，不退出登录。
    api.userInfo = const UserInfo(username: 'Bob');
    api.stats = const DashboardStats(walletBalance: 0, isVip: false);
    await auth.saveCookie('b=2');
    await pumpEventQueue();

    expect(auth.isVip, isFalse); // 三处同步显示 B 的非 VIP 状态
    expect(auth.walletBalance, 0);
    expect(auth.username, 'Bob');
    expect(auth.status, AuthStatus.authenticated); // 账号保持登录
    expect(api.statsCalls, greaterThan(callsAfterA)); // 重新拉取了 B 的统计
  });

  test('clearCookie 清空账户统计', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _FakeApi();
    final auth = AuthService(client: ApiClient(), api: api);

    await auth.saveCookie('a=1');
    await pumpEventQueue();
    expect(auth.isVip, isTrue);

    await auth.clearCookie();
    expect(auth.isVip, isFalse);
    expect(auth.walletBalance, 0);
    expect(auth.status, AuthStatus.expired);
  });
}
