-- DUNGEON ZELDA (compacto): jogo de texto + teste de modelo (MBT) com Algoritmo Genético.
module Main where
import Data.Char (toLower)
import Data.List (intercalate, isPrefixOf, nub)
import System.Exit (exitSuccess)
import System.IO
import Text.Read (readMaybe)
-- 1. MODELO (cada regra tem um peso; na Armadilha, Voltar: Corredor 70 / Morte 30) ----------
data Estado = Entrada | Corredor | SalaSecreta | Armadilha | Tesouro | Morte deriving (Show, Eq, Enum, Bounded)
data Evento = Avancar | Explorar | Voltar | Renascer deriving (Show, Eq, Enum, Bounded)
type Transicao = (Estado, Evento, Estado)
type Individuo = [Evento]; type Semente = Int   -- Individuo: uma sequência de ações = um teste
modelo :: [(Transicao, Int)]
modelo = [ ((Entrada, Avancar, Corredor), 100), ((Entrada, Explorar, SalaSecreta), 100)
         , ((SalaSecreta, Voltar, Entrada), 100), ((Corredor, Explorar, Armadilha), 100)
         , ((Corredor, Avancar, Tesouro), 100), ((Corredor, Voltar, Entrada), 100)
         , ((Armadilha, Voltar, Corredor), 70), ((Armadilha, Voltar, Morte), 30)
         , ((Morte, Renascer, Entrada), 100) ]
todasTransicoes = map fst modelo
universo :: (Enum a, Bounded a) => [a]
universo = [minBound .. maxBound]
destinos s e = [(d, p) | ((o, ev, d), p) <- modelo, o == s, ev == e]
eventosValidos s = nub [e | ((o, e, _), _) <- modelo, o == s]
sorteio limite chave = (mix (mix chave) `div` 65536) `mod` limite
  where mix x = (1103515245 * (x `mod` 2147483648) + 12345) `mod` 2147483648
escolher :: Int -> [(Estado, Int)] -> Estado   -- seguro para lista vazia e pesos zero
escolher _ [] = Entrada
escolher chave ops@((p0, _) : _)
  | total <= 0 = p0
  | otherwise  = go (sorteio total chave) ops
  where total = sum (map snd ops)
        go v ((d, w) : r) | v >= w = go (v - w) r
                          | otherwise = d
eventoAleatorio chave = universo !! sorteio (length (universo :: [Evento])) chave
data Jogo = Jogo { posicao :: Estado, vidas, turnos :: Int, sementeJogo :: Semente
                 , historico :: [Evento] }   -- do mais recente ao mais antigo
data Desfecho = Invalido | Moveu Estado Estado
data Status = Jogando | Venceu | Perdeu deriving (Show, Eq)
novoJogo s = Jogo Entrada 3 0 s []
status j | posicao j == Tesouro = Venceu | vidas j <= 0 = Perdeu | otherwise = Jogando
passo :: Jogo -> Evento -> (Jogo, Desfecho)   -- evento inválido não muda nada nem gasta turno
passo j ev = case destinos (posicao j) ev of
  [] -> (j, Invalido)
  ops -> let d = escolher (sementeJogo j * 1000 + turnos j) ops
         in (j { posicao = d, vidas = vidas j - (if d == Morte then 1 else 0)
               , turnos = turnos j + 1, historico = ev : historico j }, Moveu (posicao j) d)
repetir :: Jogo -> [Evento] -> [(Evento, Desfecho, Jogo)]   -- para quando o jogo acaba
repetir j (e : es) | status j == Jogando = let (j', d) = passo j e in (e, d, j') : repetir j' es
repetir _ _ = []