# nim_gpiod

`nim_gpiod` は、Nim 向けの小さな Linux GPIO ライブラリです。

GPIO 入力の読み取りと、エッジイベント待ちを扱うための簡単な API を提供します。
公開 API は従来の `nim_gpiod` に近い形を維持しつつ、内部実装は `libgpiod`
に依存しない構成へ変更しています。

この版では、小さな C shim を同梱し、Linux GPIO character device v2 ABI を
直接使用します。

## 目的

`libgpiod` は v1 と v2 で C API が大きく変わっています。そのため、同じ Nim
アプリケーションを、`libgpiod` v1 を採用しているディストリビューションと
v2 を採用しているディストリビューションの両方で扱うと、実装やビルド条件が
複雑になります。

`nim_gpiod` は、その差分を避けるため、kernel の GPIO character device v2 API
を直接使います。

対象 kernel が GPIO chardev v2 を提供していれば、実行環境にある `libgpiod`
が v1 か v2 か、あるいは `libgpiod` が入っていないかを気にせず使えます。

## 機能

- GPIO line name によるオープン
- GPIO chip path と offset によるオープン
- 入力値の読み取り
- rising / falling / both edge のイベント待ち
- active-low 指定
- イベントメタデータ:
  - nanosecond 単位の timestamp
  - global sequence number
  - line sequence number
- `Result` ベースの明示的なエラー処理
- 従来互換向けの例外 API
- `libgpiod` への runtime 依存なし
- 通常ビルド時に Futhark / libclang 不要

## 必要条件

- GPIO character device v2 を持つ Linux kernel
- 利用可能な `/dev/gpiochipN`
- Nim ビルド時に C compiler が使えること
- Nim
- Nim package の `results`

主な想定対象は、Linux 5.10.y 以降の組み込み Linux 環境です。

## ディレクトリ構成

```text
src/
  nim_gpiod.nim
  nim_gpiod/
    async_gpio.nim
    errors.nim
    types.nim
    bindings/
      c_api.nim
      generated/
        ngpio.nim
    shim/
      ngpio.h
      ngpio.c
tests/
  test_poll_watch.nim
  test_event_watch.nim
```

C shim は Nim の `{.compile.}` pragma により、Nim アプリケーションと一緒に
コンパイルされます。

Nim 側の binding は生成済みファイルとして repository に含める方針なので、
通常利用時に Futhark や libclang は不要です。

## 基本的な使い方

```nim
import nim_gpiod

let gpio = newGpio("SIM2_CD", "my_app")
echo gpio.getValue()
gpio.close()
```

`newGpio()` は失敗時に `OSError` を送出します。明示的にエラーを扱う場合は
`openGpio()` と `getValueRes()` を使います。

```nim
import nim_gpiod

let gpioRes = openGpio("SIM2_CD", "my_app")
if gpioRes.isErr:
  echo gpioRes.error
  quit 1

let gpio = gpioRes.value
defer:
  gpio.close()

let valueRes = gpio.getValueRes()
if valueRes.isErr:
  echo valueRes.error
  quit 1

echo valueRes.value
```

## エッジイベント待ち

```nim
import std/asyncdispatch

import nim_gpiod

proc main() {.async.} =
  let gpio = newGpio("DI0", "my_app")
  defer:
    gpio.close()

  let edge = await gpio.waitEvent(Edge.Both)
  echo edge

waitFor main()
```

`waitEvent()` は従来互換を意識して、検出した edge だけを返します。

timestamp や sequence number が必要な場合は、`waitEventInfo()` または
`waitEventRes()` を使います。

```nim
let ev = await gpio.waitEventInfo(Edge.Both)
echo ev.edge
echo ev.timestampNs
echo ev.seqno
echo ev.lineSeqno
```

## active-low

論理的に active-low の入力信号では、open 時に `activeLow = true` を指定します。

```nim
let gpio = newGpio("DI0", "my_app", activeLow = true)
```

Nim 側の API では、できるだけ生の電気レベルではなく、論理値として扱えることを
意図しています。

## ポーリングテスト

I2C GPIO expander などでは、入力値は読めるが、エッジイベント用の interrupt が
使えない場合があります。

そのような line には、ポーリングテストを使います。

```sh
nim c -d:release --cpu:arm64 tests/test_poll_watch.nim
./tests/test_poll_watch SIM2_CD 100
```

出力例:

```text
line       : SIM2_CD
intervalMs : 100
activeLow  : false
2026-05-08 19:27:54.272 value=0 initial
2026-05-08 19:28:24.513 value=1 changed from 0
2026-05-08 19:28:25.819 value=0 changed from 1
```

## エッジイベントテスト

エッジイベントに対応している GPIO line では、次のように確認できます。

```sh
nim c -d:release --cpu:arm64 tests/test_event_watch.nim
./tests/test_event_watch DI0 both
```

入力値は読めるのに edge request が `No such device or address` で失敗する場合、
その GPIO provider が対象 line の interrupt に対応していないか、board 側の
Device Tree 等で interrupt が定義されていない可能性があります。

## 公開 API 概要

### 型

```nim
type
  Edge {.pure.} = enum
    Falling
    Rising
    Both

  EventEdge {.pure.} = enum
    Falling
    Rising

  Event = object
    edge: EventEdge
    timestampNs: uint64
    seqno: uint32
    lineSeqno: uint32
```

### open

```nim
proc openGpio(
  lineName: string,
  consumer = "nim_gpiod",
  activeLow = false
): GE[AsyncGpio]

proc openGpioByChipOffset(
  chipPath: string,
  offset: uint,
  consumer = "nim_gpiod",
  activeLow = false
): GE[AsyncGpio]
```

### 互換コンストラクタ

```nim
proc newGpio(
  lineName: string,
  consumer = "nim_gpiod",
  activeLow = false
): AsyncGpio

proc newGpioByChipOffset(
  chipPath: string,
  offset: uint,
  consumer = "nim_gpiod",
  activeLow = false
): AsyncGpio
```

### 値読み取り

```nim
proc getValueRes(self: AsyncGpio): GE[int]
proc getValue(self: AsyncGpio): int
```

### エッジイベント

```nim
proc waitEventRes(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[GE[Event]]

proc waitEventInfo(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[Event]

proc waitEvent(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[Edge]
```

### close

```nim
proc close(self: AsyncGpio)
proc isOpen(self: AsyncGpio): bool
```

## 補足

このライブラリは、産業用機器でよくあるデジタル入力と、単純な edge 監視を主な
対象にしています。

現時点では、pull-up/down bias、drive mode、open-drain、open-source、
multi-line request などは公開 API として扱っていません。これらは想定用途では
基板側のハードウェア設計で決めるもの、という考え方です。

## License

MIT
