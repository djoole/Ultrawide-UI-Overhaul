# Maintenance — Ultrawide UI Overhaul

Ce dépôt remplace les anciens dossiers World Map, controller-fix,
backpack-preinit et dual-uhd-test. Les branches et tags historiques sont
conservés. La branche courante contient les sources de la 2.5.10.
Inventory HUD et Scanner HUD restent des projets séparés.

## Sources et compilation

- `cet/UltrawideUIOverhaul/init.lua` : layouts et UI Spread.
- `cet/BlackPillarsCoordinator/init.lua` : coordination des piliers noirs.
- `native/src/BlackPillarsRemover.cpp` : hook et interface CET du plugin.
- `native/src/FitReferenceRectBoundary.asm` : conservation des registres du moteur.
- `native/build.ps1` : compilation avec Visual Studio C++ x64 et MASM.
- `native/deps/RED4ext.SDK` : SDK conservé localement, révision
  `5246e659d783e5834cc08a90e56c8932c9ed3449`.

Depuis la racine du dépôt :

```powershell
& .\native\build.ps1 -OutputPath 'native\build-2.5.10'
& .\native\tests\run.ps1
python diagnostics/run_all.py
```

Les tests Lua utilisent Python avec `lupa.lua54` (Lua 5.4). Les outils
d'analyse PE dans `tools/` utilisent Capstone. Les captures de test utiles
sont conservées dans `maintenance/ink-test-fixtures.zip`, sans extraction.
Cette archive est locale et ignorée par Git ; sur un autre poste, fournir
les captures via le dossier indiqué par `UWUI_INK_DUMP_DIR`.

## Éléments conservés localement

- `native/build-2.5.10/` : dernier binaire officiel et objets de compilation.
- `dist/Ultrawide-UI-Overhaul-v2.5.10.zip` : copie du ZIP publié, identique
  à celle du dossier de publication.
- `diagnostics/` : tests de régression du chargement, du Main Menu, des
  tooltips Cyberware, de Glam Doc et de Crafting.
- `tools/` : désassemblage PE et recherche de références aux chaînes pour
  retrouver les hooks après une mise à jour du jeu.
- `maintenance/recovery/` : ancien essai Backpack non commité sauvegardé
  sous forme de patch, avec sa révision de base ; petites sources natives
  historiques regroupées dans une archive. Ces fichiers sont obsolètes et
  ne participent pas à la compilation actuelle.
- `maintenance/cleanup-verification.json` : inventaire des références Git
  et vérifications effectuées lors de la consolidation du 17 novembre 2026.

Les trois anciens worktrees ont été supprimés. Les gros anciens ZIP de test,
copies de builds, captures abandonnées et sauvegardes de World Map ont été
regroupés à côté du dépôt dans `_A-SUPPRIMER-UltrawideUIOverhaul-20261117`.
Le contrôle automatique a refusé leur suppression définitive et Windows a
refusé leur passage à la Corbeille : ce dossier peut être supprimé manuellement.
Les archives de publication extérieures au dépôt et l'installation du jeu
sont conservées.

## Distribution

Le ZIP Nexus contient uniquement les deux `init.lua` et
`red4ext/plugins/BlackPillarsRemover/BlackPillarsRemover.dll`, avec leurs chemins
d'installation. Aucun README, log, réglage utilisateur ou fichier de test.
L'auteur public est `djoole`. Recompiler la DLL après toute modification de
ses sources ou métadonnées, puis reconstruire le ZIP.
