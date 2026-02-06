# DCS SAMSim + Mission Creation Assistance Scripts 統合設計書

## 1. 概要

### 1.1 統合目標
- **DCS-Mission-Creation-Assistance-Scripts** の機能を **DCS-SAMSim** に統合
- **MIST依存を完全排除** - DCS Native API + 独自実装で代替
- 統一されたアーキテクチャで両システムの強みを活かす

### 1.2 統合対象機能

| 機能カテゴリ | 元リポジトリ | 統合先 |
|-------------|-------------|--------|
| IADS Network | iads/network.lua | SAMSIM_IADS.lua (新規) |
| Sector Management | iads/sector.lua | SAMSIM_Sector.lua (新規) |
| Threat Sharing | iads/threat.lua | SAMSIM_Threat.lua (新規) |
| SEAD Suppression | core/sead.lua | SAMSIM_SEAD.lua (拡張) |
| Configuration | core/config.lua | SAMSIM_Config.lua (新規) |
| Utilities | core/utils.lua | SAMSIM_Utils.lua (新規) |

---

## 2. アーキテクチャ設計

### 2.1 モジュール構成図

```
┌─────────────────────────────────────────────────────────────────┐
│                      SAMSIM Unified Controller                   │
│                        (SAMSIM_Unified.lua)                      │
└───────────────────────────────┬─────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  SAM Systems  │     │   IADS Layer    │     │  Support Layer  │
│   (11種類)    │     │     (新規)      │     │    (既存)       │
├───────────────┤     ├─────────────────┤     ├─────────────────┤
│ SA-2, SA-3    │     │ SAMSIM_IADS     │     │ SAMSIM_EW       │
│ SA-6, SA-10   │     │ SAMSIM_Sector   │     │ SAMSIM_Missile  │
│ SA-11, SA-8   │     │ SAMSIM_Threat   │     │ SAMSIM_Terrain  │
│ SA-15, SA-19  │     │                 │     │ SAMSIM_C2       │
│ Patriot, HAWK │     │                 │     │ SAMSIM_Training │
│ Roland        │     │                 │     │ SAMSIM_SEAD     │
└───────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        └───────────────────────┼───────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Core Foundation                            │
├─────────────────────────────────────────────────────────────────┤
│  SAMSIM_Utils.lua  │  SAMSIM_Config.lua  │  SAMSIM_Events.lua   │
│  (MIST代替)        │  (統合設定)         │  (イベント管理)       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DCS World Native API                          │
│        (world, timer, trigger, coalition, Group, Unit)           │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 データフロー

```
┌──────────────┐    Detection    ┌──────────────┐    Share     ┌──────────────┐
│     EWR      │ ──────────────► │    Threat    │ ───────────► │    IADS      │
│   (早期警戒)  │                 │   Manager    │              │   Network    │
└──────────────┘                 └──────────────┘              └──────────────┘
                                        │                            │
                                        │ Track                      │ Command
                                        ▼                            ▼
┌──────────────┐    Engage       ┌──────────────┐    Cover     ┌──────────────┐
│     SAM      │ ◄────────────── │    Sector    │ ◄─────────── │   Adjacent   │
│    Site      │                 │   Manager    │              │   Sectors    │
└──────────────┘                 └──────────────┘              └──────────────┘
        │                               ▲
        │ SEAD Event                    │ Threat Level
        ▼                               │
┌──────────────┐    Suppress     ┌──────────────┐
│    SEAD      │ ──────────────► │    EMCON     │
│   Handler    │                 │   Manager    │
└──────────────┘                 └──────────────┘
```

---

## 3. MIST依存排除設計

### 3.1 MIST関数 → Native API マッピング

| MIST関数 | 代替実装 | 実装場所 |
|----------|----------|----------|
| `mist.DBs.groupsByName` | `Group.getByName()` | SAMSIM_Utils |
| `mist.DBs.unitsByName` | `Unit.getByName()` | SAMSIM_Utils |
| `mist.getGroupData` | `Group:getUnits()` + ループ | SAMSIM_Utils |
| `mist.getUnitPosition` | `Unit:getPoint()` | SAMSIM_Utils |
| `mist.utils.tableContains` | カスタム実装 | SAMSIM_Utils |
| `mist.scheduleFunction` | `timer.scheduleFunction` | Direct |
| `mist.removeFunction` | `timer.removeFunction` | Direct |
| `mist.addEventHandler` | `world.addEventHandler` | SAMSIM_Events |
| `mist.getDistance` | カスタム実装 | SAMSIM_Utils |
| `mist.getHeading` | カスタム実装 | SAMSIM_Utils |
| `mist.vec.add/sub/mag` | カスタムベクトル演算 | SAMSIM_Utils |

### 3.2 SAMSIM_Utils.lua 設計

```lua
SAMSIM_Utils = {}

-- ============================================
-- Table Utilities (MIST.utils replacement)
-- ============================================
function SAMSIM_Utils.tableContainsValue(tbl, value)
function SAMSIM_Utils.tableContainsKey(tbl, key)
function SAMSIM_Utils.shallowCopy(tbl)
function SAMSIM_Utils.deepCopy(tbl)
function SAMSIM_Utils.mergeTables(base, override)
function SAMSIM_Utils.tableLength(tbl)

-- ============================================
-- Vector Operations (MIST.vec replacement)
-- ============================================
function SAMSIM_Utils.vec3Add(a, b)
function SAMSIM_Utils.vec3Sub(a, b)
function SAMSIM_Utils.vec3Mult(v, scalar)
function SAMSIM_Utils.vec3Mag(v)
function SAMSIM_Utils.vec3Normalize(v)
function SAMSIM_Utils.vec3Dot(a, b)
function SAMSIM_Utils.vec3Cross(a, b)

-- ============================================
-- Distance & Geometry
-- ============================================
function SAMSIM_Utils.getDistance3D(pos1, pos2)
function SAMSIM_Utils.getDistance2D(pos1, pos2)
function SAMSIM_Utils.getHeading(from, to)
function SAMSIM_Utils.getBearing(from, to)
function SAMSIM_Utils.getAltitude(pos)
function SAMSIM_Utils.pointInPolygon(point, polygon)
function SAMSIM_Utils.pointInCircle(point, center, radius)

-- ============================================
-- Unit/Group Database (MIST.DBs replacement)
-- ============================================
function SAMSIM_Utils.getGroupByName(name)
function SAMSIM_Utils.getUnitByName(name)
function SAMSIM_Utils.getGroupUnits(groupName)
function SAMSIM_Utils.getUnitPosition(unitName)
function SAMSIM_Utils.getGroupPosition(groupName)
function SAMSIM_Utils.getGroupsByPattern(pattern)
function SAMSIM_Utils.getUnitsByPattern(pattern)

-- ============================================
-- Alarm State Control
-- ============================================
SAMSIM_Utils.ALARM_STATE = {
    AUTO = 0,
    GREEN = 1,
    RED = 2,
}
function SAMSIM_Utils.setUnitAlarmState(unit, state)
function SAMSIM_Utils.setGroupAlarmState(group, state)

-- ============================================
-- Scheduler (timer wrapper)
-- ============================================
function SAMSIM_Utils.schedule(func, delay, ...)
function SAMSIM_Utils.scheduleRepeat(func, interval, ...)
function SAMSIM_Utils.cancel(id)
function SAMSIM_Utils.getTime()

-- ============================================
-- Debug & Logging
-- ============================================
function SAMSIM_Utils.debug(msg, ...)
function SAMSIM_Utils.info(msg, ...)
function SAMSIM_Utils.warn(msg, ...)
function SAMSIM_Utils.error(msg, ...)
```

---

## 4. 新規モジュール設計

### 4.1 SAMSIM_IADS.lua - 統合防空システム

```lua
SAMSIM_IADS = {}

-- ============================================
-- ノードタイプ
-- ============================================
SAMSIM_IADS.NodeType = {
    EWR = "EWR",           -- 早期警戒レーダー
    SAM = "SAM",           -- SAMサイト
    COMMAND = "COMMAND",   -- 指揮所
    COMMS = "COMMS",       -- 通信中継
}

-- ============================================
-- SAM運用状態
-- ============================================
SAMSIM_IADS.SamState = {
    DARK = "DARK",           -- レーダー停止
    ACTIVE = "ACTIVE",       -- 捜索中
    TRACKING = "TRACKING",   -- 追尾中
    ENGAGING = "ENGAGING",   -- 交戦中
    SUPPRESSED = "SUPPRESSED", -- SEAD抑圧
    DAMAGED = "DAMAGED",     -- 損傷
}

-- ============================================
-- ネットワーク構造
-- ============================================
SAMSIM_IADS.Network = {
    name = "",
    nodes = {},        -- 全ノード
    ewrs = {},         -- EWRノード
    sams = {},         -- SAMノード
    links = {},        -- ノード間リンク
    sectors = {},      -- 防空セクター
}

-- ============================================
-- 主要機能
-- ============================================

-- ネットワーク作成
function SAMSIM_IADS.createNetwork(name, options)

-- ノード登録
function SAMSIM_IADS.addEWR(network, groupName, options)
function SAMSIM_IADS.addSAM(network, groupName, samType, options)
function SAMSIM_IADS.addCommandPost(network, groupName, options)

-- 自動検出（命名パターン）
function SAMSIM_IADS.autoAddByPattern(network, samPattern, ewrPattern)

-- リンク管理
function SAMSIM_IADS.linkNodes(network, node1, node2)
function SAMSIM_IADS.autoLinkByDistance(network, maxDistance)
function SAMSIM_IADS.unlinkNodes(network, node1, node2)

-- EMCON制御
function SAMSIM_IADS.setNetworkEMCON(network, level)
function SAMSIM_IADS.setSiteEMCON(site, level)
function SAMSIM_IADS.goToDark(network)  -- 全レーダー停止
function SAMSIM_IADS.goToActive(network)

-- 状態管理
function SAMSIM_IADS.getSiteState(site)
function SAMSIM_IADS.setSiteState(site, state)
function SAMSIM_IADS.getNetworkStatus(network)

-- バックアップカバレッジ
function SAMSIM_IADS.activateBackup(network, suppressedSite)
function SAMSIM_IADS.deactivateBackup(network, reactivatedSite)

-- 脅威情報配信
function SAMSIM_IADS.shareThreat(network, threat, detectedBy)
function SAMSIM_IADS.getSharedThreats(site)
```

### 4.2 SAMSIM_Sector.lua - セクター管理

```lua
SAMSIM_Sector = {}

-- ============================================
-- セクタータイプ
-- ============================================
SAMSIM_Sector.Type = {
    POINT = "POINT",       -- 円形（中心点+半径）
    POLYGON = "POLYGON",   -- 多角形
    ZONE = "ZONE",         -- DCSトリガーゾーン
}

-- ============================================
-- 脅威レベル
-- ============================================
SAMSIM_Sector.ThreatLevel = {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4,
}

-- ============================================
-- セクター構造
-- ============================================
SAMSIM_Sector.Sector = {
    id = "",
    name = "",
    type = "",
    bounds = {},           -- 境界定義
    sams = {},             -- 所属SAM
    ewrs = {},             -- 所属EWR
    threatLevel = 0,
    activeCount = 0,
    threats = {},          -- セクター内脅威
}

-- ============================================
-- 主要機能
-- ============================================

-- セクター作成
function SAMSIM_Sector.createCircular(name, center, radius)
function SAMSIM_Sector.createPolygon(name, vertices)
function SAMSIM_Sector.createFromZone(zoneName)

-- SAM管理
function SAMSIM_Sector.addSAM(sector, samSite, priority)
function SAMSIM_Sector.removeSAM(sector, samSite)
function SAMSIM_Sector.getSAMsByPriority(sector)

-- 脅威管理
function SAMSIM_Sector.updateThreatLevel(sector)
function SAMSIM_Sector.getThreatLevel(sector)
function SAMSIM_Sector.getThreatsInSector(sector)

-- 位置判定
function SAMSIM_Sector.isPointInSector(sector, point)
function SAMSIM_Sector.getSectorForPoint(sectors, point)

-- アクティベーション制御
function SAMSIM_Sector.setMinimumCoverage(sector)   -- Priority 1のみ
function SAMSIM_Sector.setPartialCoverage(sector)   -- Priority 1-2
function SAMSIM_Sector.setFullCoverage(sector)      -- 全SAM
function SAMSIM_Sector.adaptiveCoverage(sector)     -- 脅威レベル連動

-- ステータス
function SAMSIM_Sector.getStatus(sector)
function SAMSIM_Sector.getAllSectorsStatus()
```

### 4.3 SAMSIM_Threat.lua - 脅威追跡・共有

```lua
SAMSIM_Threat = {}

-- ============================================
-- 目標カテゴリ
-- ============================================
SAMSIM_Threat.Category = {
    UNKNOWN = "UNKNOWN",
    FIGHTER = "FIGHTER",
    ATTACK = "ATTACK",
    BOMBER = "BOMBER",
    SEAD = "SEAD",
    HELICOPTER = "HELICOPTER",
    UAV = "UAV",
    CRUISE_MISSILE = "CRUISE_MISSILE",
    ARM = "ARM",
}

-- ============================================
-- 脅威優先度
-- ============================================
SAMSIM_Threat.Priority = {
    IMMEDIATE = 1,    -- ARM/SEAD機
    HIGH = 2,         -- 攻撃機
    MEDIUM = 3,       -- 戦闘機
    LOW = 4,          -- その他
    MINIMAL = 5,      -- 非脅威
}

-- ============================================
-- トラック構造
-- ============================================
SAMSIM_Threat.Track = {
    id = "",
    unitName = "",
    category = "",
    priority = 0,
    position = {},
    velocity = {},
    heading = 0,
    altitude = 0,
    speed = 0,
    detectedBy = {},    -- 検出したセンサー
    engagedBy = {},     -- 交戦中のSAM
    firstDetected = 0,
    lastUpdate = 0,
    lost = false,
}

-- ============================================
-- 主要機能
-- ============================================

-- トラック管理
function SAMSIM_Threat.createTrack(unit, detectedBy)
function SAMSIM_Threat.updateTrack(trackId)
function SAMSIM_Threat.removeTrack(trackId)
function SAMSIM_Threat.cleanupLostTracks()

-- 目標分類
function SAMSIM_Threat.categorizeTarget(unit)
function SAMSIM_Threat.isSEADCapable(typeName)
function SAMSIM_Threat.isARMCarrier(typeName)
function SAMSIM_Threat.calculatePriority(track)

-- 検出レポート
function SAMSIM_Threat.reportDetection(unit, detectedBy, network)
function SAMSIM_Threat.reportLost(trackId, sensor)
function SAMSIM_Threat.reportEngagement(trackId, samSite)

-- クエリ
function SAMSIM_Threat.getTrackByUnit(unitName)
function SAMSIM_Threat.getTracksByCategory(category)
function SAMSIM_Threat.getTracksByPriority(minPriority)
function SAMSIM_Threat.getNearestThreat(position)
function SAMSIM_Threat.getThreatsInRange(position, range)
function SAMSIM_Threat.getHighestPriorityThreats(count)

-- 交戦管理
function SAMSIM_Threat.markEngaged(trackId, engagedBy)
function SAMSIM_Threat.markDisengaged(trackId, samSite)
function SAMSIM_Threat.getEngagingUnits(trackId)
function SAMSIM_Threat.isBeingEngaged(trackId)
```

### 4.4 SAMSIM_SEAD.lua 拡張

既存のSAMSIM_SEAD.luaに以下を追加:

```lua
-- ============================================
-- IADS統合機能（追加）
-- ============================================

-- ARM発射検出→IADS通知
function SAMSIM_SEAD.onARMLaunch(weapon, target, network)
    -- ネットワーク全体に脅威共有
    SAMSIM_IADS.shareThreat(network, {
        type = "ARM",
        weapon = weapon,
        target = target,
        timeToImpact = calculateTTI(weapon, target),
    }, target)

    -- 自動EMCON推奨
    if self.Config.emcon.autoRecommend then
        SAMSIM_SEAD.recommendEMCON(target, "SHUTDOWN")
    end
end

-- グループ抑圧（既存機能拡張）
function SAMSIM_SEAD.suppressGroup(groupName, duration, network)
    -- 既存の抑圧ロジック
    local group = SAMSIM_Utils.getGroupByName(groupName)
    SAMSIM_Utils.setGroupAlarmState(group, SAMSIM_Utils.ALARM_STATE.GREEN)

    -- IADS通知（新規）
    if network then
        SAMSIM_IADS.setSiteState(groupName, SAMSIM_IADS.SamState.SUPPRESSED)
        SAMSIM_IADS.activateBackup(network, groupName)
    end

    -- 復帰スケジュール
    SAMSIM_Utils.schedule(function()
        SAMSIM_SEAD.reactivateGroup(groupName, network)
    end, duration)
end

-- グループ復帰（IADS連携）
function SAMSIM_SEAD.reactivateGroup(groupName, network)
    SAMSIM_Utils.setGroupAlarmState(group, SAMSIM_Utils.ALARM_STATE.RED)

    if network then
        SAMSIM_IADS.setSiteState(groupName, SAMSIM_IADS.SamState.ACTIVE)
        SAMSIM_IADS.deactivateBackup(network, groupName)
    end
end
```

---

## 5. イベント統合設計

### 5.1 SAMSIM_Events.lua

```lua
SAMSIM_Events = {}

-- ============================================
-- イベントタイプ
-- ============================================
SAMSIM_Events.Type = {
    -- DCS Native Events
    SHOT = world.event.S_EVENT_SHOT,
    HIT = world.event.S_EVENT_HIT,
    DEAD = world.event.S_EVENT_DEAD,

    -- Custom SAMSIM Events
    SAM_ACTIVATED = "SAM_ACTIVATED",
    SAM_DEACTIVATED = "SAM_DEACTIVATED",
    SAM_TRACKING = "SAM_TRACKING",
    SAM_ENGAGED = "SAM_ENGAGED",
    SAM_SUPPRESSED = "SAM_SUPPRESSED",
    MISSILE_LAUNCHED = "MISSILE_LAUNCHED",
    MISSILE_IMPACT = "MISSILE_IMPACT",
    ARM_DETECTED = "ARM_DETECTED",
    THREAT_DETECTED = "THREAT_DETECTED",
    THREAT_LOST = "THREAT_LOST",
    NETWORK_EMCON = "NETWORK_EMCON",
}

-- ============================================
-- イベントハンドラー登録
-- ============================================
SAMSIM_Events.handlers = {}

function SAMSIM_Events.addHandler(eventType, handler)
function SAMSIM_Events.removeHandler(eventType, handler)
function SAMSIM_Events.fire(eventType, data)

-- ============================================
-- DCSイベント統合
-- ============================================
function SAMSIM_Events.init()
    world.addEventHandler({
        onEvent = function(self, event)
            SAMSIM_Events.processEvent(event)
        end
    })
end

function SAMSIM_Events.processEvent(event)
    -- S_EVENT_SHOT: ARM/ミサイル発射検出
    -- S_EVENT_HIT: 被弾処理
    -- S_EVENT_DEAD: ユニット破壊処理
end
```

---

## 6. 設定統合設計

### 6.1 SAMSIM_Config.lua

```lua
SAMSIM_Config = {}

-- ============================================
-- グローバル設定
-- ============================================
SAMSIM_Config.Global = {
    debug = false,
    updateInterval = 1.0,      -- 秒
    threatTrackTimeout = 30,   -- 秒
    networkSyncInterval = 2.0, -- 秒
}

-- ============================================
-- SAMシステム定義（統合）
-- ============================================
SAMSIM_Config.SAMTypes = {
    -- 東側
    SA2 = {
        name = "SA-2 Guideline",
        searchRadar = "p-19 s-125 sr",
        trackRadar = "SNR_75V",
        suppressionRate = 0.7,
        minOffDelay = 30,
        maxOffDelay = 90,
        minOnDelay = 60,
        maxOnDelay = 180,
        trackRange = 75,      -- km
        engageRange = 40,     -- km
    },
    SA3 = { ... },
    SA6 = { ... },
    SA10 = { ... },
    SA11 = { ... },
    SA8 = { ... },
    SA15 = { ... },
    SA19 = { ... },

    -- 西側
    PATRIOT = {
        name = "MIM-104 Patriot",
        searchRadar = "Patriot str",
        trackRadar = "Patriot str",  -- 捜索追尾一体型
        suppressionRate = 0.5,       -- 低脆弱性
        minOffDelay = 15,
        maxOffDelay = 45,
        minOnDelay = 30,
        maxOnDelay = 120,
        trackRange = 170,
        engageRange = 100,
        phasedArray = true,
    },
    HAWK = { ... },
    ROLAND = { ... },
}

-- ============================================
-- EWRタイプ定義
-- ============================================
SAMSIM_Config.EWRTypes = {
    ["1L13 EWR"] = { range = 300, altitude = 30000 },
    ["55G6 EWR"] = { range = 400, altitude = 40000 },
    ["EWR P-37"] = { range = 350, altitude = 35000 },
}

-- ============================================
-- ARM定義
-- ============================================
SAMSIM_Config.ARMTypes = {
    ["AGM_88"] = { name = "AGM-88 HARM", range = 150 },
    ["X_58"] = { name = "Kh-58U", range = 120 },
    ["X_25MPU"] = { name = "Kh-25MPU", range = 40 },
    ["LD-10"] = { name = "LD-10", range = 80 },
}

-- ============================================
-- SEAD機タイプ
-- ============================================
SAMSIM_Config.SEADTypes = {
    "F-16CM", "F/A-18C", "EA-18G", "F-4G",
    "Tornado IDS", "Su-24M", "MiG-27",
}
```

---

## 7. ファイル構成（統合後）

```
lua/
├── mission/
│   ├── core/                          # 新規: コア基盤
│   │   ├── SAMSIM_Utils.lua           # MIST代替ユーティリティ
│   │   ├── SAMSIM_Config.lua          # 統合設定
│   │   └── SAMSIM_Events.lua          # イベント管理
│   │
│   ├── iads/                          # 新規: IADS機能
│   │   ├── SAMSIM_IADS.lua            # IADSネットワーク
│   │   ├── SAMSIM_Sector.lua          # セクター管理
│   │   └── SAMSIM_Threat.lua          # 脅威追跡・共有
│   │
│   ├── systems/                       # 既存: SAMシステム（移動）
│   │   ├── SA2_SAMSIM.lua
│   │   ├── SA3_SAMSIM.lua
│   │   ├── SA6_SAMSIM.lua
│   │   ├── SA10_SAMSIM.lua
│   │   ├── SA11_SAMSIM.lua
│   │   ├── SA8_SAMSIM.lua
│   │   ├── SA15_SAMSIM.lua
│   │   ├── SA19_SAMSIM.lua
│   │   ├── PATRIOT_SAMSIM.lua
│   │   ├── HAWK_SAMSIM.lua
│   │   └── ROLAND_SAMSIM.lua
│   │
│   ├── support/                       # 既存: サポートモジュール（移動）
│   │   ├── SAMSIM_EW.lua
│   │   ├── SAMSIM_Missile.lua
│   │   ├── SAMSIM_Terrain.lua
│   │   ├── SAMSIM_C2.lua
│   │   ├── SAMSIM_SEAD.lua            # 拡張
│   │   ├── SAMSIM_Training.lua
│   │   └── SAMSIM_Multiplayer.lua
│   │
│   ├── SAMSIM_Unified.lua             # 既存: 統合コントローラー（拡張）
│   └── SAMSIM_Main.lua                # 新規: エントリーポイント
│
└── export/
    └── SAMSIM_Export.lua
```

---

## 8. 使用例

### 8.1 基本セットアップ（MIST不要）

```lua
-- ミッションスクリプトでの読み込み
dofile("SAMSIM_Main.lua")

-- 初期化
SAMSIM.init({
    debug = true,
    autoDetect = true,
    samPattern = "^SAM_",
    ewrPattern = "^EWR_",
})
```

### 8.2 IADSネットワーク構築

```lua
-- ネットワーク作成
local network = SAMSIM_IADS.createNetwork("RedForce_IADS", {
    coalition = coalition.side.RED,
})

-- 自動検出で追加
SAMSIM_IADS.autoAddByPattern(network, "^SAM_", "^EWR_")

-- または手動で追加
SAMSIM_IADS.addEWR(network, "EWR_North", { range = 400 })
SAMSIM_IADS.addSAM(network, "SAM_SA10_Alpha", "SA10", { priority = 1 })
SAMSIM_IADS.addSAM(network, "SAM_SA6_Bravo", "SA6", { priority = 2 })

-- 距離ベースで自動リンク
SAMSIM_IADS.autoLinkByDistance(network, 150000)  -- 150km以内

-- SEAD初期化（IADS連携）
SAMSIM_SEAD.init({
    network = network,
    autoEMCON = true,
})
```

### 8.3 セクター管理

```lua
-- セクター作成
local sector1 = SAMSIM_Sector.createCircular("North_Sector", {x=10000, y=0, z=50000}, 80000)
local sector2 = SAMSIM_Sector.createFromZone("South_Defense_Zone")

-- SAM割り当て
SAMSIM_Sector.addSAM(sector1, "SAM_SA10_Alpha", 1)  -- 優先度1
SAMSIM_Sector.addSAM(sector1, "SAM_SA6_Bravo", 2)   -- 優先度2

-- 適応カバレッジ有効化（脅威レベル連動）
SAMSIM_Sector.adaptiveCoverage(sector1)
```

---

## 9. 実装フェーズ

### Phase A: コア基盤 (SAMSIM_Utils, SAMSIM_Config, SAMSIM_Events)
- MIST代替関数実装
- 統合設定構造
- イベントシステム

### Phase B: IADS基本機能 (SAMSIM_IADS)
- ネットワーク構造
- ノード登録・リンク
- EMCON制御

### Phase C: 脅威管理 (SAMSIM_Threat)
- トラック作成・更新
- 目標分類
- 優先度計算

### Phase D: セクター管理 (SAMSIM_Sector)
- セクター定義
- カバレッジ制御
- 脅威レベル連動

### Phase E: SEAD統合
- SAMSIM_SEAD拡張
- IADS連携
- 抑圧→バックアップ自動化

### Phase F: 既存システム統合
- SAMコントローラー接続
- Web UI更新
- テスト・検証

---

## 10. 互換性・移行

### 10.1 既存SAMSimからの移行
- 既存API維持（後方互換）
- 新機能はオプトイン
- 段階的移行パス提供

### 10.2 DCS-Mission-Creation-Assistance-Scriptsからの移行
- 同等機能のマッピング表提供
- 設定ファイル変換ツール
- 使用例ドキュメント

---

## 11. 制限事項・注意点

1. **MIST非使用**: 一部の高度なMIST機能は再実装が必要
2. **パフォーマンス**: 大規模ネットワーク(50+ SAM)では更新間隔調整推奨
3. **DCSバージョン**: DCS 2.7.x以降を推奨
4. **マルチプレイヤー**: 同期は既存SAMSIM_Multiplayer経由

---

*設計書 v1.0 - 2026-02-06*
