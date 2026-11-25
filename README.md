# Última Zona

Protótipo de battle royale 3D (inspirado em Free Fire) feito em **Godot 3.5 (GLES2)**,
pensado para rodar leve em PCs fracos (testado só no papel: meta de 60 fps em Core i5-2400 + Intel HD Graphics).

## Controles

| Tecla | Ação |
|---|---|
| WASD | Mover |
| Mouse | Mirar |
| Botão esquerdo | Atirar |
| Shift | Correr |
| Espaço | Pular |
| R | Recarregar |
| Esc | Pausar (soltar o mouse) |
| F11 | Tela cheia |
| F2 | Modo leve (liga/desliga) |

Cubos **verdes** = vida (+40) · Cubos **amarelos** = munição (+30)

## Como gerar o .exe sem instalar nada

1. Crie um repositório no GitHub e envie **todos** os arquivos desta pasta
   (o `project.godot` precisa ficar na raiz, e as pastas `.github`, `assets` e `scripts` vão junto).
2. Abra a aba **Actions**. O build roda sozinho a cada push
   (ou clique em *Build Windows (.exe)* → *Run workflow*).
3. Quando ficar verde (~2–4 min), clique na execução e baixe **UltimaZona-windows** em *Artifacts*.
4. Descompacte o zip e execute `UltimaZona.exe`.
   Se o Windows mostrar "SmartScreen": *Mais informações* → *Executar assim mesmo*.

## Por que roda em PC fraco

- **Godot 3.5 com renderizador GLES2**: funciona em GPUs Intel antigas (OpenGL 2.1).
- Renderiza em **960x540** e estica para a tela (1080p/tela cheia continua leve).
- Sem sombras, sem HDR, sem anti-aliasing; iluminação por vértice; um único tipo de luz.
- Personagens e árvores com poucos polígonos, materiais compartilhados.
- Névoa + distância de visão curta.
- **Contador de FPS** no topo. Se ficar abaixo de 50 fps por alguns segundos, liga sozinho o
  **modo leve** (visão mais curta, sem copas de árvore). F2 liga/desliga na mão.

Ainda estourando? Em `project.godot`, troque `window/size/width=960` e `height=540` por `854` e `480`.

## Estrutura

- `scripts/main.gd` – monta mapa, itens, bots, HUD, qualidade automática e fim de jogo
- `scripts/player.gd` – jogador em 3ª pessoa, tiro e recarga
- `scripts/bot.gd` – IA dos inimigos
- `scripts/zone.gd` – zona segura que fecha em 5 fases
- `scripts/fx.gd` – materiais leves e rastro de bala
- `assets/font.ttf` – Liberation Sans Bold (licença SIL OFL)
- `export_presets.cfg` + `.github/workflows/build.yml` – exportação automática para Windows
