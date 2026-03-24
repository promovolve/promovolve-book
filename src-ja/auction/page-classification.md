# フェーズ1: ページ分類

オークションを実行する前に、システムはページの内容を理解する必要があります。ページ分類は、LLMベースの分析を使用して、URLをIAB Content Taxonomyカテゴリと信頼度スコアにマッピングします。

## 分類パイプライン

Promovolveは分類に複数のLLMプロバイダをサポートしており、`application.conf`で設定します:

| プロバイダ | 設定キー | 環境変数 |
|----------|-----------|---------|
| Gemini | `promovolve.gemini.api-key` | `GEMINI_API_KEY` |
| OpenAI | `promovolve.openai.api-key` | `OPENAI_API_KEY` |
| Anthropic | `promovolve.anthropic.api-key` | `ANTHROPIC_API_KEY` |

Geminiがデフォルトで有効になっています（`promovolve.gemini.enabled = true`）。

## 分類の出力

分類器はカテゴリと信頼度のマップを生成します:

```json
{
  "url": "https://example.com/sports/nba-finals-recap",
  "categories": {
    "IAB17": 0.92,
    "IAB17-1": 0.85,
    "IAB12": 0.45
  }
}
```

各`Confidence`値は[0, 1]の範囲の不透明な`Double`です。

## Top-Kカテゴリ選択

AuctioneerEntityは信頼度スコアに基づいて**上位Kカテゴリ**（デフォルトK=3）を選択します。これらのカテゴリのみがランキングと入札に進みます。

## 分類の保存

分類はAuctioneerEntityの状態に`Map[URL, Classification]`として保存され、ページURLをキーとし、`classifiedAtMs`でタイムスタンプが付与されます。5分ごとに、クリーンアップタスクが48時間の鮮度ウィンドウより古いエントリを削除します。

## スコアリングにおける役割

信頼度スコアはカテゴリランキングに反映されます:

```
categoryScore = classifierConfidence × rankerWeight
```

この合成スコアは`CandidateView.categoryScore`に格納され、コールドスタート時のThompson Samplingの事前分布として使用されます。
