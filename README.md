![C#](https://img.shields.io/badge/c%23-%23239120.svg?style=for-the-badge&logo=csharp&logoColor=white)
![.NET 10](https://img.shields.io/badge/.NET-512BD4?style=for-the-badge&logo=dotnet&logoColor=white)
![WPF](https://img.shields.io/badge/WPF-blue?style=for-the-badge)
![GitHub Open Source](https://img.shields.io/badge/Open%20Source-%E2%9D%A4-red?style=for-the-badge)
# Game on Launcher

Launcher de Minecraft para **macOS, Windows e Android**. Reúne gestão de instâncias e
loaders, pesquisa e transferência de mods e modpacks (CurseForge e Modrinth), centro de
servidor Paper/Fabric/Forge/NeoForge com consola e plugins, registos da instância,
preferências de Java/memória, temas, modo streamer e vídeo de fundo em loop.

O projeto tem **três implementações** que partilham a mesma linguagem visual e as mesmas
funcionalidades:

| | macOS | Windows / Linux | Android |
| --- | --- | --- | --- |
| Implementação | SwiftUI nativa | Electron (HTML/CSS/JS) | Capacitor (WebView) |
| Pasta | `Sources/` | `desktop/` | `mobile/` |
| Compilar | `./build-macos.sh` | `cd desktop && npm run build:win` | `cd mobile && ./build-android.sh` |
| Resultado | `build/GameOnLauncher.app` | `desktop/dist/*.exe` | `build/android/*.apk` |

---

## Android — APK

### Compilar

```sh
cd mobile
npm install
npx cap sync android          # copia o código para o projeto Android
./build-android.sh release    # ou: ./build-android.sh debug
```

### Meta Quest 2

O Quest 2 corre **Horizon OS**, que é baseado em Android, por isso a mesma aplicação
Capacitor é distribuída com um *product flavor* próprio:

```sh
cd mobile
./build-quest.sh release      # ou: ./build-quest.sh debug
```

O APK do Quest sai em `build/android/GameOnLauncher-Quest-1.0.0-release.apk` e tem:

- **nome próprio** — "Game On Launcher Quest", para se distinguir do build de telemóvel;
- **metadados da Oculus** — `com.oculus.vr.focusable=false` e
  `com.oculus.supportedDevices=quest2`, o que faz o Horizon OS mostrar a aplicação num
  **painel 2D virtual** em vez de ocupar o headset inteiro (a app é de ecrã plano, não é
  um título VR imersivo);
- **alvos de toque maiores** — como não há ecrã tátil no Quest, a interface é controlada
  pelo laser do comando, e o CSS aumenta os alvos quando deteta um Quest;
- **assinatura** — para instalar por `adb` tem de estar assinado, e o build já usa a
  chave do projeto.

Instalar no headset:

```sh
adb connect <ip-do-quest>
adb install -r build/android/GameOnLauncher-Quest-1.0.0-release.apk
```

Ou pela **Quest Developer Hub** (cargo como app de 2D) ou pelo
[Meta Quest Developer Console](https://developer.oculus.com/).

Os APK ficam em `mobile/android/app/build/outputs/apk/` e são copiados para
`build/android/`:

| Ficheiro | Descrição |
| --- | --- |
| `GameOnLauncher-1.0.0-release.apk` | Versão assinada para telemóvel, pronta a instalar |
| `GameOnLauncher-Quest-1.0.0-release.apk` | Versão para Meta Quest 2 (painel 2D) |
| `GameOnLauncher-1.0.0-debug.apk` | Versão de depuração |

**Requisitos**: JDK 17 (o Gradle falha com o Java 25), Android SDK com
`platforms;android-34`, `build-tools;34.0.0` e `platform-tools`. O script
`build-android.sh` detecta o SDK em `~/Library/Android/sdk` e o JDK 17 instalado.

**Instalar no telemóvel**:

```sh
adb install -r build/android/GameOnLauncher-1.0.0-release.apk
```

Ou copie o `.apk` para o telemóvel e abra-o (é preciso permitir "instalar de fontes
desconhecidas" nas definições do Android).

### Assinatura

A chave de assinatura de demonstração fica em `mobile/android/keystore/` com as
credenciais em `mobile/android/keystore.properties`. **Substitua-a antes de publicar** —
ambos os ficheiros estão no `.gitignore`.

### O que funciona no telemóvel

| Recurso | Estado |
| --- | --- |
| Novidades oficiais da Mojang e mods em destaque | ✅ |
| Pesquisa e transferência de mods do Modrinth | ✅ |
| Lista de versões oficial do Minecraft | ✅ |
| Versões de carregadores (Fabric, Quilt, Forge, NeoForge) | ✅ |
| Criar e gerir instâncias (ficheiros no dispositivo) | ✅ |
| Login Microsoft por código de dispositivo | ✅ |
| Skin por nickname e importação de PNG | ✅ |
| Música de fundo em loop | ✅ |
| Temas, cores e definições | ✅ |
| Centro de servidores | ❌ precisa de um computador |
| Executar o jogo | ❌ abre a aplicação oficial do Minecraft |

As pedidos HTTP usam `CapacitorHttp`, que passa pela stack nativa e contorna a política
CORS do navegador — é isso que permite alcançar as APIs da Mojang, Modrinth, CurseForge e
Microsoft a partir da WebView.

### Arquitetura

```
mobile/
  capacitor.config.json     configuração do plugin
  www/                      a aplicação (HTML/CSS/JS)
    index.html
    styles/app.css          tokens e componentes adaptados ao ecrã tátil
    js/bridge.js            ponte nativa (CapacitorHttp, Filesystem, Preferences)
    js/app.js               arranque e routing
    js/store.js             estado central
    js/pages/               home, instâncias, conteúdo, contas e definições
  dev/                      pré-visualização no navegador (com stubs)
  tools/                    geração do ícone e do ecrã de arranque
  android/                  projeto Android gerado pelo Capacitor
```

A interface é desenhada primeiro para o telemóvel: barra de navegação inferior, alvos
tácteis de 46 px, folhas que deslizam de baixo para cima e a mesma linguagem visual das
versões de computador.

---

## macOS — app nativa (SwiftUI)

### Abrir

1. Abra `build/GameOnLauncher-macOS.dmg` e arraste **Game on Launcher.app** para
   Aplicativos (o DMG inclui o atalho para a pasta Aplicativos).
   Ou descompacte `build/GameOnLauncher-macOS.zip` e mova a app para Aplicativos.
2. Abra a aplicação.

O binário é **universal** (Apple silicon `arm64` + Intel `x86_64`) e requer macOS 13 ou
posterior.

### Se o macOS bloquear a aplicação

Sem um certificado de programador a app é assinada ad-hoc, e o Gatekeeper pode mostrar
*"não pode ser aberta porque o programador não pode ser verificado"*. Duas formas de
resolver:

```sh
# 1) Abrir pelo terminal (o Gatekeeper deixa passar nesta sessão)
open -a "Game on Launcher"

# 2) Remover a marca de quarentena do ficheiro baixado
xattr -dr com.apple.quarantine "Game on Launcher.app"
```

Para distribuir a app a outros Mac sem avisos, assina e notariza na build:

```sh
export SIGNING_IDENTITY="Developer ID Application: A TUA EMPRESA (TEAMID)"
export APPLE_ID="teu@email.com"
export APP_PASSWORD="app-specific-password"
export TEAM_ID="TEAMID"
./build-macos.sh
```

Com estas variáveis o script assina com o certificado, submete ao `notarytool` e fixa o
*ticket* no bundle — o Gatekeeper deixa de bloquear.

### Compilar

```sh
./build-macos.sh
```

O script compila todos os ficheiros em `Sources/`, gera `build/GameOnLauncher-macOS.zip` e
tenta criar `build/GameOnLauncher-macOS.dmg`. Requer apenas as Command Line Tools da Apple.

### Arquitetura

O código está dividido por responsabilidade:

| Pasta | Conteúdo |
| --- | --- |
| `Sources/App` | Ponto de entrada (`@main`), modelo central de estado, barra lateral e routing |
| `Sources/Design` | Tokens de design, biblioteca de componentes, fundos animados e paisagem voxel |
| `Sources/Features` | Uma vista por página: Jogar, Instâncias, Conteúdo, Servidor, Logs, Contas, Streamer, Aparência, Configurações |
| `Sources/Support` | Caminhos, preferências tipadas, store de instâncias, store de registos e feed de novidades |
| `Sources/Engines` | Motor de jogo interno, autenticação Microsoft, servidor local, clientes CurseForge/Modrinth e importador de modpacks |

`LauncherModel` é a fonte única de verdade: as vistas observam-no e nunca guardam estado
de domínio localmente.

---

## Windows / Linux — app multiplataforma (Electron)

### Compilar

```sh
cd desktop
npm install
npm run build:win      # instalador .exe (x64 + arm64) e versão portátil
npm run build:mac      # dmg + zip para macOS
npm run build:linux    # AppImage + deb
npm start              # executa em modo de desenvolvimento
```

Os artefactos ficam em `desktop/dist/`:

- `GameOnLauncher-1.0.0.exe` — instalador (NSIS) para x64 e arm64
- `GameOnLauncher-1.0.0-x64.exe` — instalador apenas para x64
- `GameOnLauncher-1.0.0-portable.exe` — versão portátil, sem instalação

O ícone da aplicação é gerado por `desktop/tools/make-icons.py` (PNG, ICO e ICNS).

### Arquitetura

```
desktop/src/
  main/
    main.js              ciclo de vida da janela e registo dos IPC
    preload.js           ponte segura entre processo principal e renderer
    services/            contas, motor de jogo, instâncias, conteúdo, servidor, novidades
  renderer/
    index.html           estrutura da aplicação
    styles/              tokens, componentes e estilos de página
    js/                  store, router e um módulo por página
```

---

## Funcionalidades

### Motor de jogo interno

Não há dependência de launchers externos. O motor interno:

- descarrega os ficheiros oficiais da Mojang (bibliotecas, assets, natives e o jar do
  cliente) e verifica os SHA-1;
- arranca o Minecraft em x86_64 e Apple Silicon (incluindo Rosetta);
- **suporta os carregadores de mods** — Fabric, Quilt, Forge e NeoForge — usando os
  metadados oficiais de cada serviço:
  - **Fabric / Quilt** leem o perfil de lançamento publicado pelo respetivo serviço
    (`meta.fabricmc.net` e `meta.quiltmc.org`), descarregando o loader, o intermediary
    e as bibliotecas Maven adicionais;
  - **Forge / NeoForge** executam o instalador oficial uma única vez, que gera o perfil
    da versão e as bibliotecas, tal como fazem os launchers de desktop. Antes de correr,
    o launcher prepara a pasta que o instalador espera (o JSON oficial da versão e um
    perfil de launcher mínimo), sem o qual o instalador aborta.
- mostra sempre o Java detetado, permite escolher outro runtime e explica o que falta
  quando o jogo não arranca.

#### Java

O runtime é escolhido automaticamente conforme a versão do Minecraft:

| Minecraft | Java necessário |
| --- | --- |
| até 1.16 | Java 8 |
| 1.17 até 1.20.4 | Java 17 |
| 1.20.5 em diante | **Java 21** |

Usar um runtime mais antigo faz o jogo falhar com `UnsupportedClassVersionError`.
**Configurações → Minecraft → Java instalado** mostra os runtimes detetados, indica
qual é o adequado e permite escolher outro (o caminho é guardado em
`gameOnLauncherJavaPath`).

#### Testar o motor

```sh
swiftc -parse-as-library -target x86_64-apple-macos13.0 \
  $(find Sources -name '*.swift' ! -name 'GameOnLauncherApp.swift') \
  tools/EngineTest.swift -o /tmp/enginetest
/tmp/enginetest 1.21.8 fabric      # versão, carregador
```

O comando compila o motor com as mesmas fontes da app, resolve o carregador,
transfere tudo e arranca o jogo, imprimindo a linha de comandos usada.

### Versão

A versão vive num único ficheiro, `VERSION`, no raiz do projeto. Todos os builds a leem:

```sh
echo "1.0.2" > VERSION
./build-macos.sh                     # macOS
cd desktop && npm run build:win       # Windows
cd mobile && ./build-android.sh release   # Android
cd mobile && ./build-quest.sh release     # Meta Quest 2
```

O `versionCode` do Android é derivado da versão (`1.0.2` → `10002`), por isso cresce
sempre e o sistema aceita a atualização por cima da versão anterior. O build do Quest usa
o pacote próprio (`com.gameonlauncher.app.quest`), para poder coexistir com o do telemóvel.

A app lê a versão real do pacote nativo em tempo de execução, por isso a comparação
feita pelo atualizador corresponde sempre ao que foi compilado.

### Atualizações

As builds são publicadas em
[github.com/lUCASFBLAB/game-on-launcher](https://github.com/lUCASFBLAB/game-on-launcher/releases),
sempre sob a etiqueta `gameon-mac.zip`:

| Ficheiro | Plataforma |
| --- | --- |
| `GameOnLauncher-macOS.dmg` | macOS |
| `GameOnLauncher-1.0.0-x64.exe` | Windows Intel |
| `GameOnLauncher-1.0.0-arm64.exe` | Windows ARM |
| `GameOnLauncher-1.0.0-portable.exe` | Windows portátil |
| `GameOnLauncher-1.0.0.exe` | Windows instalador |

O launcher procura uma build nova em **Configurações → Atualizações** e instala-a:

- **macOS** — transfere o `.dmg`, monta-o, substitui a aplicação e reinicia;
- **Windows** — transfere o instalador e arranca-o (o NSIS substitui a app);
- **Android** — transfere o `.apk` e abre o ficheiro para o sistema pedir a
  confirmação da instalação.

Como os ficheiros do Windows levam a versão no nome, a comparação é direta. O `.dmg`
do macOS não leva a versão, por isso a data de publicação é usada: substituir o
ficheiro no mesmo tag conta como atualização.

### Limitação de pedidos

A Mojang limita o número de pedidos e o launcher pede centenas de ficheiros seguidos.
Quando a resposta é `429` ou um `5xx`, o motor espera e volta a tentar, e a mensagem de
erro mostra o estado HTTP em vez de uma falha genérica.

### Música de fundo

**Aparência → Música de fundo** importa uma faixa local (MP3, M4A, AAC, WAV, OGG, FLAC)
que toca em loop com volume ajustável. A faixa é copiada para a pasta da aplicação, por
isso continua a tocar depois de reiniciar o launcher.

### Skins

**Contas → Skin da conta** resolve a skin oficial de qualquer nickname através das APIs
da Mojang, ou permite importar um PNG local. Com uma conta Microsoft iniciada, a skin
importada pode ser **enviada para o perfil** da conta.

No telemóvel o PNG é escolhido com o seletor do sistema e copiado para a pasta da
aplicação, para continuar disponível offline.

### Contas

**Contas → Conta Microsoft** usa o fluxo oficial de *device code*: o launcher mostra um
código, abre a página de confirmação da Microsoft e guarda o *refresh token* no
Porta-chaves do macOS (`safeStorage` no Windows) ou num ficheiro local encriptado.
Também existe um perfil offline local.

### Conteúdo

- **CurseForge** exige uma API key autorizada, guardada no cofre do sistema
  (**Configurações → CurseForge**). Modpacks são instalados com todas as dependências.
- **Modrinth** funciona sem chave. Modpacks `.mrpack` são importados nativamente
  (`modrinth.index.json` + `overrides/`), sem depender de nenhum launcher externo.

Os mods transferidos vão para a pasta `mods/` da instância selecionada; a página de mods
lista os JARs locais e permite desativá-los (renomeando o ficheiro) ou apagá-los.

### Centro de servidor

Obtém versões/builds da API oficial PaperMC, baixa `paper.jar`, do instalador oficial do
Fabric, ou executa o instalador do Forge/NeoForge. A EULA tem de ser aceite antes de
iniciar. A consola é lida em direto, com envio de comandos, amostragem de CPU/RAM e
gestão de ficheiros da pasta do servidor. Plugins Paper são pesquisados e baixados
diretamente da API Modrinth para `plugins/`.

### Novidades

A página inicial mostra as **patch notes oficiais da Mojang** e os mods mais
descarregados do Modrinth, com imagens reais e datas.

### Aparência

Temas sazonais (Natal, Halloween, Ano Novo, Páscoa, Verão, Carnaval) manuais ou
automáticos, nove presets de cor de destaque, paisagem voxel animada no banner inicial,
imagem ou vídeo de fundo local em loop (máximo de 30 segundos), barra lateral recolhível
e reordenável.

### Logs

A página **Logs** lê os ficheiros reais da instância (`logs/latest.log`, `logs/debug.log`,
`crash-reports/`, `config/`, `saves/`, …), com pesquisa, cópia, exportação e
atualização automática enquanto o jogo corre.

---

## Dashboard local

```sh
python3 dashboard_server.py
```

Abra <http://localhost:5069> para ver as prévias e os ficheiros do projeto.

---

## Créditos e licenças

As credenciais são mostradas em **Configurações → Créditos**. CurseForge, Modrinth e
PaperMC são serviços externos ligados pelas respetivas APIs. Minecraft e os nomes/logótipos associados pertencem aos seus titulares.
O Game on Launcher é independente e não é afiliado nem endossado por esses projetos.
O código está em [github.com/lUCASFBLAB](https://github.com/lUCASFBLAB).

- [Repositório do Game On Launcher](https://github.com/lUCASFBLAB)
- [Mojang Studios](https://www.minecraft.net/)
- [Fabric e Quilt](https://fabricmc.net/)
- [CurseForge REST API](https://docs.curseforge.com/rest-api/)
- [Modrinth API](https://docs.modrinth.com/api/)
- [PaperMC Downloads Service](https://docs.papermc.io/misc/downloads-service/)
- [Minecraft EULA](https://www.minecraft.net/eula)
