# Otimização de Portfólio via Simulação de Monte Carlo

**Projeto 2 — Programação Funcional**

| Campo | Informação |
|---|---|
| **Autor** | Gustavo Mendes da Silva |
| **Instituição** | Insper — Instituto de Ensino e Pesquisa |
| **Disciplina** | Programação Funcional 2026-1 |
| **Professores** | Fábio Ayres |

---

## 1. Descrição do Problema

Este projeto aborda o problema de **otimização de carteira de investimentos** sob o critério do **Sharpe Ratio**, aplicado às 30 ações do índice Dow Jones Industrial Average no segundo semestre de 2025 (01/07/2025 a 31/12/2025, 126 dias úteis).

### O que é o Sharpe Ratio?

O Sharpe Ratio mede o retorno obtido por unidade de risco assumido. Uma carteira com SR elevado entrega alto retorno relativo à sua volatilidade. Maximizar o SR é uma abordagem clássica de alocação eficiente de capital.

### Restrições do problema

- **Long-only:** todos os pesos são não-negativos ($w_i \geq 0$)
- **Concentração máxima:** nenhum ativo pode exceder 20% da carteira ($w_i \leq 0{,}20$)
- **Orçamento total:** os pesos somam 1 ($\sum_i w_i = 1$)

### Escopo combinatório (atualização do professor)

O professor atualizou o enunciado para **carteiras de 25 ou mais ações** dentre as 30 do Dow Jones, gerando:

$$\binom{30}{25} + \binom{30}{26} + \binom{30}{27} + \binom{30}{28} + \binom{30}{29} + \binom{30}{30} = 174.437 \text{ combinações}$$

Cada combinação é avaliada com 1.000.000 de simulações de Monte Carlo.

---

## 2. Fundamentação Matemática

Seja $R \in \mathbb{R}^{T \times k}$ a matriz de retornos diários dos $k$ ativos selecionados ao longo de $T = 126$ dias, e $w \in \mathbb{R}^k$ o vetor de pesos.

### Série de retornos da carteira

$$r_p = R \cdot w \quad (r_p \in \mathbb{R}^T)$$

### Retorno anualizado

$$\mu_p = \overline{r_p} \times 252$$

onde $\overline{r_p} = \frac{1}{T}\sum_{t=1}^{T} r_{p,t}$. Na implementação, utiliza-se a equivalência $\overline{r_p} = \boldsymbol{\mu}^\top w$, com $\boldsymbol{\mu}[i] = \frac{1}{T}\sum_t R_{ti}$ pré-calculado uma vez por combinação — eliminando o loop de 126 dias em cada simulação.

### Volatilidade anualizada

$$\sigma_p = \sqrt{w^\top C\, w \times 252}$$

onde $C$ é a matriz de covariância amostral dos retornos diários, pré-calculada uma vez por combinação.

### Sharpe Ratio

$$SR = \frac{\mu_p}{\sigma_p}$$

A taxa livre de risco é zero, conforme especificado no enunciado (slide 8).

---

## 3. Abordagem Computacional

### Força Bruta via Monte Carlo

O espaço de carteiras factíveis é contínuo e não-convexo sob as restrições de caixa ($w_i \leq 0{,}20$). A abordagem adotada é **simulação de Monte Carlo**: para cada combinação de ativos, são sorteados 1.000.000 vetores de pesos aleatórios satisfazendo as restrições, avaliado o Sharpe Ratio de cada um, e mantido apenas o máximo.

| Parâmetro | Valor |
|---|---|
| Combinações avaliadas | 174.437 |
| Simulações por combinação | 1.000.000 |
| Total de simulações | ~174 bilhões |

### Por que Programação Funcional?

A simulação é **embaraçosamente paralela**: cada combinação de ativos é avaliada de forma completamente independente. Em programação funcional:

- **Funções puras** (sem estado compartilhado) eliminam condições de corrida — o paralelismo é seguro por construção.
- **Imutabilidade** garante que `parMap rdeepseq` distribua o trabalho entre threads sem sincronização explícita.
- **Operadores de ordem superior** (`map`, `foldl'`, `unfoldr`) expressam o pipeline de forma declarativa e composicional.

### Conceitos funcionais utilizados

| Conceito | Aplicação |
|---|---|
| Funções puras | Todos os cálculos financeiros (`covarianceMatrix`, `fastAnnualizedSharpe`, `generateWeights`) |
| Imutabilidade | `VU.Vector Double` (vetores unboxed imutáveis); sem `IORef`, `MVar`, `ST monad` |
| `parMap rdeepseq` | Paralelismo sobre as 174.437 combinações (`Simulation.hs`) |
| `maximumBy` / `foldl'` | Busca do máximo global sem lista intermediária de resultados |
| `unfoldr` | Geração de pesos como stream puro e determinístico a partir de uma seed |
| Pattern matching | Parsing de argumentos CLI, restrições recursivas de pesos |
| Tipos algébricos | `SharpeResult`, `CombinationResult` em `Types.hs` |

---

## 4. Implementação

### Linguagem

**Haskell**, compilado com GHC 9.6 via Stack.

### Estrutura de módulos

```
portfolio-optimizer/
├── app/
│   └── Main.hs           — orquestração: I/O, pipeline principal, saída de resultados
├── src/
│   ├── Types.hs          — tipos algébricos: SharpeResult, CombinationResult
│   ├── DataLoader.hs     — leitura do CSV de retornos (único módulo com I/O)
│   ├── Portfolio.hs      — funções puras: covariância, médias, Sharpe Ratio
│   └── Simulation.hs     — geração de pesos, combinatória, parMap, Monte Carlo
├── data/
│   └── dow30_returns.csv — retornos diários das 30 ações (126 linhas × 30 colunas)
├── portfolio-optimizer.cabal
├── stack.yaml
└── README.md
```

### Descrição dos módulos

#### `Types.hs`
Define os tipos de dados algébricos centrais:
- `DailyReturns`, `Weights`, `CovMatrix` — sinônimos de tipo sobre vetores unboxed imutáveis
- `SharpeResult` — resultado de uma simulação: Sharpe, retorno anualizado, volatilidade anualizada, pesos
- `CombinationResult` — melhor `SharpeResult` encontrado para uma combinação de ativos

#### `DataLoader.hs`
Único módulo com efeito colateral (leitura de arquivo). Funções:
- `loadReturns` (impura) — lê o CSV e retorna `StockData`
- `transposeToColumns` (pura) — transpõe a matriz dias×ativos para ativos×dias
- `parseCSV`, `readDouble` (puras) — parsing do CSV

#### `Portfolio.hs`
Funções puras de cálculo financeiro, sem efeitos colaterais:
- `precomputeMeans` — $\boldsymbol{\mu}[i] = \frac{1}{T}\sum_t R_{ti}$, calculado uma vez por combinação
- `covarianceMatrix` — matriz $C$ calculada uma vez por combinação
- `fastAnnualizedSharpe` — Sharpe anualizado via produto interno; $\mu_p = \boldsymbol{\mu}^\top w \times 252$ elimina o loop de 126 dias por simulação

#### `Simulation.hs`
Pipeline Monte Carlo, inteiramente funcional puro:
- `generateWeights` — pesos via `unfoldr` sobre `StdGen`; determinístico por seed; sem `ST monad`
- `enforceConstraints` — garante $w_i \leq 0{,}20$ por iteração funcional
- `allCombinations`, `combinations` — enumera C(30,25)+...+C(30,30) por recursão
- `simulateCombination` — pipeline `map evalSeed [0..nSims-1]` + `foldl'`
- `runAllSimulations` — `parMap rdeepseq` sobre todas as combinações

#### `Main.hs`
Orquestra o pipeline completo, mantendo o I/O encapsulado em `main`:

```haskell
-- Pipeline funcional completo:
loadReturns csv
  >>= \stockData ->
        let combs       = allCombinations nStocks minK          -- puro
            results     = runAllSimulations returns combs nSims  -- puro, paralelo
            bestOverall = maximumBy (comparing (srSharpe . crBest)) results
        in writeResult ...
```

### Paralelismo com `parMap rdeepseq`

```haskell
runAllSimulations allReturns combs nSims =
  parMap rdeepseq
    (\(idx, comb) -> simulateCombination allReturns comb nSims (idx * nSims))
    (zip [0..] combs)
```

`parMap rdeepseq` de `Control.Parallel.Strategies` cria um *spark* independente para cada combinação. O RTS do GHC distribui os sparks entre os *capabilities* (threads do SO) ativados com `+RTS -N`. Como `simulateCombination` é pura, não há estado compartilhado — o paralelismo é seguro por construção, sem locks nem sincronização.

---

## 5. Pré-requisitos e Instalação

### Requisitos

- **GHC >= 9.4** (recomendado: 9.6, instalado via GHCup)
- **Stack >= 2.9**

### Instalar GHCup

**Linux / macOS:**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

**Windows (PowerShell, como administrador):**
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Command -ScriptBlock ([ScriptBlock]::Create((Invoke-WebRequest https://www.haskell.org/ghcup/sh/bootstrap-haskell.ps1 -UseBasicParsing))) -ArgumentList $true
```

Selecione "Install Stack" durante a instalação quando solicitado.

### Instalar Stack separadamente

**Windows:**
```powershell
winget install --id Haskell.Stack
```

**Linux / macOS:**
```bash
curl -sSL https://get.haskellstack.org/ | sh
```

### Verificar instalação

```bash
ghc   --version   # GHC 9.6.x
stack --version   # Stack 2.x.x
```

---

## 6. Como Executar

### Compilar

```bash
stack build
```

### Sintaxe geral

```bash
stack run -- <csv> <nSims> <minK> +RTS -N<cores> -RTS
```

| Parâmetro | Descrição |
|---|---|
| `<csv>` | Caminho para o CSV de retornos diários |
| `<nSims>` | Simulações de Monte Carlo por combinação (padrão: 1000000) |
| `<minK>` | Tamanho mínimo da carteira em ações (padrão: 25) |
| `+RTS -N` | Usar todos os núcleos disponíveis |
| `+RTS -N4` | Limitar a 4 núcleos |

### Exemplos

```bash
# Teste de corretude: 1 combinação, 1M sims (~3 s)
stack run -- data/dow30_returns.csv 1000000 30 +RTS -N -RTS

# Demo intermediária: 436 combinações, 1M sims (~10 min, 8 threads)
stack run -- data/dow30_returns.csv 1000000 28 +RTS -N8 -RTS

# Execução completa: 174.437 combinações, 1M sims
stack run -- data/dow30_returns.csv 1000000 25 +RTS -N -RTS

# Execução com padrão (equivalente ao acima)
stack run
```

### Estimativas de tempo (Intel i7-1165G7, 4 cores)

| Configuração | Combinações | Simulações totais | Tempo |
|---|---|---|---|
| k ≥ 30, 1M sims | 1 | 1 M | ~3 s |
| k ≥ 29, 1M sims | 31 | 31 M | ~1 min |
| k ≥ 28, 1M sims | 436 | 436 M | ~10 min |
| k ≥ 25, 1M sims | 174.437 | ~174 G | ~22 h |

Escalabilidade com mais núcleos (k ≥ 25, 1M sims):

| Núcleos | Tempo estimado |
|---|---|
| 4 | ~22 h |
| 8 | ~11 h |
| 16 | ~5 h |
| 32 | ~2 h |

---

## 7. Resultados

### k ≥ 28 — 436 combinações, 1M simulações (~10 min, 8 threads)

```
=============================================
 Portfolio Optimizer — Programação Funcional
 Insper 2026-1 | Gustavo Mendes da Silva
=============================================

[3/4] Rodando 1000000 simulações por combinação...
      Total de simulações: 436000000
      Paralelismo: parMap rdeepseq — cada combinação é um spark puro independente

[4/4] Resultados
=============================================

Melhor carteira encontrada:
  Sharpe Ratio (anualizado): 3.106447
  Retorno anualizado:        27.1100%
  Volatilidade anualizada:    8.7300%

Composição da carteira (28 ações):
  AAPL      20.00%    AMGN      20.00%
  AXP       20.00%    CAT       20.00%
  CSCO      20.00%    IBM       20.00%
  JPM       20.00%    KO        20.00%
  MCD       20.00%    PG        20.00%
  TRV       20.00%    VZ        20.00%
  WMT       20.00%    ...

Tempo de execução: 9m 43s
```

### k ≥ 30 — 1 combinação, 1M simulações (~3 s)

```
Melhor carteira encontrada:
  Sharpe Ratio (anualizado): 2.588548
  Retorno anualizado:        23.4511%
  Volatilidade anualizada:    9.0596%

Tempo de execução: 2.86s
```

---

## 8. Dados de Entrada

`data/dow30_returns.csv` contém os retornos diários das 30 ações do Dow Jones, período 01/07/2025 a 31/12/2025.

- **30 colunas:** AAPL, AMGN, AMZN, AXP, BA, CAT, CRM, CSCO, CVX, DIS, GS, HD, HON, IBM, JNJ, JPM, KO, MCD, MMM, MRK, MSFT, NKE, NVDA, PG, SHW, TRV, UNH, V, VZ, WMT
- **126 linhas:** retornos diários (sem coluna de data)
- **Formato:** CSV sem índice de linha; primeira linha é o cabeçalho com tickers

O resultado é salvo automaticamente em `data/resultado.txt`.
