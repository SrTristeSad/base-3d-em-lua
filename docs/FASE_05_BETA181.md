# Fase 5 — ciclo de dia e noite e luz ambiental

Referencia: Beta 1.8.1, em Lua/LÖVR 0.19.

- 24000 ticks por dia, 20 ticks por segundo (20 minutos reais).
- Amanhecer (0), meio-dia (6000), anoitecer (12000), meia-noite (18000).
- Cor do ceu e intensidade ambiental variaveis e suavizadas.
- HUD mostra dia, horario e fase; F7 avanca seis horas no Criativo.
- WORLDTIME persistido no save; saves anteriores carregam a partir de 0.
- Tempo avanca em jogo e com inventario, bancada ou fornalha abertos.
- Tempo pausa em menus, na tela de morte ou quando o jogo perde foco.
- Perfil Classic 0.30 permanece inalterado.

**Limites:** Esta fase nao implementa luz por bloco: faltam fontes locais
(tochas, fornalhas e lava), oclusao/cavernas, sol e lua renderizados
e spawn de mobs dependente de brilho. Nao e ainda fidelidade 1:1.
A iluminacao e uma modulacao global das malhas; a aparencia real ainda
precisa ser validada em Windows com Vulkan.

Testes: `lua5.4 tests/beta181_daylight.lua`
