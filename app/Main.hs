module Main where

import qualified Data.Vector.Unboxed as VU
import Data.List (intercalate, maximumBy)
import Data.Ord (comparing)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import System.Environment (getArgs)
import System.IO (hSetEncoding, stdout, utf8, openFile, IOMode(..), hPutStr, hClose)
import Text.Printf (printf)

import Types
import DataLoader
import Portfolio
import Simulation

-- | Configurações padrão
defaultCSV :: FilePath
defaultCSV = "data/dow30_returns.csv"

defaultNSims :: Int
defaultNSims = 1000000  -- 1 milhão de simulações por combinação

defaultMinK :: Int
defaultMinK = 25  -- mínimo de ações por carteira (C(30,25)+...+C(30,30) = 174.437)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  args <- getArgs
  let csvPath = case args of { (p:_)     -> p; [] -> defaultCSV }
      nSims   = case args of { (_:n:_)   -> read n; _ -> defaultNSims }
      minK    = case args of { (_:_:k:_) -> read k; _ -> defaultMinK }

  putStrLn "============================================="
  putStrLn " Portfolio Optimizer — Programação Funcional"
  putStrLn " Insper 2026-1 | Gustavo Mendes da Silva"
  putStrLn "============================================="
  putStrLn ""

  -- 1. Carregar dados (impuro — I/O)
  putStrLn $ "[1/4] Carregando dados de: " ++ csvPath
  stockData <- loadReturns csvPath
  let returns = sdReturns stockData
      names   = sdNames   stockData
      nStocks = sdNStocks stockData
      nDays   = sdNDays   stockData

  putStrLn $ "      Ações: "           ++ show nStocks
  putStrLn $ "      Dias de retorno: " ++ show nDays
  putStrLn ""

  -- 2. Gerar combinações (puro)
  putStrLn $ "[2/4] Gerando combinações (k >= " ++ show minK ++ " de " ++ show nStocks ++ ")..."
  let combs  = allCombinations nStocks minK
      nCombs = length combs
  putStrLn $ "      Total de combinações: " ++ show nCombs
  putStrLn ""

  -- 3. Simulação Monte Carlo em paralelo (puro)
  putStrLn $ "[3/4] Rodando " ++ show nSims ++ " simulações por combinação..."
  putStrLn $ "      Total de simulações: " ++ show (nCombs * nSims)
  putStrLn   "      Paralelismo: parMap rdeepseq — cada combinação é um spark puro independente"
  putStrLn ""

  startTime <- getCurrentTime

  -- Pipeline funcional: parMap avaliar |> maximumBy comparar
  -- parMap rdeepseq avalia cada combinação como spark independente (sem estado compartilhado).
  -- maximumBy é equivalente ao foldl' com acumulador de máximo — O(n) em memória.
  let results     = runAllSimulations returns combs nSims
      bestOverall = maximumBy (comparing (srSharpe . crBest)) results

  -- Força avaliação completa antes de medir o tempo
  srSharpe (crBest bestOverall) `seq` return ()
  endTime <- getCurrentTime

  let elapsed = diffUTCTime endTime startTime

  -- 4. Apresentar resultados (impuro — I/O)
  putStrLn "[4/4] Resultados"
  putStrLn "============================================="
  putStrLn ""

  let best      = crBest bestOverall
      bestIdxs  = crStocks bestOverall
      bestNames = map (names !!) bestIdxs
      bestW     = srWeights best

  putStrLn "Melhor carteira encontrada:"
  putStrLn $ "  Sharpe Ratio (anualizado): " ++ printf' "%.6f" (srSharpe best)
  putStrLn $ "  Retorno anualizado:        " ++ printf' "%.4f%%" (srReturn best * 100)
  putStrLn $ "  Volatilidade anualizada:   " ++ printf' "%.4f%%" (srVol best * 100)
  putStrLn ""

  putStrLn "Composição da carteira:"
  putStrLn $ "  Ações (" ++ show (length bestIdxs) ++ "):"
  mapM_ (\(name, idx) ->
    let w = bestW `VU.unsafeIndex` idx
    in putStrLn $ "    " ++ padRight 8 name ++ printf' "%6.2f%%" (w * 100)
    ) (zip bestNames [0..])
  putStrLn ""

  putStrLn $ "Tempo de execução: " ++ show elapsed
  putStrLn ""

  -- Salva resultado em arquivo UTF-8
  let resultFile = "data/resultado.txt"
  writeResult resultFile bestOverall names
  putStrLn $ "Resultado salvo em: " ++ resultFile

-- | Formata um Double como String usando printf
printf' :: String -> Double -> String
printf' = printf

-- | Padding à direita com espaços
padRight :: Int -> String -> String
padRight n s = s ++ replicate (max 0 (n - length s)) ' '

-- | Salva resultado em arquivo texto com encoding UTF-8
writeResult :: FilePath -> CombinationResult -> [String] -> IO ()
writeResult path cr names = do
  let best      = crBest cr
      bestIdxs  = crStocks cr
      bestNames = map (names !!) bestIdxs
      bestW     = srWeights best
      header    = "=== MELHOR CARTEIRA ==="
      sharpe    = "Sharpe Ratio: "          ++ show (srSharpe best)
      ret       = "Retorno anualizado: "    ++ show (srReturn best)
      vol       = "Volatilidade anualizada: " ++ show (srVol best)
      stocks    = "Acoes: " ++ intercalate ", " bestNames
      weights   = unlines $ zipWith
                    (\name idx -> name ++ ": " ++ show (bestW `VU.unsafeIndex` idx))
                    bestNames [0..]
      content   = unlines [header, sharpe, ret, vol, "", stocks, "", "Pesos:", weights]
  h <- openFile path WriteMode
  hSetEncoding h utf8
  hPutStr h content
  hClose h
