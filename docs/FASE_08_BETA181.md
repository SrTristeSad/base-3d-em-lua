# Fase 8 — cache de skylight por seções e medições

## Problema da Fase 7

O cache solar armazenava até 12.000 resultados por voxel. Ao atingir
o limite, **apagava todos**, mesmo os das áreas próximas ao jogador.
A travessia de uma borda de chunk também zerava os resultados.
Isso provocava buscas BFS repetidas, especialmente em cavernas.

## O que mudou

- Resultados organizados por seções 16×16×16 com índices numéricos.
- Capacidade total configurável, padrão 12.000 entradas.
- Evicção da seção menos recentemente usada (LRU) em vez de zerar
  todo o cache; uma seção individual pode temporariamente ultrapassar
  o limite se não houver outra a descartar.
- Travessias entre chunks preservam dados de seções adjacentes.
- Edições opacas invalidam somente as seções alcançáveis na horizontal
  pela propagação solar (14 blocos) em todas as alturas, permitindo
  mudanças em poços profundos sem apagar caches distantes.
- Consultas para blocos opacos armazenam nível zero, evitando
  leitura repetida do bloco.
- No painel F3 aparecem entradas armazenadas, seções, acertos
  de cache e nós BFS visitados desde a inicialização.
- Saves existentes, ciclo de dia e noite, fornalhas, mobs,
  luz de tochas e perfil Classic são preservados.

## Testes e limitações

`lua5.4 tests/beta181_light_cache.lua` valida reutilização,
fronteiras negativas, evicção, invalidar coluna, tempo e fontes.
A regressão completa das fases anteriores deve continuar verde.

A mudança reduz recomputações evitáveis, **não comprova
determinado aumento de FPS**. Ainda são necessárias medições
em Windows com Vulkan e avaliação de picos do BFS em túneis.
O motor permanece independente e ainda não é fiel 1:1 à Beta 1.8.1.
