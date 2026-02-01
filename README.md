# DCS SA-2 SAMSim Controller

DCS WorldでSA-2 (S-75 Dvina) 地対空ミサイルシステムを、SAMSimのようにブラウザから操作できるシステムです。

## 概要

このプロジェクトは、DCS WorldのSA-2をリアルなSAMオペレーター視点で操作できるようにします。

### 主な機能

- **レーダースコープ表示**: PPI（Plan Position Indicator）形式のレーダー画面
- **ターゲット追尾**: 複数目標の探知と単一目標の追尾
- **ミサイル発射制御**: 手動またはオート発射モード
- **リアルタイム通信**: DCSとブラウザ間のリアルタイムデータ同期

## システム構成

```
┌─────────────────────────────────────────────────────────┐
│                     DCS World                           │
│  ┌──────────────────┐    ┌─────────────────────────┐   │
│  │  Mission Script  │◄──►│  Export.lua             │   │
│  │  (SA-2 AI制御)   │    │  (UDP通信)              │   │
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
│              (SAMSim風インターフェース)                  │
└─────────────────────────────────────────────────────────┘
```

## インストール手順

### 1. 前提条件

- DCS World (最新版推奨)
- Python 3.10以上
- モダンブラウザ (Chrome, Firefox, Edge)

### 2. Pythonサーバーのセットアップ

```bash
# リポジトリのクローン
git clone https://github.com/yourusername/Dcs-samsim.git
cd Dcs-samsim

# Python依存関係のインストール
cd server
pip install -r requirements.txt
```

### 3. DCSスクリプトのインストール

#### Export.luaの設定

1. `lua/export/SAMSIM_Export.lua` を以下の場所にコピー:
   ```
   %USERPROFILE%\Saved Games\DCS\Scripts\SAMSIM_Export.lua
   ```

2. `%USERPROFILE%\Saved Games\DCS\Scripts\Export.lua` を編集（なければ作成）:
   ```lua
   local SAMSIMLfs = require('lfs')
   dofile(SAMSIMLfs.writedir() .. "Scripts/SAMSIM_Export.lua")
   ```

#### ミッションスクリプトの設定

1. `lua/mission/SA2_SAMSIM.lua` をミッションに組み込む方法:

   **方法A: ミッションエディタで直接読み込み**
   - ミッションエディタで「トリガー」を開く
   - 「ミッション開始時」トリガーを作成
   - アクション「スクリプトファイル実行」でSA2_SAMSIM.luaを選択

   **方法B: Scriptsフォルダに配置**
   ```
   %USERPROFILE%\Saved Games\DCS\Scripts\SAMSIM\SA2_SAMSIM.lua
   ```

### 4. DCSミッションの準備

ミッションエディタでSA-2サイトを配置:

1. **新規グループを作成** (赤軍または青軍)
2. **以下のユニットを追加**:
   - SNR-75 "Fan Song" (追尾レーダー) - 必須
   - 5P73 発射機 x 6 (推奨)
   - P-19 レーダー (早期警戒用、任意)

3. **グループ名を設定** (例: "SA-2 Site Alpha")

4. **サンプルスクリプトを参照**: `lua/mission/SA2_SAMSIM_Example.lua`

## 使用方法

### 1. サーバーの起動

```bash
cd server
python samsim_server.py
```

起動すると以下が表示されます:
```
╔═══════════════════════════════════════════════════════════╗
║                    SAMSIM Server                          ║
╠═══════════════════════════════════════════════════════════╣
║  HTTP Server:      http://localhost:8080                  ║
║  WebSocket Server: ws://localhost:8081                    ║
╚═══════════════════════════════════════════════════════════╝
```

### 2. DCSミッションの開始

1. DCS Worldを起動
2. 準備したミッションを読み込み
3. ミッションを開始

### 3. ブラウザでアクセス

1. ブラウザで `http://localhost:8080` を開く
2. 接続状態が「Connected」になることを確認
3. サイトを選択または初期化

### 4. SA-2の操作

#### 基本操作フロー

1. **電源投入**: [POWER ON] ボタンをクリック
2. **探知モード**: [SEARCH] ボタンでレーダー起動
3. **目標選択**: レーダー画面で目標をクリック
4. **追尾開始**: [DESIGNATE] ボタンで追尾開始
5. **発射**: [LAUNCH MISSILE] ボタンでミサイル発射

#### レーダーモード

| モード | 説明 |
|--------|------|
| STANDBY | 待機状態（レーダーオフ） |
| SEARCH | 360度探知モード |
| TRACK | 目標追尾モード |
| GUIDE | ミサイル誘導モード |

#### オートエンゲージ

1. [Engagement Auth] を有効化
2. [Auto Engage] を有効化
3. システムが自動的に最も近い目標を追尾・攻撃

## ファイル構成

```
Dcs-samsim/
├── lua/
│   ├── mission/
│   │   ├── SA2_SAMSIM.lua          # メインミッションスクリプト
│   │   └── SA2_SAMSIM_Example.lua  # サンプルミッション設定
│   └── export/
│       └── SAMSIM_Export.lua       # DCS Export統合
├── server/
│   ├── samsim_server.py            # Pythonサーバー
│   ├── requirements.txt            # Python依存関係
│   └── static/
│       ├── index.html              # WebUI HTML
│       ├── css/
│       │   └── samsim.css          # スタイルシート
│       └── js/
│           └── samsim.js           # クライアントJavaScript
└── docs/
    └── (ドキュメント)
```

## SA-2 (S-75) システム仕様

### 基本性能（実装値）

| パラメータ | 値 |
|-----------|-----|
| 最大探知距離 | 160 km |
| 最大交戦距離 | 45 km |
| 最小交戦距離 | 7 km |
| 最大高度 | 30 km |
| 最小高度 | 500 m |
| ミサイル速度 | 1200 m/s |
| アンテナ回転速度 | 6°/秒 |

### ミサイル (V-750VK)

- 搭載数: 6発（典型的な1個中隊）
- 最大飛翔時間: 60秒
- 誘導方式: 指令誘導

## トラブルシューティング

### サーバーに接続できない

1. ファイアウォールでポート8080, 8081を許可
2. サーバーが起動していることを確認
3. ブラウザのコンソールでエラーを確認

### DCSと接続できない

1. Export.luaが正しく設定されていることを確認
2. DCSのログを確認: `%USERPROFILE%\Saved Games\DCS\Logs\dcs.log`
3. ポート7777, 7778が使用可能であることを確認

### ターゲットが表示されない

1. ミッション内に敵航空機が存在することを確認
2. SA-2サイトが正しく配置されていることを確認
3. レーダーモードがSEARCHまたはTRACKになっていることを確認

## 今後の拡張予定

- [ ] マルチプレイヤー対応（複数オペレーター）
- [ ] 他のSAMシステム対応（SA-3, SA-6など）
- [ ] より詳細なレーダーシミュレーション
- [ ] 音声警告システム
- [ ] ジャミング効果のシミュレーション

## ライセンス

MIT License

## 謝辞

- DCS World Mission Scripting API
- SAMSim (オリジナルのSAMオペレータートレーナー)
- DCSコミュニティ
