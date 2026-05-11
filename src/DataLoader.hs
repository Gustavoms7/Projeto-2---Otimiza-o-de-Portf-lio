module DataLoader
  ( loadReturns
  , StockData(..)
  ) where

import qualified Data.ByteString.Lazy       as BL
import qualified Data.Vector                as V
import qualified Data.Vector.Unboxed        as VU
import qualified Data.ByteString.Lazy.Char8 as BLC

-- | Dados carregados do CSV
data StockData = StockData
  { sdNames   :: ![String]                        -- ^ Nomes/tickers das ações
  , sdReturns :: !(V.Vector (VU.Vector Double))   -- ^ Retornos diários por ação
  , sdNDays   :: !Int
  , sdNStocks :: !Int
  } deriving (Show)

-- | Carrega o CSV de retornos diários
--   Formato do CSV (sem coluna de data, já são retornos):
--   AAPL,AMGN,AMZN,AXP,...
--   0.0222,0.0217,-0.0024,...
--   0.0052,0.0046,0.0158,...
loadReturns :: FilePath -> IO StockData
loadReturns path = do
  csvData <- BL.readFile path
  let rows = parseCSV csvData
  case rows of
    []     -> error "CSV vazio!"
    (h:ds) -> do
      let stockNames = h
          nStocks    = length stockNames
          parsed     = map (map readDouble) ds
          returns    = transposeToColumns parsed nStocks
          nDays      = VU.length (returns V.! 0)
      putStrLn $ "Carregados " ++ show nDays ++ " dias de retornos para " ++ show nStocks ++ " ações"
      return StockData
        { sdNames   = stockNames
        , sdReturns = returns
        , sdNDays   = nDays
        , sdNStocks = nStocks
        }

-- | Transpõe de linhas (dias) para colunas (ações) — Função pura
transposeToColumns :: [[Double]] -> Int -> V.Vector (VU.Vector Double)
transposeToColumns rows nCols =
  V.generate nCols $ \col ->
    VU.fromList $ map (!! col) rows

-- | Parsing simples do CSV
parseCSV :: BL.ByteString -> [[String]]
parseCSV = map (splitOn ',') . filter (not . null) . lines . BLC.unpack
  where
    splitOn :: Char -> String -> [String]
    splitOn sep = go []
      where
        go acc []       = [reverse acc]
        go acc (c:cs)
          | c == sep    = reverse acc : go [] cs
          | otherwise   = go (c:acc) cs

-- | Lê um Double de uma string
readDouble :: String -> Double
readDouble s = case reads (strip s) of
  [(v, "")] -> v
  _         -> error $ "Não foi possível ler número: " ++ show s
  where
    strip = filter (\c -> c /= ' ' && c /= '\r' && c /= '"')
