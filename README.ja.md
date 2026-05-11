# nim_gpiod

`nim_gpiod` は Nim 用の小さな Linux GPIO ライブラリです。

GPIO入力値の読み取りと edge event の待機を、できるだけ単純なAPIで扱うことを目的にしています。既存の `nim_gpiod` 利用コードとの互換性はできるだけ残しつつ、実装上は `libgpiod` への依存をなくしています。

このブランチでは、小さな同梱C shimを通して Linux GPIO character device v2 ABI を直接使用します。

## このライブラリの目的

`libgpiod` v1 と v2 は C API が大きく異なります。そのため、ディストリビューションごとに入っている `libgpiod` の版が違うと、同じ Nim アプリケーションをビルドする上で問題になりました。

`nim_gpiod` は kernel の GPIO character device v2 API を直接使うことで、この差を避けます。

対象kernelが GPIO chardev v2 を提供していれば、配布環境に `libgpiod` v1 があるか、v2 があるか、あるいは `libgpiod` がまったく入っていないかをアプリケーション側で気にしなくて済みます。

## 特徴

- line name からGPIO lineを開く
- chip path と offset からGPIO lineを開く
- GPIO入力値の読み取り
- rising / falling / both edge event の待機
- active-low 対応
- event metadata 対応
  - nanoseconds単位のtimestamp
  - global sequence number
  - line sequence number
- 旧アプリケーション互換用の `Event.value` フィールド
- debounce付き旧互換 `waitEvent(edge, debounceMs)` API
- 明示的なエラー処理用の Result-based API
- 旧コード向けの exception-based compatibility API
- 実行時の `libgpiod` 依存なし
- 通常ビルドでは Futhark/libclang 不要

## 必要条件

- GPIO character device v2 を持つ Linux kernel
- 使用可能な `/dev/gpiochipN`
- Nimビルド時に使用できるCコンパイラ
- Nim
- Nim package `results`

現時点では、Linux 5.10.y 以降の組み込みLinux環境を主な対象にしています。

## プロジェクト構成

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

C shim は Nim の `{.compile.}` pragma でアプリケーションに組み込まれます。生成済み風のNim bindingもリポジトリに含めているため、通常利用者は Futhark や libclang を用意する必要はありません。

## 基本的な使い方

    import nim_gpiod

    let gpio = newGpio("SIM2_CD", "my_app")
    echo gpio.getValue()
    gpio.close()

`newGpio()` は失敗時に `OSError` を送出します。明示的にエラーを扱う場合は `openGpio()` と `getValueRes()` を使います。

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

## edge event を待つ

検出した edge だけが必要な場合は `waitEdge()` を使います。

    import std/asyncdispatch
    import nim_gpiod

    proc main() {.async.} =
      let gpio = newGpio("DI0", "my_app")
      defer:
        gpio.close()

      let edge = await gpio.waitEdge(Edge.Both)
      echo edge

    waitFor main()

timestamp や sequence number が必要な場合は `waitEventInfo()` または `waitEventRes()` を使います。

    import std/asyncdispatch
    import nim_gpiod

    proc main() {.async.} =
      let gpio = newGpio("DI0", "my_app")
      defer:
        gpio.close()

      let ev = await gpio.waitEventInfo(Edge.Both)
      echo ev.edge
      echo ev.value
      echo ev.timestampNs
      echo ev.seqno
      echo ev.lineSeqno

    waitFor main()

`waitEventInfo()` は失敗時に `OSError` を送出します。`waitEventRes()` は代わりに `GE[Event]` を返します。

## 旧API互換

Nimでは `wait_event` と `waitEvent` のような識別子は同じ名前として扱われます。そのため、旧API互換の関数は `waitEvent()` として提供します。

次のような旧コードはそのまま使えます。

    let event = await gpio.wait_event(Edge.Both, 100)
    echo event.edge
    echo event.value

これは Nim 上では次の呼び出しとして解決されます。

    let event = await gpio.waitEvent(Edge.Both, 100)

第2引数は timeout ではなく debounce interval milliseconds です。

互換APIの動作は次の通りです。

1. 最初の edge event を待つ
2. debounce interval の間、追加の edge event を待つ
3. 追加edgeが来た場合は、最後のeventを保持して debounce 待ちを繰り返す
4. debounce interval 中に追加edgeが来なくなったら確定する
5. 最後に現在のGPIO値を読み取り、`Event.value` に格納する

これにより、旧 `wait_event()` と同じように、`Event.value` は debounce 後に安定した値を表します。

新しいコードでは次の使い分けを推奨します。

- edge だけ必要なら `waitEdge(edge, timeoutMs)`
- timestamp や sequence number 付きの event が必要なら `waitEventInfo(edge, timeoutMs)`
- 旧APIと同じ debounce 動作が必要なら `waitEvent(edge, debounceMs)`

## active-low

論理的に active-low の入力信号では、lineを開くときに `activeLow = true` を指定します。

    let gpio = newGpio("DI0", "my_app", activeLow = true)

Nim APIとしては、生の電気レベルではなく論理値を返すことを意図しています。

## polling test

I2C GPIO expander のように、入力値は読めるが割り込み線が配線されておらず edge event を使えないGPIO providerがあります。

そのようなlineでは polling test を使います。

    nim c -d:release --cpu:arm64 tests/test_poll_watch.nim
    ./tests/test_poll_watch SIM2_CD 100

出力例:

    line       : SIM2_CD
    intervalMs : 100
    activeLow  : false
    2026-05-08 19:27:54.272 value=0 initial
    2026-05-08 19:28:24.513 value=1 changed from 0
    2026-05-08 19:28:25.819 value=0 changed from 1

## edge event test

edge event をサポートするGPIO lineでは次のテストを使います。

    nim c -d:release --cpu:arm64 tests/test_event_watch.nim
    ./tests/test_event_watch DI0 both

line自体は読めるのに edge request が `No such device or address` で失敗する場合、そのGPIO providerが対象lineの割り込みをサポートしていないか、ボード設定上で割り込み線が正しく記述されていない可能性があります。

## Public API overview

### Types

    type
      Edge {.pure.} = enum
        Falling
        Rising
        Both

      EventEdge {.pure.} = enum
        Falling
        Rising

      Event = object
        edge: Edge
        value: int
        timestampNs: uint64
        seqno: uint32
        lineSeqno: uint32

`Event.value` は旧アプリケーションとの互換性のために残しています。raw event APIでは edge 方向から生成されます。旧互換の `waitEvent(edge, debounceMs)` APIでは、debounce 後に実際に読み取ったGPIO値で上書きされます。

### Open

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

### Compatibility constructors

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

### Read

    proc getValueRes(self: AsyncGpio): GE[int]
    proc getValue(self: AsyncGpio): int

### Edge events

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

    proc waitEdge(
      self: AsyncGpio,
      edge: Edge,
      timeoutMs = -1
    ): Future[Edge]

    proc waitEvent(
      self: AsyncGpio,
      edge: Edge,
      debounceMs: int
    ): Future[Event]

### Close

    proc close(self: AsyncGpio)
    proc isOpen(self: AsyncGpio): bool

## Notes

このライブラリは、産業機器でよく使うデジタル入力と単純な edge monitoring に意図的に絞っています。

現時点では、pull-up/down bias、drive mode、open-drain、open-source、multi-line request API は公開していません。想定用途では、これらの設定は多くの場合ボードレベルのハードウェア設計側で決まるためです。

## License

MIT
