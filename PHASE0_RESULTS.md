# Phase 0: 仮説検証結果

## 実行日: 2025-06-26

## 検証目標
Strategy B実装前に、根本原因の仮説を検証する

## 検証結果

### ✅ 仮説1: ファイルシステムアクセスパターン

**予想**: コンテナ内では `/workspace` は存在するが `/Users/...` は存在しない

**結果**:
```bash
# コンテナ内
/workspace/go.mod          ✅ 存在
/workspace/calculator.go   ✅ 存在  
/workspace/*.go            ✅ すべて存在
/Users/ksoichiro/...       ❌ 存在しない ("Host path not accessible")
```

**結論**: ✅ 仮説通り

### ✅ 仮説2: gopls動作パターン

**予想**: gopls は `/workspace` パスで正常動作し、ホストパスで失敗する

**結果**:
```bash
# Test 1: /workspace パス
gopls check /workspace/main.go
Exit status: 0              ✅ 正常動作

# Test 2: ホストパス  
gopls check /Users/.../main.go
Error: no such file or directory  ❌ 明確な失敗
```

**結論**: ✅ 仮説通り

### ✅ 仮説3: ワークスペース認識

**予想**: `/workspace` からのモジュール解決は成功する

**結果**:
```bash
# モジュール一覧
go list -m all
go-test-example            ✅ プロジェクトを認識
依存関係                   ✅ 正常に解決

# ビルドテスト
go build -v ./...          ✅ 成功
```

**結論**: ✅ 仮説通り

## 根本原因の確認

### 問題の詳細メカニズム

1. **LSPメッセージ送信**: `textDocument/didOpen` で `file:///Users/.../main.go`
2. **gopls処理**: コンテナ内で `/Users/.../main.go` を探索
3. **失敗**: ファイルが存在しないため処理不可
4. **影響**: `NewCalculator` などの定義解決が失敗

### 実際のコード構造

**go-test-example の構造**:
```go
// main.go
package main

func main() {
    calc := NewCalculator()  // ← この定義が見つからない
    calc.Add(5, 3)
}

// calculator.go  
package main

func NewCalculator() *Calculator {  // ← 同じパッケージ内で定義
    return &Calculator{}
}
```

**問題**: 同一パッケージ内の定義すら解決できない（パス問題のため）

## GO/NO-GO判定

### ✅ GO - 実装開始の根拠

1. **明確な因果関係**: パス不一致 → gopls失敗 → LSP機能破綻
2. **解決策の有効性**: `/workspace` パスでgoplsは正常動作することを確認
3. **実装可能性**: プロキシによるパス変換で問題解決可能

### Strategy B実装の正当性

**理論的根拠**:
- gopls は `/workspace` パスで完全に正常動作
- パス変換により一貫した世界観を提供可能
- 言語非依存（ファイルパス概念は共通）

**実証的根拠**:
- Phase 0で仮説が完全に実証済み
- 失敗メカニズムが明確に特定済み
- 解決策の有効性が確認済み

## 次のステップ

Phase 2-1 (Day 1) の実装を開始:
- JSON-RPC パーサー実装
- stdio 通信レイヤー実装  
- 基本中継機能（変換なし）の動作確認

**期待結果**: 現状と同じエラーが発生（プロキシが透過的に動作することを確認）
