# フェーズ5: ServeIndexキャッシング

オークションの最終フェーズでは、ショートリストされた候補を分散インメモリキャッシュ（ServeIndex）に格納し、配信時に即座に取得できるようにします。

## ServeIndexへの書き込み

ショートリスト後、AuctioneerEntityは候補セットをServeIndexに書き込みます:

```
Key:   siteId|slotId
Value: ServeView(
         candidates: Vector[CandidateView],
         version: Long,       // auction timestamp
         expiresAtMs: Long     // currentTimeMillis + TTL
       )
```

### 書き込みセマンティクス

| 操作 | 一貫性 | ユースケース |
|-----------|-------------|----------|
| **Put**（完全置換） | `WriteLocal` | 新しいオークション結果 |
| **Append**（単一候補の追加） | `WriteLocal` + `creativeId`による重複排除 | 孤立したクリエイティブの追加 |
| **Remove** | `WriteMajority(800ms)` + リトライ（最大5回、初期バックオフ200ms） | クリエイティブ/キャンペーンの削除 |
| **CPM update** | `WriteLocal` | ベストエフォートのCPM更新 |
| **FilterByCreativeIds** | `WriteLocal` | 有効なクリエイティブのみを保持 |

### TTL

各エントリのデフォルトTTLは**120分**です。予算枯渇イベント時には、次の日次予算リセットまでエントリが存続するよう、TTLが`dayDurationSeconds × 1.1 × 1000ms`に更新されます。

### レプリケーション

ServeIndexはPekko DDataを使用し、gossipベースのレプリケーションを行います:
- gossip間隔: 2秒
- サブスクライバへの通知: 500ms
- gossipラウンドあたりの最大デルタ要素数: 500

すべてのAPIノードが、書き込みから数秒以内に完全なローカルコピーを取得します。

### バケッティング

エントリはキーのハッシュにより**32バケット**（2のべき乗）に分割されます。各バケットは独立した`LWWMap[String, ServeView]`です。これによりCRDTのデルタサイズが小さく保たれます — あるバケットの更新は、他のバケットのエントリに対するデルタを生成しません。

### 削除操作

ServeIndexはきめ細かな削除をサポートします:
- `RemoveCampaignFromKey`: スロット全体にわたって特定キャンペーンのすべての候補を削除
- `RemoveCreativeFromKey`: すべてのスロットにわたって特定のクリエイティブを削除
- `RemoveBySite`: サイト上のすべてのスロットの一括削除

すべての削除操作は耐久性のため`WriteMajority`とリトライを使用します。
