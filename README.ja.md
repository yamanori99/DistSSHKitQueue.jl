# DistSSHQueue.jl

[English](README.md) · [日本語](README.ja.md)

[![Test](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHQueue.jl)
[![Aqua](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/aqua.yml?branch=main&label=Aqua)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/aqua.yml)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/jetls.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/ssh-e2e.yml)

[![E2E weekly](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/ssh-e2e-weekly.yml?branch=main&label=E2E%20weekly)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/ssh-e2e-weekly.yml)
[![CI weekly](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/ci-weekly.yml?branch=main&label=CI%20weekly)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/ci-weekly.yml)

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHQueue.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://yamanori99.github.io/DistSSHQueue.jl/dev/requirements/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

DistSSHQueue は、何人かで同じマシンを使い、ジョブを順番に走らせるものである。
ジョブの投入、状態の確認、取り消しができる。
実行は [DistSSHKit](https://github.com/yamanori99/DistSSHKit.jl) が担う。
対応は **macOS、Linux、WSL2 Ubuntu** (ネイティブ Windows は対象外)。

小さな研究室や個人でも、常時起動のマシンを 1 台置き、SSH接続したマシンとまとめて小さな計算ノードとして使うことが出来る。
General にはまだ無い。Julia **1.12+**、DistSSHKit **0.4.1+**。

## インストール

Julia REPL で `]` を押して Pkg モードに入り、次を実行する。

```julia
pkg> add https://github.com/yamanori99/DistSSHQueue.jl
```

同じことを `Pkg` API で書くと次のとおり。

```julia
julia> import Pkg; Pkg.add(url="https://github.com/yamanori99/DistSSHQueue.jl")
```

General にはまだ無い。DistSSHKit **0.4.1+** は General から付いてくる。
通常の Queue 作業で Kit を `Pkg.develop` しない。git タグ `v0.1.0-beta.1` は
旧 DistSSHKitQueue (旧 UUID) なので、DistSSHQueue には使わない。

キューホストには **`ssh`**、**`rsync`**、および (git デプロイを使うときだけ) **`git`** も必要。
`pkg> add` では入らない。詳細な利用条件については以下:
[Requirements](https://yamanori99.github.io/DistSSHQueue.jl/dev/requirements/)。

パッケージの詳細は **[ドキュメント](https://yamanori99.github.io/DistSSHQueue.jl/dev/)** を参照。

公式ドキュメント本体は英語である。

## 使用方法

### 基本用語

- **キューホスト** — `~/.distsshqueue` を持ち、`serve` を動かす常時起動のマシン
  (macOS または Linux。VM でよい)。スリープするラップトップはこれではない。
- **クライアント** — 投入・一覧・監視・取消をする開発マシン。台数に上限はない。
  Kit のマスターになってはならない。
- **serve** — キューホスト上の FIFO プロセス。DistSSHKit
  (`execute!(…; detached=true)`) を起動する。止めても、既に走っている
  Kit ジョブは取り消されない。
- **ワーカー** — スクリプトが実際に走る先。DistSSHKit のトークン:
  キューホスト上は `parent[:N]`、SSH 先は `child:NAME[:N]`。

```text
  clients = dev machines (no cap)          one queue host (always on)
  ───────────────────────────────          ──────────────────────────
  yours / a colleague's / …                FIFO     one Kit job at a time
       │                                   table    ~/.distsshqueue
       │  julia -m DistSSHQueue         add-host / remove-host
       │    qhost:NAME                     serve    now, this terminal
       │    submit | status | list-host    enable   again after reboot
       │    watch | cancel | …
       └────────────────────────────────►  then DistSSHKit go/drive
                                           → workers (Kit tokens)
```

`qhost:NAME` はキューホストの SSH 名である (Kit の `child:NAME` と同じ形だが、
ワーカーではなくキューホストを指す)。既にそのマシンにログインしていれば省略する。
ラボが 1 つのとき: `export DISTSSHQUEUE_HOST=…` して `qhost:` を省略できる
(トークンがあればそちらが勝つ)。`--hosts` / `--julia` は Kit の `go` / `drive` のまま。

配置トークン、`go` / `drive` のフラグ、リモートの準備は DistSSHKit の範囲である。
[kit docs](https://yamanori99.github.io/DistSSHKit.jl/stable/) を参照。

### ファイルの置き場

`qhost:` はキューホストの SSH 名であり、保存先の接頭辞ではない。表と Kit の
結果ディレクトリは **そのマシン** に残る。クライアントに
`~/.distsshqueue` は無い。Queue は Kit の木をコピーしない。

#### クライアント

```text
~/my-job/
  Project.toml          DistSSHQueue (CLI)
  Manifest.toml
  SCRIPT.jl             解釈はキューホスト側
```

#### キューホスト

`~/.distsshqueue` と **ジョブごとに一つの Kit クローン** (パスは
`~/org/Repo.jl` で一意)。`--queue-env` とは別。`SCRIPT.jl` はそのクローン。
共有 `config.toml` に `DISTRIBUTED_REMOTE_PROJECT_ROOT` は書かない。
二本目のプロジェクトが同じ worker パスなら `submit` はエラー。

```text
~/.distsshqueue/
  config.toml
  jobs.toml             全行 (prune しない)
  jobs.toml.log
  jobs.toml.pid         serve 中
  jobs.toml.stopped     stop 後、serve まで
  env/                  --queue-env / enable の既定
    Project.toml
    Manifest.toml

~/org/Repo.jl/          ジョブごとに一つのクローン (cwd / DISTRIBUTED_PROJECT_ROOT)
  Project.toml          計算の依存
  SCRIPT.jl
  .distsshkit/go/
    SCRIPT_<UTC>_<id>/  result_path
      kit.pid
      kit.result
```

`enable` (任意。この端末の `serve` だけなら不要):

- **macOS** — `~/Library/LaunchAgents/org.distsshqueue.serve.plist`
- **Linux / WSL2** — `~/.config/systemd/user/distsshqueue.serve.service`

ユーザ unit (root 不要)。中身は同じ
`julia --project=<queue-env> -m DistSSHQueue serve`。

#### ワーカー

Queue の表は無い。Kit 既定は `~/parent/Repo.jl` (共有 `[env]` の
remote ではない)。収集先は上のキューホスト `.distsshkit/`。

```text
<remote project root>/
  Project.toml
  SCRIPT.jl
```

### 例

**クライアント** から (ジョブのディレクトリ。その env から Queue が load できること):

```bash
julia --project=. -m DistSSHQueue qhost:mini list-host
julia --project=. -m DistSSHQueue qhost:mini submit go child:host1:4 SCRIPT.jl
julia --project=. -m DistSSHQueue qhost:mini status
julia --project=. -m DistSSHQueue qhost:mini watch
julia --project=. -m DistSSHQueue qhost:mini cancel <id>
```

`submit` は、`serve` が無ければキューホスト上で起動する。ジョブ id は
stdout 1 行。stderr に `Queued  N` (`DISTSSHKIT_QUIET` で隠す)。

**キューホスト** で一度だけ:

```bash
cd ~/.distsshqueue/env
julia --project=. -m DistSSHQueue setup
julia --project=. -m DistSSHQueue add-host parent child:host1
julia --project=. -m DistSSHQueue enable --queue-env ~/.distsshqueue/env
```

`setup` / `serve` / `enable` / `disable` / `add-host` / `remove-host` は
`qhost:` を受け付けない。コマンド参照:
[User Guide](https://yamanori99.github.io/DistSSHQueue.jl/dev/manual/)。

## ドキュメント

| | |
| --- | --- |
| Introduction | [Introduction](https://yamanori99.github.io/DistSSHQueue.jl/dev/) |
| First Steps | [First Steps](https://yamanori99.github.io/DistSSHQueue.jl/dev/requirements/) |
| User Guide | [User Guide](https://yamanori99.github.io/DistSSHQueue.jl/dev/manual/) |
| API | [API](https://yamanori99.github.io/DistSSHQueue.jl/dev/api/) |
| News | [NEWS.md](NEWS.md) |

## 貢献

バグ報告・機能要望は [Issues](https://github.com/yamanori99/DistSSHQueue.jl/issues)。
貢献の仕方は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。

## ライセンス

ソースコードは [MIT](LICENSE)。
