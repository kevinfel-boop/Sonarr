#!/usr/bin/env bash
# install-kvm.sh
# Script d'installation "en un clic" pour King Video Master (KVM)
# Fork personnalisé de Sonarr — macOS (Apple Silicon)

set -euo pipefail

# ============================================================
# 0. CONFIGURATION
# ============================================================
KVM_DIR="${KVM_DIR:-$HOME/Sonnar/Sonarr}"
KVM_BRANCH="custom-branding"
KVM_REPO_URL="${KVM_REPO_URL:-https://github.com/kevinfel-boop/Sonarr.git}"
KVM_PORT="${KVM_PORT:-8989}"
LOG_FILE="$HOME/kvm-install.log"

# Auto-update
SCRIPT_VERSION="1.0.1"
SCRIPT_URL="https://raw.githubusercontent.com/kevinfel-boop/Sonarr/custom-branding/install-kvm.sh"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Couleurs pour les messages
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[0;31m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"

# ============================================================
# 1. FONCTIONS UTILITAIRES
# ============================================================

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[ATTENTION]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERREUR]${COLOR_RESET} $1"
}

die() {
    log_error "$1"
    exit 1
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi
    return 0
}

run_step() {
    local description="$1"
    shift
    log_info "$description..."
    if "$@"; then
        log_success "$description : terminé"
    else
        die "$description a échoué. Voir les détails ci-dessus."
    fi
}

# ============================================================
# 1.5 AUTO-UPDATE DU SCRIPT
# ============================================================

update_script() {
    log_info "Version locale : $SCRIPT_VERSION"
    log_info "Vérification d'une nouvelle version sur GitHub..."

    local tmp_file
    tmp_file=$(mktemp)

    if ! curl -fsSL "$SCRIPT_URL" -o "$tmp_file"; then
        rm -f "$tmp_file"
        die "Impossible de récupérer la version distante ($SCRIPT_URL). Vérifie ta connexion."
    fi

    local remote_version
    remote_version=$(grep -m1 '^SCRIPT_VERSION=' "$tmp_file" | cut -d'"' -f2)

    if [ -z "$remote_version" ]; then
        rm -f "$tmp_file"
        die "Impossible de lire la version distante. Le script distant est peut-être corrompu."
    fi

    log_info "Version distante : $remote_version"

    if [ "$remote_version" = "$SCRIPT_VERSION" ]; then
        log_success "Le script est déjà à jour (version $SCRIPT_VERSION)."
        rm -f "$tmp_file"
        exit 0
    fi

    log_warn "Nouvelle version disponible : $remote_version (locale : $SCRIPT_VERSION)"
    read -r -p "Mettre à jour maintenant ? [O/n] " reply
    if [[ "$reply" =~ ^[nN]$ ]]; then
        log_info "Mise à jour annulée."
        rm -f "$tmp_file"
        exit 0
    fi

    # Sauvegarde de l'ancienne version avant remplacement
    cp "$SCRIPT_PATH" "${SCRIPT_PATH}.bak"
    chmod +x "$tmp_file"
    mv "$tmp_file" "$SCRIPT_PATH"

    log_success "Script mis à jour vers la version $remote_version."
    log_info "Ancienne version sauvegardée : ${SCRIPT_PATH}.bak"
    log_info "Relance $0 pour utiliser la nouvelle version."
    exit 0
}

# ============================================================
# 2. VÉRIFICATION DES DÉPENDANCES
# ============================================================

check_dependencies() {
    log_info "Vérification des dépendances..."
    local missing=0

    if check_command git; then
        log_success "Git trouvé ($(git --version))"
    else
        log_error "Git n'est pas installé."
        log_warn "Installe-le avec : xcode-select --install"
        missing=1
    fi

    if check_command node; then
        local node_version
        node_version=$(node --version | tr -d 'v' | cut -d. -f1)
        if [ "$node_version" -ge 18 ]; then
            log_success "Node.js trouvé ($(node --version))"
        else
            log_error "Node.js version $(node --version) trouvée, mais v18+ requis."
            log_warn "Mets à jour avec : brew install node"
            missing=1
        fi
    else
        log_error "Node.js n'est pas installé."
        log_warn "Installe-le avec : brew install node"
        missing=1
    fi

    if check_command yarn; then
        log_success "Yarn trouvé ($(yarn --version))"
    else
        log_error "Yarn n'est pas installé."
        log_warn "Installe-le avec : brew install yarn (ou npm install -g yarn)"
        missing=1
    fi

    if check_command dotnet; then
        log_success "dotnet trouvé ($(dotnet --version))"
    else
        log_error ".NET SDK n'est pas installé."
        log_warn "Installe-le avec : brew install --cask dotnet-sdk"
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        die "Une ou plusieurs dépendances manquent. Installe-les puis relance le script."
    fi

    log_success "Toutes les dépendances sont présentes."
}

# ============================================================
# 3. RÉCUPÉRATION DU CODE SOURCE
# ============================================================

setup_repository() {
    if [ -d "$KVM_DIR/.git" ]; then
        log_info "Dépôt existant détecté dans $KVM_DIR"
        cd "$KVM_DIR"

        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)

        if [ "$current_branch" != "$KVM_BRANCH" ]; then
            log_warn "Branche actuelle : $current_branch. Bascule vers $KVM_BRANCH..."
            git checkout "$KVM_BRANCH" || die "Impossible de basculer sur la branche $KVM_BRANCH"
        fi

        log_info "Mise à jour du dépôt (git pull)..."
        if git pull origin "$KVM_BRANCH"; then
            log_success "Dépôt à jour."
        else
            log_warn "git pull a échoué (pas de connexion réseau ou conflits ?). Poursuite avec le code local existant."
        fi
    else
        if [ -d "$KVM_DIR" ] && [ "$(ls -A "$KVM_DIR" 2>/dev/null)" ]; then
            die "$KVM_DIR existe déjà mais n'est pas un dépôt Git valide. Renomme-le ou choisis un autre KVM_DIR."
        fi

        log_info "Clonage du dépôt depuis $KVM_REPO_URL..."
        git clone --branch "$KVM_BRANCH" "$KVM_REPO_URL" "$KVM_DIR" \
            || die "Échec du clonage. Vérifie l'URL du dépôt et ta connexion."

        cd "$KVM_DIR"
        log_success "Dépôt cloné dans $KVM_DIR sur la branche $KVM_BRANCH."
    fi
}

# ============================================================
# 4. INSTALLATION DES DÉPENDANCES FRONTEND
# ============================================================

install_frontend_deps() {
    cd "$KVM_DIR/frontend" || die "Dossier frontend introuvable dans $KVM_DIR"

    log_info "Installation des dépendances frontend (yarn install)..."
    if yarn install; then
        log_success "yarn install terminé."
    else
        die "yarn install a échoué. Vérifie ta connexion réseau ou le fichier package.json."
    fi

    if [ -d "node_modules" ] && [ -n "$(ls -A node_modules 2>/dev/null)" ]; then
        : # node_modules trouvé localement dans frontend/
    elif [ -d "$KVM_DIR/node_modules" ] && [ -n "$(ls -A "$KVM_DIR/node_modules" 2>/dev/null)" ]; then
        : # node_modules hissé à la racine (yarn workspaces)
    else
        die "node_modules est absent ou vide (ni dans frontend/ ni à la racine) après yarn install."
    fi

    log_success "Dépendances frontend installées correctement."
}

# ============================================================
# 5. COMPILATION DU FRONTEND
# ============================================================

build_frontend() {
    cd "$KVM_DIR/frontend" || die "Dossier frontend introuvable dans $KVM_DIR"

    log_info "Compilation du frontend (yarn build)..."
    if yarn build; then
        log_success "yarn build terminé."
    else
        die "yarn build a échoué. Consulte les erreurs webpack ci-dessus."
    fi

    if [ ! -f "$KVM_DIR/_output/UI/index.html" ]; then
        die "index.html introuvable dans _output/UI après le build. Le build a peut-être échoué silencieusement."
    fi

    log_success "Frontend compilé : $KVM_DIR/_output/UI"
}

# ============================================================
# 6. COMPILATION DU BACKEND
# ============================================================

build_backend() {
    cd "$KVM_DIR" || die "Dossier $KVM_DIR introuvable"

    local sln="src/Sonarr.sln"
    if [ ! -f "$sln" ]; then
        die "Solution backend introuvable : $sln"
    fi

    log_info "Compilation du backend (dotnet build de la solution complète)..."
    if dotnet build "$sln" -p:RunAnalyzersDuringBuild=false; then
        log_success "dotnet build terminé."
    else
        die "dotnet build a échoué. Consulte les erreurs de compilation ci-dessus."
    fi

    if [ ! -d "_output" ]; then
        die "Le dossier _output n'a pas été créé après le build backend."
    fi

    log_success "Backend compilé."
}

# ============================================================
# 7. COPIE DES ASSETS UI VERS LE DOSSIER DE SORTIE .NET
# ============================================================

copy_ui_assets() {
    cd "$KVM_DIR" || die "Dossier $KVM_DIR introuvable"

    # Détecte dynamiquement le dossier net*.0 (ex: net10.0), au cas où la version change
    local net_dir
    net_dir=$(find "_output" -maxdepth 1 -type d -name "net*.0" | head -n 1)

    if [ -z "$net_dir" ]; then
        die "Impossible de trouver le dossier net*.0 dans _output/. Le build backend a-t-il réussi ?"
    fi

    local dest="$net_dir/UI"

    log_info "Copie des fichiers UI vers $dest..."

    # Supprime la destination si elle existe déjà, pour éviter une copie imbriquée (UI/UI/...)
    if [ -d "$dest" ]; then
        rm -rf "$dest"
    fi

    cp -R "_output/UI" "$dest" || die "Échec de la copie vers $dest"

    if [ ! -f "$dest/index.html" ]; then
        die "index.html introuvable dans $dest après la copie. Quelque chose a mal tourné."
    fi

    log_success "Assets UI copiés dans $dest"
}

# ============================================================
# 8. LANCEMENT DE L'APPLICATION
# ============================================================

check_port_free() {
    if lsof -ti ":$KVM_PORT" &> /dev/null; then
        log_warn "Le port $KVM_PORT est déjà occupé par un autre processus."
        read -r -p "Veux-tu arrêter ce processus pour libérer le port ? [o/N] " reply
        if [[ "$reply" =~ ^[oOyY]$ ]]; then
            lsof -ti ":$KVM_PORT" | xargs kill
            sleep 2
            log_success "Port $KVM_PORT libéré."
        else
            die "Le port $KVM_PORT reste occupé. Change KVM_PORT ou libère-le manuellement."
        fi
    fi
}

launch_app() {
    cd "$KVM_DIR" || die "Dossier $KVM_DIR introuvable"
    check_port_free

    local csproj="src/NzbDrone.Console/Sonarr.Console.csproj"

    if [ "$RUN_IN_BACKGROUND" = "true" ]; then
        log_info "Lancement de KVM en arrière-plan..."
        nohup dotnet run --project "$csproj" -p:RunAnalyzersDuringBuild=false > "$LOG_FILE" 2>&1 &
        APP_PID=$!
        sleep 3

        if kill -0 "$APP_PID" 2>/dev/null; then
            log_success "KVM lancé en arrière-plan (PID: $APP_PID)"
            log_info "Logs disponibles dans : $LOG_FILE"
        else
            die "Le processus s'est arrêté immédiatement. Consulte $LOG_FILE pour le détail."
        fi
    else
        log_info "Lancement de KVM au premier plan (Ctrl+C pour arrêter)..."
        dotnet run --project "$csproj" -p:RunAnalyzersDuringBuild=false
    fi
}

# ============================================================
# 9. RÉCAPITULATIF FINAL
# ============================================================

print_summary() {
    echo ""
    echo "============================================================"
    log_success "Installation terminée !"
    echo "============================================================"
    echo "  Application : King Video Master (KVM)"
    echo "  Dossier     : $KVM_DIR"
    echo "  URL         : http://localhost:$KVM_PORT"
    if [ "$RUN_IN_BACKGROUND" = "true" ]; then
        echo "  Mode        : arrière-plan (PID: ${APP_PID:-inconnu})"
        echo "  Logs        : $LOG_FILE"
    else
        echo "  Mode        : premier plan"
    fi
    echo "============================================================"
}

# ============================================================
# PROGRAMME PRINCIPAL
# ============================================================

RUN_IN_BACKGROUND="false"

usage() {
    echo "Usage: $0 [--background] [--update] [--help]"
    echo "  --background   Lance l'application en arrière-plan (logs dans $LOG_FILE)"
    echo "  --update       Vérifie et installe une nouvelle version du script, puis quitte"
    echo "  --help         Affiche cette aide"
}

# Parsing des arguments
for arg in "$@"; do
    case "$arg" in
        --background)
            RUN_IN_BACKGROUND="true"
            ;;
        --update)
            update_script
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_warn "Argument inconnu ignoré : $arg"
            ;;
    esac
done

main() {
    log_info "=== Installation de King Video Master (KVM) ==="
    check_dependencies
    setup_repository
    install_frontend_deps
    build_frontend
    build_backend
    copy_ui_assets
    launch_app
    print_summary
}

main
