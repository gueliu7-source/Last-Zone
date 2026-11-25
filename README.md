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

- `main.gd` – mapa, itens, bots, HUD, qualidade automática
- `player.gd` – jogador em 3ª pessoa, tiro e recarga
- `bot.gd` – IA dos inimigos
- `zone.gd` – zona segura que fecha
- `fx.gd` – materiais leves e rastro de bala
- `font.ttf` – Liberation Sans Bold (licença SIL OFL)
