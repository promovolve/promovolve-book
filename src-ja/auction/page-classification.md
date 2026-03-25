# フェーズ1: ページ分類

オークションを実行する前に、システムはページの内容を理解する必要がある。ページ分類は、LLMベースの分析を使用して、URLをIAB Content Taxonomy 2.1カテゴリと信頼度スコアにマッピングする。

## 2つのTaxonomy、1つのマッチ

Promovolveはオークション時に交差する2つの異なるIAB taxonomyを使用する:

| Taxonomy | バージョン | 設定者 | 目的 |
|----------|---------|-------------|---------|
| **Ad Product Taxonomy** | 2.0 | 広告主 | 「私の製品は何か？」（例: Travel、Kitchen Equipment） |
| **Content Taxonomy** | 2.1 | LLM分類器 | 「このページは何についてか？」（例: Destinations、Outdoor Recreation） |

広告主はcontent categoryを見ることはない。自分のproductカテゴリを選ぶだけで、`ContentToAdProductMapping`が公式IABマッピングファイル（`content_2.1_to_ad_product_2.0.tsv`）を使って、マッチするcontent categoryを導出する。productカテゴリに対する直接のマッピングが存在しない場合、システムはtaxonomyの親チェーンを遡ってマッピングを見つける。

オークション時のマッチングは**厳密**である: ページのcontent categoryがキャンペーンの導出されたcontent categoryセットに含まれている必要がある。入札時にファジーマッチングや階層的マッチングは行われない — 階層はキャンペーン設定時に一度だけ解決される。

## 分類パイプライン

Promovolveは分類に複数のLLMプロバイダをサポートしており、`application.conf`で設定する:

| プロバイダ | 設定キー | 環境変数 |
|----------|-----------|---------|
| Gemini | `promovolve.gemini.api-key` | `GEMINI_API_KEY` |
| OpenAI | `promovolve.openai.api-key` | `OPENAI_API_KEY` |
| Anthropic | `promovolve.anthropic.api-key` | `ANTHROPIC_API_KEY` |

Geminiがデフォルトで有効になっている（`promovolve.gemini.enabled = true`）。

## 分類の出力

LLMはカテゴリIDを返し、それらは**IAB Content Taxonomy 2.1の数値ID**に正規化される。レガシーのIAB 1.0形式のID（例: `"IAB17"`）は`TieredCategory.normalize()`を通じて2.1の対応するID（例: `"483"`）に変換される。結果はカテゴリと信頼度のマップとなる:

```json
{
  "url": "https://example.com/sports/nba-finals-recap",
  "categories": {
    "483": 0.92,
    "484": 0.85,
    "393": 0.45
  }
}
```

各`Confidence`値は[0, 1]の範囲の不透明な`Double`である。すべての下流のマッチングはこれらの数値のContent Taxonomy 2.1 IDを使用する。

## Top-Kカテゴリ選択

AuctioneerEntityは信頼度スコアに基づいて**上位Kカテゴリ**（デフォルトK=3）を選択する。これらのカテゴリのみがランキングと入札に進む。

## 分類の保存

分類はAuctioneerEntityの状態に`Map[URL, Classification]`として保存され、ページURLをキーとし、`classifiedAtMs`でタイムスタンプが付与される。5分ごとに、クリーンアップタスクが48時間の鮮度ウィンドウより古いエントリを削除する。

## スコアリングにおける役割

信頼度スコアはカテゴリランキングに反映される:

```
categoryScore = classifierConfidence × rankerWeight
```

この合成スコアは`CandidateView.categoryScore`に格納され、コールドスタート時のThompson Samplingの事前分布として使用される。
