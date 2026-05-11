module Simulation
  ( generateWeights
  , simulateCombination
  , allCombinations
  , runAllSimulations
  ) where

import qualified Data.Vector.Unboxed as VU
import qualified Data.Vector         as V
import Data.List (foldl', unfoldr)
import System.Random (mkStdGen, uniformR)
import Control.Parallel.Strategies (parMap, rdeepseq)
import Types
import Portfolio

-- ============================================================
-- GERAÇÃO DE PESOS — Função pura, determinística por seed
-- ============================================================

-- | Gera pesos aleatórios a partir de uma seed.
--   Mesma seed → mesmos pesos. Sem estado mutável.
--   Restrições: w_i ∈ [0, 0.2], Σw = 1.
generateWeights :: Int -> Int -> Weights
generateWeights nAssets seed =
  let raws   = take nAssets $ unfoldr genOne (mkStdGen seed)
      normed = normalise raws
  in VU.fromList (enforceConstraints normed)
  where
    genOne g =
      let (v, g') = uniformR (0.001 :: Double, 1.0) g
      in Just (min 0.2 v, g')

-- | Divide cada elemento pela soma da lista
normalise :: [Double] -> [Double]
normalise xs =
  let total = sum xs
  in map (/ total) xs

-- | Garante w_i ≤ 0.2 via iteração funcional (caminho raro)
enforceConstraints :: [Double] -> [Double]
enforceConstraints ws
  | all (<= 0.2 + 1e-10) ws = ws
  | otherwise =
      let capped = map (min 0.2) ws
          total  = sum capped
          normed = map (/ total) capped
      in enforceConstraints normed

-- ============================================================
-- COMBINATÓRIA — Funções puras
-- ============================================================

allCombinations :: Int -> Int -> [[Int]]
allCombinations n kMin = concatMap (combinations n) [kMin .. n]

combinations :: Int -> Int -> [[Int]]
combinations n k = go 0 k
  where
    go _     0         = [[]]
    go start remaining
      | start > n - remaining = []
      | otherwise =
          map (start :) (go (start + 1) (remaining - 1))
          ++ go (start + 1) remaining

-- ============================================================
-- SIMULAÇÃO POR COMBINAÇÃO — Pipeline funcional puro
-- ============================================================

-- | Simula nSims carteiras para uma combinação e retorna a melhor.
--   Pipeline: pré-cômputo → map evalSeed → foldl' streaming
--
--   Otimizações funcionais:
--   1. meanRets pré-calculado UMA VEZ: elimina loop de 126 dias por simulação
--   2. covMat pré-calculado UMA VEZ por combinação
--   3. generateWeights puro: seed → pesos (sem estado compartilhado)
--   4. foldl' streaming: sem lista de nSims SharpeResults em memória
simulateCombination :: V.Vector (VU.Vector Double)
                    -> [Int]
                    -> Int
                    -> Int
                    -> CombinationResult
simulateCombination allReturns selectedIdxs nSims baseSeed =
  let nAssets  = length selectedIdxs
      covMat   = covarianceMatrix allReturns selectedIdxs
      meanRets = precomputeMeans  allReturns selectedIdxs
      evalSeed i = fastAnnualizedSharpe meanRets covMat
                     (generateWeights nAssets (baseSeed + i))
      results  = map evalSeed [0 .. nSims - 1]
      best     = foldl' (\acc r -> if srSharpe r > srSharpe acc then r else acc)
                        (head results) (tail results)
  in CombinationResult { crStocks = selectedIdxs, crBest = best }

-- ============================================================
-- SIMULAÇÃO GLOBAL — parMap rdeepseq
-- ============================================================

-- | Executa todas as combinações em paralelo com parMap rdeepseq.
--   Cada combinação é avaliada como uma função pura independente,
--   permitindo paralelismo seguro sem estado compartilhado.
runAllSimulations :: V.Vector (VU.Vector Double)
                  -> [[Int]]
                  -> Int
                  -> [CombinationResult]
runAllSimulations allReturns combs nSims =
  parMap rdeepseq
    (\(idx, comb) -> simulateCombination allReturns comb nSims (idx * nSims))
    (zip [0..] combs)
