import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/api/models.dart';

void main() {
  test('CropsResponse 解析 crops 字段与 totalSlots 兜底', () {
    final resp = CropsResponse.fromJson({
      'crops': [
        {
          'id': 'a',
          'seedId': 'pumpkin',
          'seedName': '南瓜',
          'seedImage': '/farm/crops/pumpkin',
          'plotIndex': 0,
          'isMature': true,
          'remainingTime': 0,
          'conditions': [
            {'kind': 'thirsty'},
          ],
        },
      ],
      'maxSlots': 4,
    });

    expect(resp.crops.length, 1);
    expect(resp.totalSlots, 4);
    expect(resp.plantedCount, 1);
    expect(resp.freeSlots, 3);
    expect(resp.crops.first.mature, isTrue);
    expect(resp.crops.first.hasDebuff, isTrue);
  });

  test('totalSlots 缺失时用 plotLevels 最大 plotIndex+1 兜底', () {
    final resp = CropsResponse.fromJson({
      'crops': [],
      'plotLevels': [
        {'plotIndex': 0, 'level': 1, 'theme': 'a'},
        {'plotIndex': 2, 'level': 1, 'theme': 'b'},
      ],
    });
    expect(resp.totalSlots, 3);
  });

  test('crops 响应 data 字段为数组时不丢失外层 maxSlots', () {
    final resp = CropsResponse.fromJson({
      'success': true,
      'data': [
        {
          'id': 'a',
          'seedId': 's',
          'seedName': 'n',
          'seedImage': 'img',
          'plotIndex': 0,
        },
      ],
      'maxSlots': 6,
    });
    expect(resp.crops.length, 1);
    expect(resp.totalSlots, 6);
    expect(resp.freeSlots, 5);
  });

  test('Crop.mature 判定 isMature 或 remainingTime<=0', () {
    const mature = Crop(
      id: 'x',
      seedId: 's',
      seedName: 'n',
      seedImage: 'img',
      plotIndex: 0,
      isMature: false,
      remainingTime: 0,
    );
    expect(mature.mature, isTrue);

    const growing = Crop(
      id: 'x',
      seedId: 's',
      seedName: 'n',
      seedImage: 'img',
      plotIndex: 0,
      isMature: false,
      remainingTime: 100,
    );
    expect(growing.mature, isFalse);
    expect(growing.isEmpty, isFalse);
  });
}
