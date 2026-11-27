# NBDashR — 九号 5 寸仪表投屏(全量重构版)

纯源码重构,**非注入**。功能:

- **免九号出行投屏**:carwithin V2 加密配对(按 P 键一次永久有效),0x71 导航唤醒,配置完成后打开 App 自动投屏
- **蚂蚁 ANT BMS**:FFE0/FFE1 GATT 直连,严格只读;实时功率/峰值/回收/电量/电压/单体直出仪表
- **六套仪表主题**:运动仪表(宝马TFT)/ 赛博竞技 / 超维引擎 / 赛道遥测 / 极简高亮 / 流萤
- **GPS+IMU 车速融合**、行程统计、压弯倾角、G 值
- UDP 5012/5013 H.264 硬编推流(协议对照 OpenNinebot cast_protocol,MIT)

## 构建

GitHub Actions「Build unsigned IPA」产出未签名 IPA,TrollStore/Sideloadly/AltStore 签名安装(iOS 16+)。

```bash
xcodebuild -project NBDashR.xcodeproj -scheme NBDashR \
  -configuration Release -sdk iphoneos -arch arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build
```

## 首次使用

1. 车辆通电 →「车辆配对」→ 扫描选车 → 建立本机配对 → 等「车机已就绪」震动 → 短按车上 P 键
2. 「ANT 保护板设置」→ 扫描并绑定你的蚂蚁保护板
3. 之后打开 App 即自动连接唤醒并投屏;仪表用 P 键/按键退出导航会自动停止推流

## 许可

车辆 BLE 配对/加密源自 carwithin(AGPL-3.0-only);ANT 帧解析参考 maibms(MIT);
UDP 投屏协议对照 OpenNinebot cast_protocol(MIT)。本项目按 AGPL-3.0-only 分发,仅供个人研究学习。
