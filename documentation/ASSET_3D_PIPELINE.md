# Padrão de assets 3D

## Contrato

Torres e inimigos usam `VisualAsset3D`, um Resource compartilhado que aponta para um prefab visual e guarda somente ajustes de apresentação:

- `scene`: prefab com raiz `Node3D`.
- `scale`, `rotation_degrees`, `offset`: normalização sem alterar o arquivo importado.
- `aim_pivot_path`: pivô horizontal de arma, obrigatório para torres.
- `muzzle_path`: origem de tiro, obrigatória para torres.
- `supports_instance_color`: indica compatibilidade do material com cor por instância.
- `cast_shadow`: política explícita de sombra.

Vida, dano, raio de colisão, footprint, alcance e velocidade não pertencem ao asset visual. Continuam em `EnemyData` ou `TurretConfig`.

## Pastas

```text
src/assets/3d/                         arquivos importados existentes
src/assets/3d/prefabs/enemies/        prefabs normalizados de inimigos
src/assets/3d/prefabs/turrets/        prefabs normalizados de torres
src/resources/visuals/enemies/        perfis VisualAsset3D de inimigos
src/resources/visuals/turrets/        perfis VisualAsset3D de torres
src/resources/enemies/                EnemyData
src/resources/turrets/                TurretConfig
```

Não editar transformação do FBX/GLB original para corrigir somente um ator. Fazer a correção no prefab ou no perfil mantém o source reutilizável.

## Coordenadas e cena

- Eixo vertical: `+Y`.
- Frente de gameplay: `+Z`; yaw zero aponta para `+Z`.
- Inimigo: origem no centro do volume visual.
- Torre: origem no centro da base e base apoiada em `Y = 0`.
- Aplicar transformações no editor antes da exportação quando possível. O prefab/perfil cobre diferenças inevitáveis do source.

Prefab mínimo de inimigo:

```text
EnemyVisual (Node3D)
└── Model (MeshInstance3D ou subcena importada)
```

Prefab mínimo de torre:

```text
TurretVisual (Node3D)
└── AimPivot (Node3D)
    ├── Body (MeshInstance3D)
    └── Muzzle (Marker3D)
```

`AimPivot` deve girar todo o conjunto apontável. `Muzzle` deve ficar na saída da arma e acompanha o pivô. Nomes podem variar porque os caminhos ficam no `VisualAsset3D`, mas manter esses nomes facilita revisão.

## Inimigos

1. Colocar FBX/GLB em `src/assets/3d/`.
2. Criar prefab em `prefabs/enemies/`, ajustar orientação, escala e origem.
3. Criar `VisualAsset3D` em `resources/visuals/enemies/`.
4. Marcar `supports_instance_color` quando o material aceita cor de instância.
5. Referenciar o perfil em `EnemyData.visual_asset`.
6. Configurar gameplay no `EnemyData` e adicionar esse recurso ao roster do LevelConfig.

O renderer instancia o prefab somente para extrair meshes, materiais e transformações. Depois o libera e renderiza todos os inimigos do arquétipo por `MultiMesh`. Scripts, colisores, luzes, áudio e partículas dentro do prefab não viram comportamento individual. Evitar esses nós em inimigos mass.

Cada `MeshInstance3D` do prefab cria um batch por arquétipo. Para 10.000 inimigos, preferir um mesh, poucos surfaces, material simples e sombras desligadas. `BaseMaterial3D` recebe HP/flash automaticamente. Shader customizado precisa ler a cor da instância.

## Torres

1. Colocar modelo em `src/assets/3d/` e criar prefab em `prefabs/turrets/`.
2. Criar `AimPivot` e `Muzzle` conforme o contrato.
3. Criar `VisualAsset3D` em `resources/visuals/turrets/` e preencher os dois caminhos.
4. Referenciar o perfil em `TurretConfig.visual_asset`.
5. Usar uma cena de comportamento (`defense_blaster.tscn`, `laser_turret.tscn`, `turret_miner.tscn` ou outra classe).

A torre instancia o prefab uma vez. Mira gira `AimPivot`; projétil, laser e mina usam a posição global do `Muzzle`. Preview de posicionamento aplica material fantasma a todos os meshes do prefab e restaura os overrides originais ao terminar.

Trocar somente `visual_asset` troca aparência sem duplicar scripts ou números de combate. Um comportamento novo ainda exige uma cena/script de torre, mas pode reutilizar qualquer perfil compatível.

## Assets migrados

- Asteroides pequeno, médio e grande usam prefabs que encapsulam os FBX existentes e preservam as escalas 90/140/220.
- Nave atacante usa `enemy_spaceship_3d.tscn` através de um perfil visual.
- Blaster, laser e miner usam prefabs próprios com `AimPivot` e `Muzzle`.
- Campos legados `EnemyData.visual_scene` e `visual_scale` permanecem como fallback para recursos externos ainda não migrados.

## Validação

`VisualAsset3D.get_validation_errors()` verifica cena instanciável, raiz `Node3D`, transformação finita, escala positiva e caminhos válidos. Inimigos também exigem pelo menos um `MeshInstance3D`. `TurretConfig.get_visual_validation_errors()` exige pivô e muzzle.

Executar:

```powershell
.\tests\run_mass_enemy_tests.ps1 -GPU
```

A suíte cobre recursos migrados, erros de caminho/escala, instanciação, resolução de marcadores, rotação do pivô, origem de tiro, preview, extração `MultiMesh` e gameplay das torres.
