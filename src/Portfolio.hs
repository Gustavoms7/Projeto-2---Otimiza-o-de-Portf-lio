module Portfolio
  ( portfolioReturn
  , portfolioVolatility
  , sharpeRatio
  , covarianceMatrix
  , meanReturn
  , annualizedSharpe
  , precomputeMeans
  , fastAnnualizedSharpe
  ) where

import qualified Data.Vector.Unboxed as VU
import qualified Data.Vector         as V
import Types

-- ============================================================
-- FUNÇÕES PURAS — sem efeitos colaterais
-- ============================================================

-- | Retorno médio diário de cada ativo selecionado
--   Pré-calculado UMA VEZ por combinação; reutilizado em 1M simulações
precomputeMeans :: V.Vector (VU.Vector Double) -> [Int] -> VU.Vector Double
precomputeMeans allReturns selectedIdxs =
  let nDays = fromIntegral $ VU.length (allReturns V.! head selectedIdxs)
  in VU.fromList $ map (\i -> VU.sum (allReturns V.! i) / nDays) selectedIdxs

-- | Produto interno entre dois vetores unboxed (fusível com stream fusion)
{-# INLINE dotProduct #-}
dotProduct :: VU.Vector Double -> VU.Vector Double -> Double
dotProduct u v = VU.foldl' (+) 0.0 (VU.zipWith (*) u v)

-- | Sharpe anualizado usando médias pré-calculadas e covMatrix
--   retA   = dot(w, meanRets) * 252        (sem iterar 126 dias por simulação!)
--   sigmaA = sqrt(w^T * C * w * 252)
--   wTcw calculado com ifoldl' para evitar vetor intermediário Cw
{-# INLINE fastAnnualizedSharpe #-}
fastAnnualizedSharpe :: VU.Vector Double -> CovMatrix -> Weights -> SharpeResult
fastAnnualizedSharpe meanRets covMat weights =
  let retA   = dotProduct weights meanRets * 252.0
      wTcw   = VU.ifoldl' (\acc i wi ->
                 acc + wi * dotProduct (covMat V.! i) weights)
               0.0 weights
      sigmaA = sqrt (wTcw * 252.0)
      sr     = sharpeRatio retA sigmaA
  in SharpeResult { srSharpe = sr, srReturn = retA, srVol = sigmaA, srWeights = weights }

-- | Retorno diário da carteira: r_p[t] = sum_i w_i * r_i[t]
portfolioReturn :: V.Vector (VU.Vector Double) -> [Int] -> Weights -> VU.Vector Double
portfolioReturn allReturns selectedIdxs weights =
  let nDays    = VU.length (allReturns V.! head selectedIdxs)
      selected = map (allReturns V.!) selectedIdxs
  in VU.generate nDays $ \day ->
       sum $ zipWith (\retVec i -> (retVec `VU.unsafeIndex` day) * (weights `VU.unsafeIndex` i))
                     selected [0..]

-- | Retorno médio anualizado: mean(r_p) * 252
meanReturn :: VU.Vector Double -> Double
meanReturn rp =
  let n = VU.length rp
  in (VU.sum rp / fromIntegral n) * 252.0

-- | Matriz de covariância (pré-calculada uma vez por combinação)
covarianceMatrix :: V.Vector (VU.Vector Double) -> [Int] -> CovMatrix
covarianceMatrix allReturns selectedIdxs =
  let selected = V.fromList $ map (allReturns V.!) selectedIdxs
      n        = VU.length (selected V.! 0)
      nAssets  = V.length selected
      means    = V.map (\v -> VU.sum v / fromIntegral n) selected
      cov i j  =
        let mi = means V.! i
            mj = means V.! j
            vi = selected V.! i
            vj = selected V.! j
        in VU.sum (VU.zipWith (\a b -> (a - mi) * (b - mj)) vi vj) / fromIntegral (n - 1)
  in V.generate nAssets $ \i ->
       VU.generate nAssets $ \j -> cov i j

-- | Volatilidade diária: sigma = sqrt(w^T * C * w)
portfolioVolatility :: CovMatrix -> Weights -> Double
portfolioVolatility covMat weights =
  let wTcw = VU.ifoldl' (\acc i wi ->
               acc + wi * dotProduct (covMat V.! i) weights) 0.0 weights
  in sqrt wTcw

-- | Sharpe Ratio sem taxa livre de risco: SR = mu / sigma
sharpeRatio :: Double -> Double -> Double
sharpeRatio mu sigma
  | sigma <= 0 = -1e10
  | otherwise  = mu / sigma

-- | Sharpe anualizado via portfolioReturn (mantido para referência)
annualizedSharpe :: V.Vector (VU.Vector Double) -> [Int] -> CovMatrix -> Weights -> SharpeResult
annualizedSharpe allReturns selectedIdxs covMat weights =
  let rp     = portfolioReturn allReturns selectedIdxs weights
      mu     = meanReturn rp
      sigmaD = portfolioVolatility covMat weights
      sigmaA = sigmaD * sqrt 252.0
      sr     = sharpeRatio mu sigmaA
  in SharpeResult { srSharpe = sr, srReturn = mu, srVol = sigmaA, srWeights = weights }
