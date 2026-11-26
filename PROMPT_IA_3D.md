# Briefing para a IA de 3D (copie o texto abaixo da linha e cole na outra IA)

> Dica para você: muitas IAs de 3D só geram o modelo parado, sem esqueleto e com muitos polígonos.
> Se for o caso, gere só o corpo e use o **Mixamo** (gratuito) para colocar esqueleto e animações,
> e o **Blender** para reduzir polígonos e exportar em `.glb`. Os requisitos abaixo servem para os dois caminhos.

---

Preciso de um personagem 3D **estilo anime (cel-shaded)** para um jogo de tiro em terceira pessoa que roda em PC fraco (placa de vídeo integrada Intel HD). Siga exatamente estas especificações.

## Modelo
- **Formato: `.glb` (glTF binário)**, um arquivo só, com textura embutida.
- **Máximo de 4.000 triângulos** (alvo: 3.000). Cabeça, corpo, roupa e cabelo juntos. Sem arma no modelo.
- **Uma única malha e um único material**, com **uma única textura de 512x512** (no máximo 1024x1024).
- Textura só de **cor base** (pintura chapada, estilo anime). **Sem** normal map, sem mapa de metal/rugosidade, sem emissão, sem vertex color.
- **Normais suaves (smooth shading) em todo o modelo.** Não use flat shading nem arestas duras divididas: o contorno preto é feito pelo jogo e quebra se as normais forem divididas.
- **Não desenhe contorno preto no modelo nem na textura.** O jogo adiciona o contorno e o sombreado de desenho sozinho.
- Proporção realista de anime, **1,75 m de altura**, **pés em Y = 0**, personagem de pé em T-pose ou A-pose.
- **Y para cima, unidades em metros, olhando para +Z.** Aplique todas as transformações antes de exportar (escala 1, rotação 0, posição 0).

## Esqueleto
- Esqueleto humanoide com **no máximo 40 ossos**, **no máximo 4 ossos influenciando cada vértice**.

## Animações (nomes exatos, minúsculos, dentro do mesmo `.glb`)
| Nome | Duração | Loop | Descrição |
|---|---|---|---|
| `idle` | ~2 s | sim | parado, respirando, segurando um rifle na frente do corpo (sem o rifle) |
| `run` | ~0,7 s | sim | correndo para a frente, braços na posição de segurar um rifle |
| `shoot` | ~0,3 s | não | disparando um rifle: recuo curto, braços apontando para a frente |
| `death` | ~1,5 s | não | caindo para trás, terminando deitado no chão |

Todas a 30 fps, começando e terminando no mesmo ponto quando forem em loop.

## Entrega
- `player.glb`: o personagem do jogador.
- `bot.glb`: um segundo personagem (outro visual) com **o mesmo esqueleto e as mesmas animações**. Se não der, pode ser uma cópia do primeiro com outra cor de roupa e cabelo.
