# DCS SAM Simulator (SAMSIM)

DCS Worldで東側・西側SAMシステムを、ブラウザから操作できるシステムです。
**MIST不要** - 全てDCS Native APIで動作します。

## 対応システム

### 東側 (8システム)

| NATO呼称 | ソ連呼称 | カテゴリ | 最大射程 |
|----------|----------|----------|----------|
| SA-2 Guideline | S-75 Dvina | 長距離 | 45km |
| SA-3 Goa | S-125 Neva | 中距離 | 25km |
| SA-6 Gainful | 2K12 Kub | 中距離 | 24km |
| SA-10 Grumble | S-300PS | 長距離 | 150km |
| SA-11 Gadfly | 9K37 Buk | 中距離 | 35km |
| SA-8 Gecko | 9K33 Osa | 短距離 | 10km |
| SA-15 Gauntlet | 9K330 Tor | 短距離 | 12km |
| SA-19 Grison | 2S6 Tunguska | 短距離 | 8km |

### 西側 (3システム)

| 名称 | 国 | カテゴリ | 最大射程 |
|------|-----|----------|----------|
| MIM-104 Patriot | USA | 長距離 | 160km |
| MIM-23 HAWK | USA | 中距離 | 40km |
| Roland 2/3 | France/Germany | 短距離 | 8km |

## 主な機能

### コア機能
- **マルチシステム対応**: 11種類のSAMシステムをサポート
- **レーダースコープ表示**: PPI/B-Scope/A-Scopeリアルタイム表示
- **射撃管制**: 撃墜確率(Pk)計算、迎撃点予測
- **ECM/ECCM**: 電子戦シミュレーション

### IADS機能 (統合防空システム)
- **ネットワーク管理**: SAM/EWR自動検出・リンク
- **脅威追跡**: 目標分類・優先度計算
- **セクター管理**: 防空セクター・適応カバレッジ
- **SEAD対策**: ARM検出・自動EMCON・バックアップ起動

### マルチプレイヤー
- **ロールベース制御**: Commander, Operator, Observer
- **チャット機能**: チーム内コミュニケーション

---

## クイックスタート

### 1. 基本セットアップ（簡易）

ミッションエディタで以下をDO SCRIPT FILEで読み込み:

```lua
-- SAMSIM_Main.lua を読み込み
dofile(lfs.writedir() .. "Scripts/SAMSIM_Main.lua")

-- RED側IADSを自動セットアップ
SAMSIM.initRed()
```

これだけで:
- `SAM_` で始まるグループをSAMとして登録
- `EWR_` で始まるグループをEWRとして登録
- 150km以内のノードを自動リンク
- SEADシミュレーション有効化

### 2. カスタムセットアップ

```lua
dofile(lfs.writedir() .. "Scripts/SAMSIM_Main.lua")

SAMSIM.init({
    -- デバッグ
    debug = true,

    -- 自動検出パターン
    autoDetect = true,
    samPattern = "^RED_SAM_",  -- RED_SAM_ で始まるグループ
    ewrPattern = "^RED_EWR_",  -- RED_EWR_ で始まるグループ

    -- ネットワーク設定
    networkName = "IRAN_IADS",
    coalition = coalition.side.RED,
    maxLinkDistance = 200000,  -- 200km

    -- SEAD設定
    seadEnabled = true,
    autoEMCON = true,          -- ARM検出時自動レーダーオフ
    backupActivation = true,   -- 被抑圧時バックアップ起動

    -- セクター管理
    sectorsEnabled = true,
    adaptiveCoverage = true,   -- 脅威レベル連動カバレッジ
})
```

### 3. 両陣営セットアップ

```lua
dofile(lfs.writedir() .. "Scripts/SAMSIM_Main.lua")

local redNetwork, blueNetwork = SAMSIM.initBoth({
    redSamPattern = "^RED_SAM_",
    redEwrPattern = "^RED_EWR_",
    blueSamPattern = "^BLUE_SAM_",
    blueEwrPattern = "^BLUE_EWR_",
})
```

---

## 詳細使用方法

### IADS ネットワーク管理

#### 手動でSAM/EWRを追加

```lua
-- 初期化後にネットワークを取得
local network = SAMSIM.network

-- SAMを追加（タイプ自動検出）
SAMSIM.addSAM("SAM_Alpha")

-- SAMを追加（タイプ指定）
SAMSIM.addSAM("SAM_Bravo", "SA10", {
    priority = 1,  -- 優先度（1=主力, 2=支援, 3=予備）
})

-- EWRを追加
SAMSIM.addEWR("EWR_North")

-- ノード間リンク（距離ベース）
SAMSIM_IADS.autoLinkByDistance(network, 150000)

-- 手動リンク
local node1 = network.sams["SAM_Alpha"]
local node2 = network.ewrs["EWR_North"]
SAMSIM_IADS.linkNodes(network, node1.id, node2.id)
```

#### EMCON制御

```lua
-- 全レーダーオフ
SAMSIM.goDark()

-- 全レーダーオン
SAMSIM.goActive()

-- EMCON レベル設定
SAMSIM.setEMCON("ACTIVE")    -- 全レーダー稼働
SAMSIM.setEMCON("LIMITED")   -- EWRのみ稼働
SAMSIM.setEMCON("DARK")      -- 全レーダー停止
SAMSIM.setEMCON("ADAPTIVE")  -- 脅威連動（自動）

-- 個別サイト制御
local node = network.sams["SAM_Alpha"]
SAMSIM_IADS.setSiteEMCON(node, SAMSIM_IADS.EMCON.DARK)
```

### セクター管理

```lua
-- 円形セクター作成
local sector = SAMSIM.createSector("North_Defense",
    {x = 10000, y = 0, z = 50000},  -- 中心座標
    80000  -- 半径 80km
)

-- DCSトリガーゾーンからセクター作成
local sector = SAMSIM.createSectorFromZone("Defense_Zone_Alpha")

-- セクター内のSAMは自動的に割り当てられる

-- カバレッジモード設定
SAMSIM_Sector.setMinimumCoverage(sector)   -- Priority 1のみ
SAMSIM_Sector.setPartialCoverage(sector)   -- Priority 1-2
SAMSIM_Sector.setFullCoverage(sector)      -- 全SAM
SAMSIM_Sector.setAdaptiveCoverage(sector)  -- 脅威レベル連動（推奨）
```

### 脅威追跡

```lua
-- 脅威統計取得
local stats = SAMSIM.getThreatStats()
print("Active tracks: " .. stats.activeTracks)
print("SEAD threats: " .. (stats.byCategory.SEAD or 0))

-- 高優先度脅威取得
local threats = SAMSIM_Threat.getHighestPriorityThreats(5)
for _, track in ipairs(threats) do
    print(string.format("%s: %s (P%d) at %.0fm",
        track.id, track.category, track.priority, track.altitude))
end

-- 特定位置周辺の脅威
local nearbyThreats = SAMSIM_Threat.getThreatsInRange(
    {x = 10000, y = 0, z = 50000},  -- 位置
    100000  -- 100km
)
```

### SEAD対策

```lua
-- SEAD状況取得
local seadStatus = SAMSIM.getSEADStatus()
print("ARMs in flight: " .. seadStatus.armsInFlight)
print("Suppressed sites: " .. seadStatus.suppressedSites)

-- 手動でサイト抑圧（ARM回避）
SAMSIM_SEAD.suppressGroup("SAM_Alpha", 60)  -- 60秒間レーダーオフ

-- 抑圧からの復帰
SAMSIM_SEAD.reactivateGroup("SAM_Alpha")
```

### ステータス取得

```lua
-- ネットワーク全体の状態
local status = SAMSIM.getStatus()
print("SAMs: " .. status.nodes.sams)
print("EWRs: " .. status.nodes.ewrs)
print("Links: " .. status.links)
print("Active SAMs: " .. status.samStates.active)
print("Suppressed: " .. status.samStates.suppressed)

-- 全セクターの状態
local sectors = SAMSIM.getSectorsStatus()
for _, s in ipairs(sectors) do
    print(string.format("Sector %s: Threat=%d, Active=%d/%d",
        s.name, s.threatLevel, s.sams.active, s.sams.total))
end
```

---

## グループ命名規則

自動検出を使用する場合、以下の命名規則を推奨:

```
[陣営]_[タイプ]_[識別子]

例:
RED_SAM_Alpha        -- RED側SAM "Alpha"
RED_SAM_SA10_North   -- RED側SA-10 北部
RED_EWR_Central      -- RED側EWR 中央
BLUE_SAM_Patriot_01  -- BLUE側Patriot 1番
```

### SAMタイプ自動検出

ユニットタイプ名から自動的にSAMタイプを検出:

| ユニット名パターン | 検出タイプ |
|-------------------|------------|
| `SNR_75V`, `S_75M` | SA2 |
| `snr s-125`, `5p73` | SA3 |
| `Kub 1S91`, `Kub 2P25` | SA6 |
| `S-300PS` | SA10 |
| `SA-11 Buk` | SA11 |
| `Osa 9A33` | SA8 |
| `Tor 9A331` | SA15 |
| `2S6 Tunguska` | SA19 |
| `Patriot` | PATRIOT |
| `Hawk` | HAWK |
| `Roland` | ROLAND |

---

## イベントハンドラ

カスタムロジックを追加可能:

```lua
-- SAM起動イベント
SAMSIM_Events.addHandler(SAMSIM_Events.Type.SAM_ACTIVATED, function(data)
    print("SAM activated: " .. data.groupName)
end)

-- ARM検出イベント
SAMSIM_Events.addHandler(SAMSIM_Events.Type.ARM_DETECTED, function(data)
    print(string.format("ARM incoming! Target: %s, TTI: %.0fs",
        data.targetSite, data.tti))
end)

-- 脅威検出イベント
SAMSIM_Events.addHandler(SAMSIM_Events.Type.THREAT_DETECTED, function(data)
    print(string.format("New threat: %s (%s) Priority %d",
        data.unitName, data.category, data.priority))
end)

-- セクター脅威レベル変更
SAMSIM_Events.addHandler(SAMSIM_Events.Type.SECTOR_THREAT_LEVEL_CHANGED, function(data)
    print(string.format("Sector %s threat: %d -> %d",
        data.sectorName, data.oldLevel, data.newLevel))
end)
```

### 利用可能なイベントタイプ

| イベント | 説明 |
|----------|------|
| `SAM_ACTIVATED` | SAMレーダー起動 |
| `SAM_DEACTIVATED` | SAMレーダー停止 |
| `SAM_SUPPRESSED` | SEAD抑圧 |
| `SAM_RECOVERED` | 抑圧から復帰 |
| `SAM_DESTROYED` | SAM破壊 |
| `ARM_DETECTED` | ARM検出 |
| `ARM_LAUNCHED` | ARM発射 |
| `ARM_IMPACT` | ARM着弾 |
| `THREAT_DETECTED` | 新規脅威検出 |
| `THREAT_LOST` | 脅威ロスト |
| `NETWORK_EMCON` | EMCONレベル変更 |
| `SECTOR_THREAT_LEVEL_CHANGED` | セクター脅威レベル変更 |

---

## ファイル構成

```
Dcs-samsim/
├── lua/
│   ├── mission/
│   │   ├── core/                    # コア基盤 (MIST代替)
│   │   │   ├── SAMSIM_Utils.lua     # ユーティリティ
│   │   │   ├── SAMSIM_Config.lua    # 統合設定
│   │   │   └── SAMSIM_Events.lua    # イベント管理
│   │   │
│   │   ├── iads/                    # IADS機能
│   │   │   ├── SAMSIM_IADS.lua      # ネットワーク管理
│   │   │   ├── SAMSIM_Threat.lua    # 脅威追跡
│   │   │   └── SAMSIM_Sector.lua    # セクター管理
│   │   │
│   │   ├── SA2_SAMSIM.lua           # SA-2コントローラー
│   │   ├── SA3_SAMSIM.lua           # SA-3コントローラー
│   │   ├── SA6_SAMSIM.lua           # SA-6コントローラー
│   │   ├── SA10_SAMSIM.lua          # SA-10コントローラー
│   │   ├── SA11_SAMSIM.lua          # SA-11コントローラー
│   │   ├── SA8_SAMSIM.lua           # SA-8コントローラー
│   │   ├── SA15_SAMSIM.lua          # SA-15コントローラー
│   │   ├── SA19_SAMSIM.lua          # SA-19コントローラー
│   │   ├── PATRIOT_SAMSIM.lua       # Patriotコントローラー
│   │   ├── HAWK_SAMSIM.lua          # HAWKコントローラー
│   │   ├── ROLAND_SAMSIM.lua        # Rolandコントローラー
│   │   │
│   │   ├── SAMSIM_Unified.lua       # 統合コントローラー
│   │   ├── SAMSIM_SEAD.lua          # SEAD/DEADモジュール
│   │   ├── SAMSIM_EW.lua            # 電子戦モジュール
│   │   ├── SAMSIM_Multiplayer.lua   # マルチプレイヤー
│   │   ├── SAMSIM_Training.lua      # 訓練モード
│   │   └── SAMSIM_Main.lua          # エントリーポイント
│   │
│   └── export/
│       └── SAMSIM_Export.lua        # DCS Export
│
├── server/
│   ├── samsim_server.py             # Pythonサーバー
│   └── static/
│       ├── index.html
│       ├── css/samsim.css
│       └── js/samsim.js
│
└── docs/
    └── INTEGRATION_DESIGN.md        # 統合設計書
```

---

## インストール手順

### 1. 前提条件

- DCS World 2.7.x 以降
- Python 3.10以上（サーバー用）
- モダンブラウザ (Chrome, Firefox, Edge)
- **MIST不要**

### 2. ファイル配置

```bash
# Scripts フォルダにコピー
cp -r lua/mission/* "Saved Games/DCS/Scripts/"
cp lua/export/SAMSIM_Export.lua "Saved Games/DCS/Scripts/"
```

### 3. Export.lua 編集

`Saved Games/DCS/Scripts/Export.lua` に追加:

```lua
local samsimExportPath = lfs.writedir() .. "Scripts/SAMSIM_Export.lua"
dofile(samsimExportPath)
```

### 4. サーバー起動

```bash
cd server
pip install aiohttp websockets
python samsim_server.py
```

### 5. ミッションに追加

Mission Editor → Triggers → DO SCRIPT FILE → `SAMSIM_Main.lua`

### 6. ブラウザでアクセス

```
http://localhost:8080
```

---

## トラブルシューティング

### SAMが自動検出されない

1. グループ名が正しいパターンか確認 (`SAM_` で始まるか)
2. ユニットが正しいSAMタイプか確認
3. coalitionが正しいか確認

```lua
-- デバッグモードで確認
SAMSIM.init({ debug = true })
```

### ARM検出が動作しない

1. `seadEnabled = true` が設定されているか確認
2. イベントハンドラが登録されているか確認

```lua
-- イベント確認
SAMSIM_Events.addHandler(SAMSIM_Events.Type.SHOT, function(data)
    print("Shot event: " .. tostring(data))
end)
```

### ネットワークリンクが作成されない

1. `maxLinkDistance` が適切か確認
2. ノードのpositionが取得できているか確認

```lua
-- ネットワーク状態確認
local status = SAMSIM.getStatus()
print("Links: " .. status.links)
```

---

## API リファレンス

### SAMSIM (メイン)

| 関数 | 説明 |
|------|------|
| `SAMSIM.init(options)` | 初期化 |
| `SAMSIM.initRed(options)` | RED側簡易初期化 |
| `SAMSIM.initBlue(options)` | BLUE側簡易初期化 |
| `SAMSIM.initBoth(options)` | 両陣営初期化 |
| `SAMSIM.addSAM(groupName, samType, options)` | SAM追加 |
| `SAMSIM.addEWR(groupName, options)` | EWR追加 |
| `SAMSIM.createSector(name, center, radius)` | セクター作成 |
| `SAMSIM.setEMCON(level)` | EMCON設定 |
| `SAMSIM.goDark()` | 全レーダーオフ |
| `SAMSIM.goActive()` | 全レーダーオン |
| `SAMSIM.getStatus()` | ステータス取得 |
| `SAMSIM.shutdown()` | シャットダウン |

### SAMSIM_IADS

| 関数 | 説明 |
|------|------|
| `createNetwork(name, options)` | ネットワーク作成 |
| `addSAM(network, groupName, samType, options)` | SAM追加 |
| `addEWR(network, groupName, options)` | EWR追加 |
| `autoAddByPattern(network, samPattern, ewrPattern)` | パターン自動追加 |
| `autoLinkByDistance(network, maxDistance)` | 距離自動リンク |
| `setNetworkEMCON(network, level)` | ネットワークEMCON |
| `setSiteState(node, state)` | サイト状態設定 |
| `shareThreat(network, threat, detectedBy)` | 脅威共有 |
| `activateBackup(network, suppressedNode)` | バックアップ起動 |

### SAMSIM_Threat

| 関数 | 説明 |
|------|------|
| `createTrack(unit, detectedBy)` | トラック作成 |
| `reportDetection(unit, detectedBy, network)` | 検出報告 |
| `getTracksByPriority(maxPriority)` | 優先度別取得 |
| `getNearestThreat(position)` | 最近接脅威取得 |
| `getThreatsInRange(position, range)` | 範囲内脅威取得 |
| `getStatistics()` | 統計取得 |

### SAMSIM_Sector

| 関数 | 説明 |
|------|------|
| `createCircular(name, center, radius)` | 円形セクター |
| `createFromZone(zoneName)` | ゾーンからセクター |
| `addSAM(sector, samNode, priority)` | SAM割り当て |
| `setMinimumCoverage(sector)` | 最小カバレッジ |
| `setAdaptiveCoverage(sector)` | 適応カバレッジ |
| `getThreatsInSector(sector)` | セクター内脅威 |

---

## ライセンス

MIT License

## 作者

Claude Code
