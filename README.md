# DCS Eastern SAM Simulator

DCS Worldで東側SAMシステムを、SAMSimのようにブラウザから操作できるシステムです。

## 対応システム

| NATO呼称 | ソ連呼称 | 捜索レーダー | 火器管制レーダー | ミサイル |
|----------|----------|--------------|------------------|----------|
| SA-2 Guideline | S-75 Dvina | P-19 "Flat Face" | SNR-75 "Fan Song" | V-750 |
| SA-3 Goa | S-125 Neva/Pechora | P-15 "Flat Face" | SNR-125 "Low Blow" | 5V27 |
| SA-6 Gainful | 2K12 Kub | 1S91 "Straight Flush" | 1S91 (複合型) | 3M9 |
| SA-10 Grumble | S-300PS | 64N6 "Big Bird" | 30N6 "Flap Lid" | 5V55R |
| SA-11 Gadfly | 9K37 Buk | 9S18 "Snow Drift" | 9S35 "Fire Dome" | 9M38 |

## 概要

このプロジェクトは、DCS Worldの各種SAMシステムをリアルなオペレーター視点で操作できるようにします。

### 主な機能

- **マルチシステム対応**: SA-2, SA-3, SA-6, SA-10, SA-11をサポート
- **レーダースコープ表示**: PPI形式の捜索/火器管制レーダー画面
- **A-Scope/B-Scope**: 距離・仰角表示
- **マルチチャンネル**: SA-10/SA-11の複数目標同時交戦
- **射撃諸元計算**: 撃墜確率(Pk)、迎撃点予測
- **リアルタイム通信**: DCSとブラウザ間のリアルタイムデータ同期

## システム構成

```
┌─────────────────────────────────────────────────────────┐
│                     DCS World                           │
│  ┌──────────────────┐    ┌─────────────────────────┐   │
│  │  Mission Script  │◄──►│  Export.lua             │   │
│  │  (SAM Controller)│    │  (UDP通信)              │   │
│  └──────────────────┘    └─────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                              │ UDP (Port 7777/7778)
                              ▼
┌─────────────────────────────────────────────────────────┐
│              Python SAMSIM Server                        │
│         (UDP Handler + WebSocket Server)                │
└─────────────────────────────────────────────────────────┘
                              │ WebSocket (Port 8081)
                              ▼
┌─────────────────────────────────────────────────────────┐
│                   Web Browser                            │
│              (SAMSimインターフェース)                    │
└─────────────────────────────────────────────────────────┘
```

## 各システムの特徴

### SA-2 Guideline (S-75 Dvina)
- 高高度防空に最適化
- 単一目標追尾
- CLOS (Command Line of Sight) 誘導
- 最大射程: 45km

### SA-3 Goa (S-125 Neva/Pechora)
- 低高度性能が優秀
- SA-2より高機動目標への対処能力向上
- 最大射程: 25km、最小高度: 20m

### SA-6 Gainful (2K12 Kub)
- 自走式で機動性高い
- 捜索・追尾レーダー統合型
- SARH (Semi-Active Radar Homing) 誘導
- 最大射程: 24km

### SA-10 Grumble (S-300PS)
- 長距離防空システム
- 6チャンネル同時交戦能力
- TVM (Track Via Missile) 誘導
- 最大射程: 90km

### SA-11 Gadfly (9K37 Buk)
- 中距離野戦防空
- 4基のTELARによる同時交戦
- SARH誘導
- 最大射程: 35km

## インストール手順

### 1. 前提条件

- DCS World (最新版推奨)
- Python 3.10以上
- モダンブラウザ (Chrome, Firefox, Edge)

### 2. Pythonサーバーのセットアップ

```bash
cd server
pip install aiohttp websockets
python samsim_server.py
```

### 3. DCSへのスクリプト導入

#### Mission Script
使用するSAMシステムのLuaファイルをミッションに追加:

- `SA2_SAMSIM.lua` - SA-2用
- `SA3_SAMSIM.lua` - SA-3用
- `SA6_SAMSIM.lua` - SA-6用
- `SA10_SAMSIM.lua` - SA-10用
- `SA11_SAMSIM.lua` - SA-11用
- `SAMSIM_Unified.lua` - 統合コントローラー（複数システム使用時）

#### Export.lua
`SAMSIM_Export.lua`をSaved Games/DCS/Scriptsに配置

### 4. ブラウザでアクセス

```
http://localhost:8080
```

## 使用方法

1. **システム選択**: ヘッダーのドロップダウンからSAMシステムを選択
2. **電源投入**: STARTUPボタンでシステム起動
3. **捜索開始**: 捜索レーダーをSEARCHモードに設定
4. **目標指定**: ターゲットリストから目標を選択し、DESIGNATEをクリック
5. **追尾**: 火器管制レーダーがTRACKモードに移行
6. **発射**: IN ZONEになったらLAUNCHボタンで発射

## ファイル構成

```
Dcs-samsim/
├── lua/
│   ├── mission/
│   │   ├── SA2_SAMSIM.lua
│   │   ├── SA3_SAMSIM.lua
│   │   ├── SA6_SAMSIM.lua
│   │   ├── SA10_SAMSIM.lua
│   │   ├── SA11_SAMSIM.lua
│   │   └── SAMSIM_Unified.lua
│   └── export/
│       └── SAMSIM_Export.lua
├── server/
│   ├── samsim_server.py
│   └── static/
│       ├── index.html
│       ├── css/samsim.css
│       └── js/samsim.js
└── README.md
```

## 技術仕様

### 通信プロトコル
- DCS ↔ Server: UDP (Port 7777受信, 7778送信)
- Server ↔ Browser: WebSocket (Port 8081)
- Static Files: HTTP (Port 8080)

### レーダーシミュレーション
- RCSベースの検出確率計算
- レーダー方程式に基づく探知距離
- カルマンフィルタ風トラック平滑化
- ドップラー効果（SA-6, SA-10, SA-11）

## ライセンス

MIT License

## 作者

Claude Code
