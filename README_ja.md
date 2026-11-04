# RHEL 9.8 perfディレクトリ一括ダウンロード

## 同梱ファイル

- `DownloadPerf.ttl`：Tera TermのSSH接続・su昇格・tar.gz作成・SCP受信・サーバー一時ファイル削除を実行。
- `VerifyAndExtractPerf.ps1`：SCP受信完了をサイズ・SHA-256で検証し、Windows標準のtar.exeで展開、manifest.csv作成。

## 前提条件

- Windows 11、Tera Term 5、Windows PowerShell 5.1、Windows標準`tar.exe`。
- RHEL 9.8でSSH可能な`spfai001`、`su -`でroot昇格可能なアカウント・rootパスワード。
- RHELで`tar`、`sha256sum`、`stat`、`mktemp`、`chown`が使用可能。
- `SOURCE_PARENT/perf`が実在する通常のディレクトリであること。
- RHELの`/var/tmp`にtar.gzを作成できる空き容量があること。
- 転送中に元ファイルが更新されない、または整合性のとれたスナップショットから取得できること。

## 設定

`DownloadPerf.ttl`の冒頭で以下の3項目を変更します。

```ttl
HOST          = '192.0.2.10'       ; RHELサーバの実際のIPまたはホスト名
SOURCE_PARENT = '/opt/myapp'      ; /opt/myapp/perf を取得する例
LOCAL_BASE    = 'C:\PerfDownloads'
```

`SOURCE_PARENT`は絶対パス、半角英数字・`_`・`-`・`.`・`/`のみ使用できます。`..`は使用できません。`perf`まで指定せず、その**親**を指定します。

## 実行方法

1. `DownloadPerf.ttl`と`VerifyAndExtractPerf.ps1`を同じWindowsフォルダに保存。
2. `DownloadPerf.ttl`を編集して、上記3項目を設定。
3. `DownloadPerf.ttl`をダブルクリック、またはTera Termの「コントロール→マクロ」で実行。
4. SSHの`spfai001`認証ダイアログでパスワードを入力。
5. `su`用rootパスワードをダイアログで入力。
6. 完了後、`C:\PerfDownloads\<ホスト名>_<年月日時分秒>\`を確認。

## 動作

1. `spfai001`でSSHログイン。
2. `LC_ALL=C su -`でroot昇格し、UID=0を確認。
3. `mktemp -d /var/tmp/perf_spfai001_XXXXXXXX`で一時格納場所を作る。
4. root権限で`perf`を`perf.tar.gz`に圧縮する。中間階層・隠しファイル・空ディレクトリを含む。
5. 一時格納場所を`spfai001`所有に変更する（パーミッションを一般公開しない）。
6. サーバ側でアーカイブのサイズとSHA-256を取得。
7. Tera Termの`scprecv`でWindowsへ転送（非同期）。
8. PowerShellがサイズの一致を待ち、SHA-256で完全一致を検証。
9. Windowsの`tar.exe`で`perf`配下を元の構造のまま展開し、ファイル/ディレクトリ一覧の`manifest.csv`を作成。
10. 成功時のみRHEL側の一時格納場所を削除。失敗時は調査用に残す場合がある。

## 保存先例

```text
C:\PerfDownloads\192.0.2.10_20261105_080000\
  perf.tar.gz
  manifest.csv
  verify_extract.log
  perf\
    .hidden
    logs\
      gc.log
      middleware\
        server.log
    subdir\
      sample.txt
```

## 注意点

- **パスワードはマクロに固定保存しません。** 実行のたびにSSH/`su`認証が必要です。完全無人化には公開鍵認証と、管理者承認済みの限定権限によるファイル取得方式を別途設計してください。
- Tera Termの`scprecv`は**ログインユーザー権限**でSCPを行い、`su`はSCP転送権限を変更しません。このため一時アーカイブを使用しています。
- リモート`perf`が通常のディレクトリでなくシンボリックリンクの場合は安全側に失敗します。内部のシンボリックリンクはアーカイブされますが、Windowsでの再現はWindowsの権限とtar.exe動作に依存します。
- WindowsではLinuxのroot所有者、UNIXのアクセス権、ACL、デバイス等がそのまま再現されるとは限りません。
- `perf`に更新中のログがあるとGNU tarが変更を検知して失敗する場合があります。実行中のデータの一貫性を保証するものではありません。
- `manifest.csv`は取得した一覧です。**差分同期自体は行いません。** 再実行するたびに新しい日時別フォルダへ全量保存します。
- エラー時は`verify_extract.log`を確認してください。一時格納場所が残った場合はサーバ管理者が`/var/tmp/perf_spfai001_...`を確認・削除してください。
- 長いパス、特殊なファイル、EFS等の大量ファイルの取得では、tarの警告やWindowsの展開制約に注意してください。
- 既知のホスト鍵を事前に確認して接続してください。初回接続時に表示されるホスト鍵確認を無条件承認しないでください。

## 検証に使えるRHEL側コマンド

```bash
sudo test -d /opt/myapp/perf && echo OK
sudo find /opt/myapp/perf -type f | wc -l
sudo du -sh /opt/myapp/perf
command -v tar sha256sum stat mktemp
```

## 公式資料

- Tera Term `scprecv`：https://teratermproject.github.io/manual/5/ja/macro/command/scprecv.html
- Tera Term `connect`：https://teratermproject.github.io/manual/5/ja/macro/command/connect.html
- Tera Term `exec`：https://teratermproject.github.io/manual/5/ja/macro/command/exec.html