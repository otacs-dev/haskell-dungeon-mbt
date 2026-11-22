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
mensagem _ Invalido = "Nada aconteceu."
mensagem j (Moveu de para)
  | para == Morte = "A armadilha disparou! Você morreu. Vidas restantes: " ++ show (vidas j)
  | de == Morte = "Você renasceu na Entrada."
  | para == Tesouro = "Você encontrou o Tesouro!"
  | otherwise = "Você foi de " ++ show de ++ " para " ++ show para ++ "."
data Comando = Sair | Ajuda | Mapa | Vazio | Fazer Evento | Ambiguo [Evento] | QuisDizer [Evento]
             | Desconhecido deriving (Show, Eq)
-- 4. DIGITAÇÃO: minúsculo, sem acentos, sem espaços sobrando
normalizar = map (\c -> maybe c id (lookup c (zip "áàâãäéèêëíìîïóòôõöúùûüç" "aaaaaeeeeiiiiooooouuuuc")) ) . map toLower . unwords . words
interpretar :: String -> Comando
interpretar texto
  | n == "" = Vazio
  | n `elem` ["sair", "s"] = Sair
  | n `elem` ["ajuda", "?", "h"] = Ajuda
  | n `elem` ["mapa", "m"] = Mapa
  | otherwise = case [e | e <- universo, n `isPrefixOf` nome e] of
      [e] -> Fazer e   -- "av" ou "a" -> Avancar
      [] -> case [e | e <- universo, diferencas (nome e) <= 2] of { [] -> Desconhecido; ps -> QuisDizer ps }
      muitos -> Ambiguo muitos
  where n = normalizar texto
        nome = normalizar . show
        diferencas p = length [() | (x, y) <- zip n p, x /= y] + abs (length n - length p)   -- "voltra" x "voltar" = 2
nomes = intercalate " ou " . map show
-- 5. MAPA (largura calculada: barras sempre alinhadas; sala nova => acrescentar em desenharMapa)
centralizar n t = replicate esq ' ' ++ t ++ replicate (folga - esq) ' '
  where { folga = max 0 (n - length t); esq = folga `div` 2 }
desenharMapa :: Estado -> [String]
desenharMapa atual = [cel SalaSecreta, ponte, cel Entrada ++ elo ++ cel Corredor ++ elo ++ cel Tesouro
                     , ponte ++ replicate 5 ' ' ++ ponte, cel Morte ++ elo ++ cel Armadilha]
  where larg = maximum (map (length . show) (universo :: [Estado])) + 4
        cel s = "[" ++ centralizar (larg - 2) (if s == atual then "*" ++ show s ++ "*" else show s) ++ "]"
        (elo, ponte) = (" --- ", centralizar larg "|")
-- 6. COBERTURA (a Armadilha depende de sorte: acompanhamos TODOS os lugares possíveis)
passoDoTeste :: ([Estado], [Transicao]) -> Evento -> ([Estado], [Transicao])
passoDoTeste (lugares, usadas) ev = (nub ([s | s <- lugares, null (destinos s ev)] ++ [d | (_, _, d) <- feitas]), nub (usadas ++ feitas))
  where feitas = [(s, ev, d) | s <- lugares, (d, _) <- destinos s ev]
simularTeste :: [Evento] -> ([Estado], [Transicao])   -- (estados visitados, transições usadas)
simularTeste evs = (nub (Entrada : [d | (_, _, d) <- usadas]), usadas)
  where usadas = snd (foldl passoDoTeste ([Entrada], []) evs)
cobertura :: Eq a => [a] -> [a] -> Double
cobertura univ vis = 100 * fromIntegral (length (nub vis)) / fromIntegral (length univ)
arredondar x = fromIntegral (round (x * 10) :: Int) / 10
-- 7. ALGORITMO GENÉTICO ---------------------------------------------------------------------
tamPop, geracoes, tamTorneio, taxaMutacao, tamMax :: Int
tamPop = 40; geracoes = 60; tamTorneio = 3; taxaMutacao = 25; tamMax = 14
avaliar :: Individuo -> Double   -- premia cobertura; desconta 0,5 por evento (testes curtos ganham)
avaliar ind = 0.4 * cobertura universo es + 0.6 * cobertura todasTransicoes ts - 0.5 * fromIntegral (length ind)
  where (es, ts) = simularTeste ind
melhor [] = []
melhor xs = foldl1 (\a b -> if avaliar a >= avaliar b then a else b) xs
torneio :: [Individuo] -> Int -> Individuo   -- sorteia 3 testes e devolve o melhor
torneio pop chave = melhor [pop !! sorteio (length pop) (chave + k) | k <- [1 .. tamTorneio]]
filhosDoCasal :: [Individuo] -> Int -> [Individuo]   -- cruzamento + mutação (25%)
filhosDoCasal pop chave = [mutar (chave + 50) (ia ++ fb), mutar (chave + 60) (ib ++ fa)]
  where paiA = torneio pop chave
        paiB = torneio pop (chave + 10)
        (ia, fa) = splitAt (sorteio (length paiA + 1) (chave + 20)) paiA
        (ib, fb) = splitAt (sorteio (length paiB + 1) (chave + 21)) paiB
        mutar c filho
          | null f || sorteio 100 c >= taxaMutacao = f
          | otherwise = take p f ++ [eventoAleatorio (c + 2)] ++ drop (p + 1) f
          where f = take tamMax filho
                p = sorteio (length f) (c + 1)
executarAG s = [(g, melhor p) | (g, p) <- zip [0 .. geracoes] pops]
  where pops = scanl proxima [ind i | i <- [1 .. tamPop]] [0 ..]
        ind i = [eventoAleatorio ((s * 1000 + i) * 31 + k) | k <- [1 .. 4 + sorteio 6 (s * 1000 + i)]]
        proxima p g = melhor p : take (tamPop - 1) (concat [filhosDoCasal p (s * 10000000 + g * 10000 + i * 100) | i <- [1 .. tamPop `div` 2]])
perguntar :: String -> IO String   -- se a entrada acabar (Ctrl+D), encerra sem erro
perguntar t = putStr t >> isEOF >>= \fim ->
  if fim then putStrLn "\nEntrada encerrada. Até a próxima!" >> exitSuccess else getLine
aviso t = putStrLn ("\n  [!] " ++ t ++ "\n")
perguntarSemente :: IO Semente
perguntarSemente = do
  t <- unwords . words <$> perguntar "Semente (número inteiro, Enter = 42): "
  case (t, readMaybe t) of
    ("", _) -> return 42
    (_, Just n) -> return (n `mod` 2147483648)
    _ -> aviso ("\"" ++ t ++ "\" não é um número inteiro. Tente de novo.") >> perguntarSemente
descreverEvento s e
  | length ops <= 1 = show e
  | otherwise = show e ++ " (" ++ intercalate " / " [show (p * 100 `div` sum (map snd ops)) ++ "% " ++ show d | (d, p) <- ops] ++ ")"
  where ops = destinos s e
mostrarMapa = mapM_ (putStrLn . ("  " ++)) . desenharMapa
jogar j = case status j of
  Venceu -> putStrLn "\n  *** Você chegou ao Tesouro! Vitória! ***" >> return j
  Perdeu -> putStrLn "\n  *** Suas vidas acabaram. Fim de jogo. ***" >> return j
  Jogando -> do
    putStrLn "" >> mostrarMapa (posicao j)
    putStrLn ("\n  Vidas: " ++ show (vidas j) ++ "   Turnos: " ++ show (turnos j) ++ "   (* = você está aqui)")
    putStrLn ("  Opções: " ++ intercalate ", " (map (descreverEvento (posicao j)) (eventosValidos (posicao j))))
    lerComando j
lerComando j = do
  linha <- perguntar "\n> "
  let de = lerComando j
      avisar t = aviso t >> de
      validos = eventosValidos (posicao j)
  case interpretar linha of
    Sair -> putStrLn "\n  Partida encerrada." >> return j
    Vazio -> de
    Ajuda -> putStrLn "\n  Comandos: avancar (a), explorar (e), voltar (v), renascer (r), mapa (m), ajuda (?), sair (s).\n  Maiúsculas, acentos e espaços não importam; abreviações e pequenos erros são aceitos." >> de
    Mapa -> putStrLn "" >> mostrarMapa (posicao j) >> de
    Ambiguo es -> avisar ("Pode ser " ++ nomes es ++ ". Digite mais letras.")
    QuisDizer es -> avisar ("Não entendi. Você quis dizer: " ++ nomes es ++ "?")
    Desconhecido -> avisar "Não conheço esse comando. Digite 'ajuda'."
    Fazer e
      | e `elem` validos -> let (j', d) = passo j e in putStrLn ("\n  " ++ mensagem j' d) >> jogar j'
      | otherwise -> avisar (show e ++ " não funciona em " ++ show (posicao j) ++ ". Opções: " ++ intercalate ", " (map show validos))
modoJogo = do
  s <- perguntarSemente
  putStrLn ("\nSemente " ++ show s ++ ". Você tem 3 vidas. Digite 'ajuda' se precisar.")
  f <- jogar (novoJogo s)
  putStrLn ("\nResumo: " ++ show (turnos f) ++ " turnos, " ++ show (vidas f) ++ " vidas restantes.\n  Sequência jogada: "
            ++ show (reverse (historico f)) ++ "\n  Para repetir: opção 3, semente " ++ show s ++ ".")
modoReproduzir = do
  s <- perguntarSemente
  ps <- words . map (\c -> if c `elem` ",;[]" then ' ' else c) <$> perguntar "Eventos (ex.: avancar, explorar, voltar): "
  let ents = [(p, interpretar p) | p <- ps]
      evs = [e | (_, Fazer e) <- ents]
      erros = [p | (p, c) <- ents, c `notElem` map Fazer (universo :: [Evento])]
      passos = repetir (novoJogo s) evs
      ultimo = if null passos then novoJogo s else (\(_, _, x) -> x) (last passos)
  if null ps then aviso "Nenhum evento informado."
  else if not (null erros) then aviso ("Não entendi: " ++ intercalate ", " erros)
  else do
    mapM_ (\(n, (e, d, x)) -> putStrLn ("  " ++ show n ++ ". " ++ show e ++ ": " ++ mensagem x d)) (zip [1 :: Int ..] passos)
    putStrLn ("\n  Resultado: " ++ show (status ultimo) ++ ", em " ++ show (posicao ultimo) ++ ", com " ++ show (vidas ultimo) ++ " vida(s).")
    if length passos < length evs then putStrLn "  (O jogo terminou antes do fim da sequência.)" else return ()
modoAG = do
  s <- perguntarSemente
  let evolucao = executarAG s
      best = snd (last evolucao)
      (es, ts) = simularTeste best
  putStrLn "\nEvolução da nota do melhor teste:"
  mapM_ (\(g, i) -> putStrLn ("  geração " ++ show g ++ ": " ++ show (arredondar (avaliar i)) ++ "  " ++ show i)) [x | x@(g, _) <- evolucao, g `mod` 10 == 0]
  putStrLn ("\nMelhor sequência de teste:\n" ++ show best)
  putStrLn ("Cobertura de estados:    " ++ show (arredondar (cobertura universo es)) ++ "%\nCobertura de transições: "
            ++ show (arredondar (cobertura todasTransicoes ts)) ++ "%")
  putStrLn ("Nota final:              " ++ show (arredondar (avaliar best)) ++ "\n\nPara jogar esta sequência, use a opção 3 e cole:\n  " ++ show best)
menu = do
  mapM_ putStrLn ["\n=== Dungeon Zelda ===", "  1) Jogar a dungeon", "  2) Gerar testes com o Algoritmo Genético"
                 , "  3) Reproduzir uma sequência de eventos", "  0) Sair"]
  r <- perguntar "Escolha: "
  case normalizar r of
    "1" -> modoJogo >> menu
    "2" -> modoAG >> menu
    "3" -> modoReproduzir >> menu
    "0" -> putStrLn "Até a próxima!"
    "" -> menu
    _ -> aviso "Opção inválida. Digite 1, 2, 3 ou 0." >> menu
main = hSetEncoding stdout utf8 >> hSetEncoding stdin utf8 >> hSetBuffering stdout NoBuffering >> menu
