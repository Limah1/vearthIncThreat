# Guia de Desenvolvimento & Balanceamento - IdleSpaceCpp

Este documento consolida o **Guia de Desenvolvimento (C++/Blueprint)** e o **Guia de Balanceamento de Upgrades**, servindo como manual unificado para expansão de conteúdo e calibração matemática do jogo.

---

## PARTE 1: GUIA DE DESENVOLVIMENTO (C++)

O projeto utiliza uma arquitetura híbrida C++/Blueprint focada em alta performance e expansibilidade rápida.

### 1. Sistema de Pooling (`UObjectPoolSubsystem`)
Todos os objetos dinâmicos voadores (Lixo Espacial, Asteroides, Inimigos, Projéteis e Debris) **NUNCA** devem ser instanciados com `SpawnActor` ou destruídos com `DestroyActor`. Em vez disso:
* Use `Pool->BorrowFromPool(Class, Transform)` para ativar um objeto.
* Use `Pool->ReturnToPool(Actor)` para reciclar um objeto.
* **Regras Rígidas de C++**:
  - `OnPoolActivate()`: Reinicie escalas, velocidades, HP e estados visuais aqui.
  - `OnPoolDeactivate()`: Pare todos os emissores de partículas, efeitos sonoros e limpe timers ativos para evitar memory leaks.
  - `ApplyDamage()`: Ponto centralizado para aplicar dano, reações de impacto (câmera shake), efeitos de slow (desaceleração) e checagem de morte.

### 2. Fluxo para Adicionar Novo Conteúdo

#### A. Adicionar um Novo Asteroide (Recurso)
1. Crie um novo Data Asset baseado na classe `ResourcesDA` no editor Unreal.
2. Configure a malha visual (Mesh), Pontos de Vida (HP), Valor Monetário (Value) e Velocidade base.
3. Para incluí-lo nas ondas: abra o Data Asset `DA_SpawnConfig` (na pasta Data) e adicione seu novo Data Asset nos slots de onda desejados.

#### B. Adicionar uma Nova Nave Inimiga
1. Crie um novo Data Asset do tipo `SpaceshipDA`.
2. Configure a malha 3D e seus status de combate (Cadência de Tiro, Classe do Projétil, Raio de Órbita).
3. Adicione este Data Asset no `DA_SpawnConfig` para colocá-lo na fila de spawn das waves.

#### C. Adicionar um Novo Upgrade no Jogo
1. **Passo C++**: Se precisar de um status ou multiplicador inédito, adicione um novo termo ao enum `EUpgradeCategory` no arquivo `EUpgradeCategory.h`.
2. **Passo Data Asset**: Crie um novo Data Asset do tipo `DAUpgrades`. Configure o Nome, Ícone, Categoria de Upgrade (enum) e a lógica de incremento/porcentagem.
3. **Passo UI**: Insira o widget `WBP_UpgradeNode` no Canvas da Skill Tree e atribua este Data Asset a ele.

#### D. Adicionar um Novo Projétil
1. Crie um Blueprint herdando de `DebrisProjectile` ou `APlayerProjectile`.
2. Configure a malha, colisor e velocidade.
3. Associe a nova classe de blueprint ao slot 'Projectile Class' em um Satélite ou recurso configurado em Data Assets.

---

## PARTE 2: GUIA DE BALANCEAMENTO E MATEMÁTICA

### 1. A Nova Matemática Unificada
O jogo opera com um **Multiplicador Base de `1.0` (100%)**.
Cada nível de upgrade soma um bônus a esse multiplicador base.
A fórmula final aplicada aos status base dos atores é:
$$\text{StatusFinal} = \text{StatusBase} \times (1.0f + \text{Soma dos Bônus})$$

O cálculo do bônus individual de cada classe `DAUpgrades` é determinado pelo nível efetivo ($N = \text{Level} \times \text{InternalLevel}$):

* **Linear (`bIsPercentage = false`)**:
  $$\text{Bônus} = \text{ValueIncrement} \times N$$
  > [!NOTE]
  > Exemplo com Incremento 0.5, InternalLevel 1:
  > * Nível 1 = +0.5 multiplicador
  > * Nível 2 = +1.0 multiplicador

* **Composto/Exponencial (`bIsPercentage = true`)**:
  $$\text{Bônus} = (1.0f + \text{ValueIncrement})^{N} - 1.0f$$
  > [!NOTE]
  > Exemplo com Incremento 0.2, InternalLevel 1:
  > * Nível 1 = +0.2 multiplicador
  > * Nível 2 = +0.44 multiplicador

---

### 2. Recomendações de Ajuste por Categoria

Abaixo está a tabela de calibração para orientar o design das árvores de upgrades:

| Categoria | Tipo de Progressão | Incremento Sugerido (`ValueIncrement`) | Motivo e Recomendações |
| :--- | :---: | :---: | :--- |
| **Dano de Clique** (`ClickDamage`) | Linear ou Composto | Linear: `1.0`<br>Composto: `0.15 - 0.20` | Use Composto se o HP dos inimigos escalar exponencialmente no Late Game. Caso contrário, Linear lineariza o dano de forma segura. |
| **Velocidade de Auto-Click** (`AutoClickRate`) | Composto (Recomendado) | `0.10 - 0.15` | **Combate Retornos Decrescentes**: O intervalo é `Base / Multiplicador` ($1/x$). A fórmula Linear causa sensação de estagnação rápida. Composto mantém o progresso impactante até o limite físico de **0.05s**. |
| **Raio de Clique** (`ClickRadius`) | Linear | `0.10 - 0.15` | Defina um `MaxPurchases` baixo (ex: 5 a 10) para evitar que o clique cubra toda a extensão da tela de jogo. |
| **Vida/Escudo do Planeta** (`PlanetHealth` / `ShieldHP`) | Composto | `0.20 - 0.30` | Inimigos escalam dano de forma agressiva. A sobrevivência do planeta exige juros compostos nos níveis mais avançados. |
| **Multiplicador de Recursos** (`ResourceMultiplier`) | Linear ou Composto | Linear: `0.10 - 0.20`<br>Composto: `0.10 - 0.15` | Se os preços da loja forem fixos, use Linear. Se os preços dos upgrades escalarem a cada compra, use Composto para compensar a inflação. |
| **Quantidades Exatas** (Ex: `SatelliteAmount`, `GarbageAmount`) | **Obrigatório Linear** | `1.0` | **IMPORTANTE**: Essas categorias não representam taxas, mas contagens diretas. Multiplicadores não-inteiros são arredondados para baixo (ex: 1.8 satélites vira 1). Use sempre `bIsPercentage = false` e incremento `1.0`. |

---

### 3. Dicas Rápidas de Design de Árvore

> [!WARNING]
> **Cuidado com Juros Compostos Altos**:
> Evite usar `bIsPercentage = true` combinando com `ValueIncrement > 0.5`. Por exemplo, $(1.5)^{10} \approx 57.6$. Um upgrade de 10 níveis com $50\%$ de taxa multiplicaria o status original por 57 vezes, quebrando completamente a economia e o balanceamento das fases avançadas. Mantenha taxas compostas estritamente entre `0.05` e `0.25`.

1. **Early Game (Upgrades Iniciais)**: Utilize valores menores de incremento linear para proporcionar um senso de progresso gradual.
2. **Late Game (Upgrades Finais)**: Mantenha os mesmos incrementos básicos, mas aproveite o empilhamento das árvores que somam seus bônus na mesma categoria para criar picos de poder perceptíveis.
3. **Frequência de Ondas**: Cadências de spawn de inimigos (`SpawnRate`) possuem limite mínimo de **0.2s** entre ondas. Evite reduzir muito este valor para não sobrecarregar a CPU com excesso de atores simultâneos na tela.
