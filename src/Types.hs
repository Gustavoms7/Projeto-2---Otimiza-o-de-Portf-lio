module Types
  ( DailyReturns
  , Weights
  , CovMatrix
  , SharpeResult(..)
  , CombinationResult(..)
  ) where

import qualified Data.Vector.Unboxed as VU
import qualified Data.Vector         as V
import Control.DeepSeq (NFData(..))

-- | Vetor de retornos diários de um ativo
type DailyReturns = VU.Vector Double

-- | Vetor de pesos da carteira
type Weights = VU.Vector Double

-- | Matriz de covariância (vetor de vetores)
type CovMatrix = V.Vector (VU.Vector Double)

-- | Resultado de uma simulação individual de pesos
data SharpeResult = SharpeResult
  { srSharpe  :: !Double
  , srReturn  :: !Double
  , srVol     :: !Double
  , srWeights :: !Weights
  } deriving (Show)

instance NFData SharpeResult where
  rnf (SharpeResult s r v w) = s `seq` r `seq` v `seq` VU.length w `seq` ()

-- | Resultado da melhor carteira de uma combinação de ações
data CombinationResult = CombinationResult
  { crStocks  :: ![Int]       -- ^ Índices das ações escolhidas
  , crBest    :: !SharpeResult -- ^ Melhor resultado encontrado
  } deriving (Show)

instance NFData CombinationResult where
  rnf (CombinationResult s b) = rnf s `seq` rnf b `seq` ()
