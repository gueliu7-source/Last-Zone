# Última Zona

Protótipo de battle royale 3D (inspirado em Free Fire) feito em **Godot 3.5 (GLES2)**,
pensado para rodar leve em PCs fracos (meta: 60 fps em Core i5-2400 + Intel HD Graphics).

## Controles

WASD mover · Mouse mirar · Botão esquerdo atirar · Shift correr · Espaço pular · R recarregar ·
Esc pausar · F11 tela cheia · F2 modo leve

Cubos verdes = vida (+40) · Cubos amarelos = munição (+30)

## Como gerar o .exe

1. Envie todos os arquivos desta pasta para a raiz de um repositório no GitHub
   (não tem subpastas; só falta criar `.github/workflows/build.yml`, que vem num arquivo separado).
2. Aba **Actions** → o build roda sozinho (ou *Run workflow*).
3. Baixe **UltimaZona-windows** em *Artifacts* e execute `UltimaZona.exe`.

## Arquivos

- `main.gd` – carrega a ilha, itens, bots, HUD, qualidade automática
- `island.glb` – mapa da ilha (terreno + construções + árvores, cor por vértice; gerado em código)
- `map_data.gd` – colisores, itens, pontos de spawn e nomes das regiões do mapa
- `player.gd` – jogador em 3ª pessoa, tiro e recarga
- `bot.gd` – IA dos inimigos
- `zone.gd` – zona segura que fecha
- `fx.gd` – materiais leves e rastro de bala
- `font.ttf` – Liberation Sans Bold (licença SIL OFL)

## Modelos 3D

`player.glb` é o personagem **Kael** (estilo anime, 4.000 triângulos, textura 1024x1024, 17 ossos)
com as animações `idle`, `run`, `shoot` e `death`. O jogo aplica **contorno preto** (`outline.shader`)
e **sombreado de desenho** (`cel.shader`) sozinho. Os bots usam o mesmo modelo com uma cor diferente;
para dar outro visual aos bots, coloque um `bot.glb` ao lado (mesmos nomes de animação).
Sem nenhum `.glb`, o jogo usa os bonecos simples.

Ajustes rápidos (em `player.gd` e `bot.gd`):
- `MODEL_YAW`: se o personagem aparecer de costas, troque 180.0 por 0.0.
- `OUTLINE_WIDTH`: espessura do contorno (0.02 = 2 cm).
- `GUN_POS_MODEL`: posição da arma na frente do personagem.
Especificações para gerar outros modelos: veja `PROMPT_IA_3D.md`.

## Mapa

Ilha de ~330 m com 8 regiões: **Cidade** (centro), **Base Militar**, **Fábrica**, **Vila**, **Porto**,
**Fazenda**, **Colina** (torre no topo) e **Floresta**, ligadas por estradas. O nome da região aparece
no topo da tela. Zona segura começa com raio 150 m e fecha em 6 fases.
Os prédios são blocos sólidos (sem interior). O mapa é pequeno em triângulos (~24 mil) para manter 60 fps.
