#!/bin/bash

INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"
CONFIG_DIR="/etc/vk-proxy"
CONFIG_FILE="$CONFIG_DIR/vk-proxy.conf"
CLIENTS_DIR="/root/vpn-clients"
PANEL_VERSION="2.1"

if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите скрипт от имени root (команда: sudo bash)"
    exit 1
fi

mkdir -p "$CONFIG_DIR" "$CLIENTS_DIR"

# === ФУНКЦИИ КОНФИГУРАЦИИ ===
get_conf() {
    if [ -f "$CONFIG_FILE" ]; then
        grep "^$1=" "$CONFIG_FILE" | cut -d'=' -f2-
    fi
}

set_conf() {
    if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi
    if grep -q "^$1=" "$CONFIG_FILE"; then
        sed -i "s|^$1=.*|$1=$2|" "$CONFIG_FILE"
    else
        echo "$1=$2" >> "$CONFIG_FILE"
    fi
}

# === ГЛОБАЛЬНЫЕ УТИЛИТЫ ===
generate_wrap_key() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
    else
        cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1
    fi
}

get_target_port_from_file() {
    local file="$1"
    local port=""
    if [[ "$file" == *.json ]]; then
        port=$(jq -r '.listen // empty' "$file" 2>/dev/null | grep -oE '[0-9]+$')
    elif [[ "$file" == *.yaml || "$file" == *.yml ]]; then
        port=$(grep -i -E -m 1 '^[[:space:]]*listen:[[:space:]]*' "$file" 2>/dev/null | grep -oE '[0-9]+$')
    elif [[ "$file" == *.conf ]]; then
        port=$(awk -F'=' '/^[[:space:]]*ListenPort[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$file")
    fi
    echo "$port"
}

# Миграция со старых файлов
migrate_configs() {
    if [ -f /root/.vk-proxy.conf ]; then
        mv /root/.vk-proxy.conf "$CONFIG_FILE"
    fi
    if [ -f /root/.vk-proxy-version ]; then
        set_conf "VERSION" "$(cat /root/.vk-proxy-version)"
        set_conf "PROXY_PORT" "$(cat /root/.vk-proxy-port 2>/dev/null || echo 56000)"
        set_conf "TARGET_PORT" "$(cat /root/.vk-proxy-target-port 2>/dev/null || echo 51820)"
        set_conf "PROXY_REPO" "$(cat /root/.vk-proxy-repo 2>/dev/null || echo cacggghp/vk-turn-proxy)"
        set_conf "CORE_TYPE" "$(cat /root/.vk-proxy-core-type 2>/dev/null || echo go)"
        if [[ "$(cat /root/.vk-proxy-vless 2>/dev/null)" == "1" ]]; then set_conf "VLESS_MODE" "vless"; else set_conf "VLESS_MODE" "off"; fi
        if [[ "$(cat /root/.vk-proxy-dc-mode 2>/dev/null)" == "1" ]]; then set_conf "DC_MODE" "1"; else set_conf "DC_MODE" "0"; fi
        set_conf "JAZZ_ROOM" "$(cat /root/.vk-proxy-jazz-room 2>/dev/null)"
        set_conf "YANDEX_LINK" "$(cat /root/.vk-proxy-yandex-link 2>/dev/null)"
        set_conf "CUSTOM_ARGS" "$(cat /root/.vk-proxy-custom-args 2>/dev/null)"
        rm -f /root/.vk-proxy-version /root/.vk-proxy-port /root/.vk-proxy-target-port /root/.vk-proxy-repo \
              /root/.vk-proxy-core-type /root/.vk-proxy-vless /root/.vk-proxy-dc-mode /root/.vk-proxy-jazz-room \
              /root/.vk-proxy-yandex-link /root/.vk-proxy-custom-args /root/.vk-proxy-yandex-dc
    fi
}
migrate_configs

# === ФУНКЦИЯ СОЗДАНИЯ ПАНЕЛИ ===
create_panel() {
cat << 'EOF' > /usr/local/bin/vk-panel
#!/bin/bash
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"
CONFIG_DIR="/etc/vk-proxy"
CONFIG_FILE="$CONFIG_DIR/vk-proxy.conf"
CLIENTS_DIR="/root/vpn-clients"
PANEL_VERSION="2.1"

mkdir -p "$CONFIG_DIR" "$CLIENTS_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi
PUBLIC_IP=$(curl -4 -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 https://api.ipify.org)

get_conf() { if [ -f "$CONFIG_FILE" ]; then grep "^$1=" "$CONFIG_FILE" | cut -d'=' -f2-; fi }
set_conf() { if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi; if grep -q "^$1=" "$CONFIG_FILE"; then sed -i "s|^$1=.*|$1=$2|" "$CONFIG_FILE"; else echo "$1=$2" >> "$CONFIG_FILE"; fi }

generate_wrap_key() {
    if command -v openssl &> /dev/null; then openssl rand -hex 32
    else cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1; fi
}

get_target_port_from_file() {
    local file="$1"; local port=""
    if [[ "$file" == *.json ]]; then
        port=$(jq -r '.listen // empty' "$file" 2>/dev/null | grep -oE '[0-9]+$')
    elif [[ "$file" == *.yaml || "$file" == *.yml ]]; then
        port=$(grep -i -E -m 1 '^[[:space:]]*listen:[[:space:]]*' "$file" 2>/dev/null | grep -oE '[0-9]+$')
    elif [[ "$file" == *.conf ]]; then
        port=$(awk -F'=' '/^[[:space:]]*ListenPort[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$file")
    fi
    echo "$port"
}

CURRENT_VERSION=$(get_conf "VERSION")
CURRENT_VERSION=${CURRENT_VERSION:-"Неизвестно"}
PROXY_PORT=$(get_conf "PROXY_PORT"); PROXY_PORT=${PROXY_PORT:-"56000"}
TARGET_PORT=$(get_conf "TARGET_PORT"); TARGET_PORT=${TARGET_PORT:-"51820"}
PROXY_REPO=$(get_conf "PROXY_REPO"); PROXY_REPO=${PROXY_REPO:-"cacggghp/vk-turn-proxy"}

# Миграция репозитория
if [[ "$PROXY_REPO" != *"/"* ]] && [[ "$PROXY_REPO" != "Прямая ссылка" ]]; then
    if [[ "$PROXY_REPO" == "Urtyom-Alyanov" ]]; then PROXY_REPO="Urtyom-Alyanov/turn-proxy"; else PROXY_REPO="${PROXY_REPO}/vk-turn-proxy"; fi
    set_conf "PROXY_REPO" "$PROXY_REPO"
fi
if [[ "$PROXY_REPO" == "alexmac6574/vk-turn-proxy" ]]; then PROXY_REPO="alxmcp/vk-turn-proxy"; set_conf "PROXY_REPO" "$PROXY_REPO"; fi

get_download_url() {
    local api_resp="$1"; local arch="$2"; local repo="$3"; local url=""
    if [[ "$repo" == *"Urtyom-Alyanov"* ]]; then
        url=$(echo "$api_resp" | jq -r '.assets[] | select(.name == "turn-proxy-server") | .browser_download_url' | head -n 1)
    else
        url=$(echo "$api_resp" | jq -r '.assets[] | select(.name == "server-linux-'"${arch}"'") | .browser_download_url' | head -n 1)
    fi
    echo "$url"
}

# Единая функция сборки аргументов запуска
get_exec_args() {
    local FINAL_ARGS=""
    local CUSTOM_ARGS=$(get_conf "CUSTOM_ARGS")
    if [[ -n "$CUSTOM_ARGS" ]]; then
        echo "$CUSTOM_ARGS"; return
    fi

    local PROXY_PORT=$(get_conf "PROXY_PORT"); PROXY_PORT=${PROXY_PORT:-"56000"}
    local TARGET_PORT=$(get_conf "TARGET_PORT"); TARGET_PORT=${TARGET_PORT:-"51820"}
    local CORE_TYPE=$(get_conf "CORE_TYPE"); CORE_TYPE=${CORE_TYPE:-"go"}

    # Rust ядро поддерживает только чистый UDP (WireGuard/Hysteria2). 
    # Флаги VLESS, WRAP и DC в нём физически отсутствуют.
    if [[ "$CORE_TYPE" == "rust" ]]; then
        echo "-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000"
        return
    fi

    local VLESS_FLAG="" DC_FLAG="" WRAP_FLAG=""

    # VLESS
    local VLESS_MODE=$(get_conf "VLESS_MODE")
    if [[ "$VLESS_MODE" == "vless" ]]; then
        VLESS_FLAG=" -vless"
    elif [[ "$VLESS_MODE" == "vless-bond" ]]; then
        VLESS_FLAG=" -vless -vless-bond"
    fi

    # DataChannel — передаём флаг, ядро само решит, поддерживает ли его
    if [[ "$(get_conf "DC_MODE")" == "1" ]]; then
        local JAZZ_ROOM=$(get_conf "JAZZ_ROOM")
        local LINK=$(get_conf "YANDEX_LINK")
        if [[ -n "$JAZZ_ROOM" ]]; then DC_FLAG=" -jazz-room $JAZZ_ROOM -dc"
        elif [[ -n "$LINK" ]]; then DC_FLAG=" -yandex-link $LINK -dc"; fi
    fi

    # WRAP
    if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then
        WRAP_FLAG=" -wrap"
        local WRAP_KEY=$(get_conf "WRAP_KEY")
        if [[ -z "$WRAP_KEY" ]]; then
            WRAP_KEY=$(generate_wrap_key)
            set_conf "WRAP_KEY" "$WRAP_KEY"
        fi
        WRAP_FLAG="$WRAP_FLAG -wrap-key $WRAP_KEY"
    fi

    FINAL_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT$DC_FLAG$VLESS_FLAG$WRAP_FLAG"
    echo "$FINAL_ARGS"
}

apply_and_restart_service() {
    local EXEC_ARGS=$(get_exec_args)
    cat <<EOF_SVC > /etc/systemd/system/vk-proxy.service
[Unit]
Description=VK TURN Proxy Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root
LimitNOFILE=1048576
ExecStart=/root/server-linux-$SYS_ARCH $EXEC_ARGS
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF_SVC
    systemctl daemon-reload
    if systemctl is-active --quiet vk-proxy; then systemctl restart vk-proxy; fi
}

check_bbr_status() {
    if command -v sysctl &> /dev/null; then
        local bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
        if [[ "$bbr_status" == "bbr" ]]; then echo -e "${GREEN}Включен${NC}"
        else echo -e "${RED}Выключен${NC}"; fi
    else
        echo -e "${YELLOW}Неизвестно${NC}"
    fi
}

while true; do
    clear
    TARGET_SERVICE="Введен вручную / Неизвестен"
    shopt -s nullglob
    # Сканируем только серверные конфиги (не клиентские из $CLIENTS_DIR)
    for conf in /etc/hysteria/*.yaml /etc/hysteria/*.yml /etc/hysteria/*.json; do
        port=$(get_target_port_from_file "$conf")
        if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="Hysteria2"; break; fi
    done
    if [[ "$TARGET_SERVICE" == "Введен вручную / Неизвестен" ]]; then
        for conf in /etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf; do
            port=$(get_target_port_from_file "$conf")
            if [[ "$port" == "$TARGET_PORT" ]]; then
                if grep -q -E '^[[:space:]]*(Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4)[[:space:]]*=' "$conf" 2>/dev/null; then
                    TARGET_SERVICE="AmneziaWG"; break
                fi
            fi
        done
    fi
    if [[ "$TARGET_SERVICE" == "Введен вручную / Неизвестен" ]]; then
        for conf in /etc/wireguard/*.conf; do
            port=$(get_target_port_from_file "$conf")
            if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="WireGuard"; break; fi
        done
    fi
    shopt -u nullglob

    if systemctl is-active --quiet vk-proxy; then PROXY_STATE="${GREEN}Активен${NC}"; else PROXY_STATE="${RED}Остановлен${NC}"; fi

    VLESS_MODE=$(get_conf "VLESS_MODE")
    if [[ "$VLESS_MODE" == "vless" ]]; then VLESS_TEXT="${GREEN}Включен (-vless)${NC}"
    elif [[ "$VLESS_MODE" == "vless-bond" ]]; then VLESS_TEXT="${GREEN}Включен (-vless-bond)${NC}"
    else VLESS_TEXT="${RED}Выключен${NC}"; fi

    if [[ "$(get_conf "DC_MODE")" == "1" ]]; then DC_TEXT="${GREEN}Включен${NC}"; else DC_TEXT="${RED}Выключен${NC}"; fi
    if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then WRAP_TEXT="${GREEN}Включен${NC}"; else WRAP_TEXT="${RED}Выключен${NC}"; fi

    if [[ -n "$(get_conf "CUSTOM_ARGS")" ]]; then MODE_TEXT="${YELLOW}Кастомные аргументы (Raw)${NC}"
    else MODE_TEXT="${GREEN}Автоматический${NC}"; fi

    BBR_TEXT=$(check_bbr_status)

    echo "========================================================================="
    echo -e "${CYAN}                       VK TURN Proxy Manager v${PANEL_VERSION}                        ${NC}"
    echo "========================================================================="
    echo -e " 🟢 Статус:      ${PROXY_STATE}"
    echo -e " 📦 Версия:      ${YELLOW}${CURRENT_VERSION}${NC} (Ядро: ${CYAN}${PROXY_REPO}${NC})"
    echo -e " ⚙️  Режим:       ${MODE_TEXT}"
    echo -e " 🛡️  VLESS:       ${VLESS_TEXT}  |  📞 DataChannel: ${DC_TEXT}"
    echo -e " ☁️  WRAP:        ${WRAP_TEXT}  |  🚀 TCP BBR: ${BBR_TEXT}"
    echo "-------------------------------------------------------------------------"
    echo -e " 🌐 Внешний:     ${PUBLIC_IP}:${PROXY_PORT}"
    echo -e " 🎯 Назначение:  127.0.0.1:${TARGET_PORT} [${YELLOW}${TARGET_SERVICE}${NC}]"
    echo -e " 📁 Директория клиентов: ${YELLOW}${CLIENTS_DIR}${NC}"
    echo "========================================================================="
    echo -e "${YELLOW}--- Управление Proxy ---${NC}"
    echo "  1. 🟢 Запустить прокси"
    echo "  2. 🔴 Остановить прокси"
    echo "  3. 🔄 Перезапустить"
    echo "  4. 📥 Обновить ядро"
    echo "  5. 🔀 Сменить реализацию ядра"
    echo "  6. 🗑️  Полностью удалить прокси"
    echo ""
    echo -e "${YELLOW}--- Настройки ---${NC}"
    echo "  7. 🔌 Изменить порты (Внешний / Локальный)"
    echo "  8. 🛡️  Настройка VLESS (-vless / -vless-bond)"
    echo "  9. 📞 Включить/Выключить режим 'DataChannel (SaluteJazz / Yandex)'"
    echo " 10. ☁️  Настройка WRAP (Обфускация / Управление ключом)"
    echo " 11. ✍️  Задать кастомные аргументы запуска (Raw command)"
    echo ""
    echo -e "${YELLOW}--- VPN и Клиенты ---${NC}"
    echo " 12. ➕ Установка/Управление VPN (WG / AmneziaWG / Hysteria2)"
    echo " 13. 📱 Показать QR-код существующего клиента"
    echo ""
    echo -e "${YELLOW}--- Система ---${NC}"
    echo " 14. 🚀 Управление TCP BBR (Вкл/Выкл)"
    echo " 15. 💾 Создать Backup (Резервная копия)"
    echo " 16. 📊 Посмотреть логи"
    echo " 17. ⚙️  Обновить панель"
    echo "  0. ❌ Выйти"
    echo "========================================================================="
    read -p "Выбери действие: " choice
    API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"
    case $choice in
        1) systemctl start vk-proxy; echo -e "${GREEN}Запущено!${NC}"; sleep 1 ;;
        2) systemctl stop vk-proxy; echo -e "${RED}Остановлено!${NC}"; sleep 1 ;;
        3) if systemctl restart vk-proxy; then echo -e "${GREEN}Успешно перезапущено!${NC}"; else echo -e "${RED}Ошибка! Проверьте логи.${NC}"; fi; sleep 2 ;;
        4)
            if [[ "$PROXY_REPO" == "Прямая ссылка" || "$PROXY_REPO" == "Custom_Direct_Link" ]]; then
                echo -e "${YELLOW}Ядро по прямой ссылке. Авто-обновление недоступно.${NC}"
                read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi
            echo "Проверка обновлений ($PROXY_REPO)..."
            API_RESP=$(curl -s --connect-timeout 10 "$API_URL")
            LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
            if [[ "$LATEST_TAG" == "null" || -z "$LATEST_TAG" ]]; then
                echo -e "${RED}Ошибка API GitHub.${NC}"; read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi
            if [[ "$LATEST_TAG" == "$CURRENT_VERSION" ]]; then
                echo -e "${GREEN}Уже установлена актуальная версия ($CURRENT_VERSION)!${NC}"
            else
                echo -e "Доступна: ${YELLOW}$LATEST_TAG${NC} (текущая: $CURRENT_VERSION)"
                read -p "Обновить? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    DOWNLOAD_URL=$(get_download_url "$API_RESP" "$SYS_ARCH" "$PROXY_REPO")
                    if [[ "$DOWNLOAD_URL" != "null" && -n "$DOWNLOAD_URL" ]]; then
                        if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                            systemctl stop vk-proxy
                            mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                            chmod +x /root/server-linux-$SYS_ARCH
                            apply_and_restart_service
                            set_conf "VERSION" "$LATEST_TAG"
                            CURRENT_VERSION=$LATEST_TAG
                            echo -e "${GREEN}Обновлено до $LATEST_TAG!${NC}"
                        fi
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        5)
            echo -e "${YELLOW}ВНИМАНИЕ: При смене ядра клиенты могут перестать подключаться!${NC}"
            echo -e "Текущее: ${CYAN}${PROXY_REPO}${NC}"
            echo -e "1) cacggghp/vk-turn-proxy (Оригинал)"
            echo -e "2) kiper292/vk-turn-proxy (Форк, \e[9mподдержка WB Stream\e[0m)"
            echo -e "3) Urtyom-Alyanov/turn-proxy (Rust, только amd64)"
            echo -e "4) Moroka8/vk-turn-proxy"
            echo -e "5) alxmcp/vk-turn-proxy (Форк, \e[9mподдержка Yandex / SaluteJazz\e[0m)"
            echo -e "6) samosvalishe/vk-turn-proxy"
            echo -e "7) Свой репозиторий или прямая ссылка"
            echo "0) Отмена"
            read -p "Выбор [0-7]: " repo_choice
            case "$repo_choice" in
                1) NEW_REPO="cacggghp/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                2) NEW_REPO="kiper292/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                3) NEW_REPO="Urtyom-Alyanov/turn-proxy"; NEW_CORE_TYPE="rust" ;;
                4) NEW_REPO="Moroka8/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                5) NEW_REPO="alxmcp/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                6) NEW_REPO="samosvalishe/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                7)
                    read -p "Введи owner/repo ИЛИ прямую ссылку: " custom_input
                    if [[ "$custom_input" =~ ^https?:// ]] && [[ ! "$custom_input" =~ ^https?://(www\.)?github\.com/[^/]+/[^/]+/?$ ]]; then
                        NEW_REPO="Custom_Direct_Link"; DOWNLOAD_URL="$custom_input"; LATEST_TAG="Custom"
                    else
                        NEW_REPO=$(echo "$custom_input" | sed -E 's|^https?://github\.com/||' | sed 's/\.git$//' | awk -F/ '{print $1"/"$2}')
                        if [[ -z "$NEW_REPO" || "$NEW_REPO" != *"/"* ]]; then echo -e "${RED}Неверный формат.${NC}"; sleep 1; continue; fi
                    fi
                    echo -e "${CYAN}Какой тип аргументов использовать?${NC}"
                    echo "1) Стандартные (Go)"
                    echo "2) Rust"
                    echo "3) Задать вручную (Raw command)"
                    read -p "Твой выбор [1-3]: " cct
                    if [[ "$cct" == "2" ]]; then NEW_CORE_TYPE="rust"
                    elif [[ "$cct" == "3" ]]; then NEW_CORE_TYPE="custom"
                    else NEW_CORE_TYPE="go"; fi
                    ;;
                0) continue ;;
                *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1; continue ;;
            esac
            if [[ "$NEW_REPO" == "$PROXY_REPO" ]]; then echo -e "${YELLOW}Уже установлено!${NC}"; sleep 1; continue; fi
            read -p "Сменить ядро? [y/N]: " confirm_switch
            if [[ "$confirm_switch" =~ ^[Yy]$ ]]; then
                if [[ "$NEW_REPO" == "Custom_Direct_Link" ]]; then
                    if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                        systemctl stop vk-proxy; mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH; chmod +x /root/server-linux-$SYS_ARCH
                        set_conf "CORE_TYPE" "$NEW_CORE_TYPE"
                        if [[ "$NEW_CORE_TYPE" == "custom" ]]; then read -p "Аргументы: " mca; set_conf "CUSTOM_ARGS" "$mca"; else set_conf "CUSTOM_ARGS" ""; fi
                        apply_and_restart_service
                        set_conf "PROXY_REPO" "Прямая ссылка"; set_conf "VERSION" "Custom"
                        CURRENT_VERSION="Custom"; echo -e "${GREEN}Готово!${NC}"
                    fi
                else
                    NEW_API_URL="https://api.github.com/repos/${NEW_REPO}/releases/latest"
                    API_RESP=$(curl -s --connect-timeout 10 "$NEW_API_URL")
                    LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
                    if [[ "$LATEST_TAG" != "null" && -n "$LATEST_TAG" ]]; then
                        DOWNLOAD_URL=$(get_download_url "$API_RESP" "$SYS_ARCH" "$NEW_REPO")
                        if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                            systemctl stop vk-proxy; mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH; chmod +x /root/server-linux-$SYS_ARCH
                            set_conf "CORE_TYPE" "$NEW_CORE_TYPE"
                            if [[ "$NEW_CORE_TYPE" == "custom" ]]; then read -p "Аргументы: " mca; set_conf "CUSTOM_ARGS" "$mca"; else set_conf "CUSTOM_ARGS" ""; fi
                            apply_and_restart_service
                            set_conf "PROXY_REPO" "$NEW_REPO"; set_conf "VERSION" "$LATEST_TAG"
                            CURRENT_VERSION=$LATEST_TAG; echo -e "${GREEN}Готово!${NC}"
                        fi
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        6)
            echo -e "${RED}ВНИМАНИЕ: Это удалит службу, бинарник прокси и его настройки! VPN останутся нетронутыми.${NC}"
            read -p "Вы АБСОЛЮТНО уверены? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop vk-proxy; systemctl disable vk-proxy; rm -f /etc/systemd/system/vk-proxy.service; systemctl daemon-reload
                if command -v ufw &> /dev/null; then ufw delete allow $PROXY_PORT/tcp >/dev/null 2>&1; ufw delete allow $PROXY_PORT/udp >/dev/null 2>&1; fi
                rm -f /root/server-linux-$SYS_ARCH /usr/local/bin/vk-panel
                rm -rf "$CONFIG_DIR"
                echo -e "${GREEN}Удалено.${NC}"; exit 0
            fi ;;
        7)
            echo -e "${CYAN}Изменение портов:${NC}"
            echo "1) Внешний порт прокси (сейчас: $PROXY_PORT)"
            echo "2) Локальный порт назначения (сейчас: $TARGET_PORT)"
            echo "0) Отмена"
            read -p "Что меняем? [1, 2 или 0]: " pcc
            if [[ "$pcc" == "1" ]]; then
                read -p "Новый внешний порт: " NPP
                if [[ "$NPP" =~ ^[0-9]+$ ]]; then
                    if command -v ufw &> /dev/null; then
                        ufw delete allow $PROXY_PORT/tcp >/dev/null 2>&1; ufw delete allow $PROXY_PORT/udp >/dev/null 2>&1
                        ufw allow $NPP/tcp >/dev/null 2>&1; ufw allow $NPP/udp >/dev/null 2>&1
                    fi
                    set_conf "PROXY_PORT" "$NPP"; PROXY_PORT="$NPP"; apply_and_restart_service
                fi
            elif [[ "$pcc" == "2" ]]; then
                echo "1) Ввести вручную"
                echo "2) Найти автоматически (WG/AmneziaWG/Hysteria2)"
                read -p "Выбор: " tpm
                if [[ "$tpm" == "1" ]]; then
                    read -p "Локальный порт: " NTP
                else
                    shopt -s nullglob
                    # Сканируем только серверные конфиги (без $CLIENTS_DIR)
                    ALL_CONFS=(/etc/wireguard/*.conf /etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf /etc/hysteria/*.yaml /etc/hysteria/*.yml /etc/hysteria/*.json)
                    shopt -u nullglob
                    if [ ${#ALL_CONFS[@]} -gt 0 ]; then
                        for i in "${!ALL_CONFS[@]}"; do
                            port=$(get_target_port_from_file "${ALL_CONFS[$i]}")
                            echo "$((i+1)). ${ALL_CONFS[$i]} (Порт: ${port:-?})"
                        done
                        read -p "Номер: " cc
                        if [[ "$cc" -ge 1 && "$cc" -le ${#ALL_CONFS[@]} ]]; then
                            NTP=$(get_target_port_from_file "${ALL_CONFS[$((cc-1))]}")
                        fi
                    fi
                    if [[ -z "$NTP" ]]; then read -p "Введи вручную: " NTP; fi
                fi
                if [[ -n "$NTP" ]]; then set_conf "TARGET_PORT" "$NTP"; TARGET_PORT="$NTP"; apply_and_restart_service; fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        8)
            if [[ "$(get_conf "CORE_TYPE")" == "rust" ]]; then
                echo -e "\n${RED}⚠️ Ядро на Rust (Urtyom-Alyanov) поддерживает только UDP (WireGuard/Hysteria2).${NC}"
                echo -e "${YELLOW}Флаг VLESS в этой реализации физически отсутствует.${NC}"
                echo -e "${CYAN}Чтобы использовать VLESS, смените ядро на Go (Пункт 5).${NC}"
                read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi
            echo -e "${CYAN}Настройка VLESS:${NC}"
            echo "1) Отключить флаги VLESS"
            echo "2) Включить стандартный режим (-vless)"
            echo "3) Включить режим Bond (-vless -vless-bond)"
            read -p "Ваш выбор [1-3]: " vc
            case "$vc" in
                1) set_conf "VLESS_MODE" "off"; echo -e "${YELLOW}VLESS отключен.${NC}" ;;
                2) set_conf "VLESS_MODE" "vless"; echo -e "${GREEN}Включен флаг -vless.${NC}" ;;
                3) set_conf "VLESS_MODE" "vless-bond"; echo -e "${GREEN}Включен флаг -vless-bond.${NC}" ;;
            esac
            apply_and_restart_service; sleep 1 ;;
        9)
            if [[ "$(get_conf "CORE_TYPE")" == "rust" ]]; then
                echo -e "\n${RED}⚠️ Ядро на Rust (Urtyom-Alyanov) поддерживает только UDP (WireGuard/Hysteria2).${NC}"
                echo -e "${YELLOW}DataChannel в этой реализации отсутствует.${NC}"
                read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi
            if [[ "$(get_conf "DC_MODE")" == "1" ]]; then
                set_conf "DC_MODE" "0"; echo -e "${YELLOW}DataChannel выключен.${NC}"
            else
                echo -e "${CYAN}Настройка DataChannel${NC}"
                echo "1) SaluteJazz"
                echo "2) Яндекс Телемост"
                read -p "Сервис [1-2]: " dc
                if [[ "$dc" == "1" ]]; then
                    read -p "Комната (По умолчанию: any): " ir
                    set_conf "JAZZ_ROOM" "${ir:-any}"; set_conf "YANDEX_LINK" ""; set_conf "DC_MODE" "1"
                elif [[ "$dc" == "2" ]]; then
                    read -p "Ссылка Yandex: " il
                    if [[ -n "$il" ]]; then set_conf "YANDEX_LINK" "$il"; set_conf "JAZZ_ROOM" ""; set_conf "DC_MODE" "1"; fi
                fi
            fi
            apply_and_restart_service; sleep 1 ;;
        10)
            if [[ "$(get_conf "CORE_TYPE")" == "rust" ]]; then
                echo -e "\n${RED}⚠️ Ядро на Rust (Urtyom-Alyanov) поддерживает только UDP (WireGuard/Hysteria2).${NC}"
                echo -e "${YELLOW}Флаг WRAP в этой реализации физически отсутствует.${NC}"
                read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi
            echo -e "${CYAN}Настройки WRAP (Обфускация):${NC}"
            echo "1) Включить/Выключить WRAP-обфускацию (-wrap)"
            echo "2) Показать текущий WRAP ключ"
            echo "3) Задать новый WRAP ключ / Сгенерировать случайный"
            read -p "Выбор [1-3]: " wc
            case "$wc" in
                1)
                    if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then
                        set_conf "WRAP_ENABLED" "0"; echo -e "${YELLOW}WRAP выключен.${NC}"
                    else
                        set_conf "WRAP_ENABLED" "1"; echo -e "${GREEN}WRAP включен.${NC}"
                    fi
                    apply_and_restart_service ;;
                2)
                    CWK=$(get_conf "WRAP_KEY")
                    if [[ -n "$CWK" ]]; then echo -e "Ключ: ${YELLOW}$CWK${NC}"; else echo "Ключ не задан (будет сгенерирован автоматически)."; fi ;;
                3)
                    echo -e "Вы можете вставить свой 64-символьный hex ключ."
                    echo -e "Или введите ${CYAN}gen${NC}, чтобы сгенерировать случайный ключ."
                    read -p "Ввод (или Enter для сброса): " iwk
                    if [[ "$iwk" == "gen" ]]; then
                        NK=$(generate_wrap_key); set_conf "WRAP_KEY" "$NK"
                        echo -e "${GREEN}Новый ключ: $NK${NC}"
                    else
                        set_conf "WRAP_KEY" "$iwk"
                    fi
                    apply_and_restart_service ;;
            esac
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        11)
            echo -e "${CYAN}Кастомные аргументы (Raw command)${NC}"
            echo -e "Внимание: при задании кастомных аргументов порты/VLESS/WRAP из панели игнорируются."
            read -p "Введи аргументы (или Enter для сброса на авто): " ic
            set_conf "CUSTOM_ARGS" "$ic"
            if [[ -z "$ic" ]]; then echo -e "${GREEN}Сброшено на авто!${NC}"; else echo -e "${GREEN}Сохранено!${NC}"; fi
            apply_and_restart_service; read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        12)
            echo -e "${CYAN}Управление VPN:${NC}"
            echo "1) WireGuard"
            echo "2) AmneziaWG"
            echo "3) Hysteria2"
            read -p "Выбор: " vmc
            mkdir -p "$CLIENTS_DIR"
            cd "$CLIENTS_DIR" || cd /root
            if [[ "$vmc" == "1" ]]; then
                if [ ! -f /root/wireguard-install.sh ]; then curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; chmod +x /root/wireguard-install.sh; fi
                bash /root/wireguard-install.sh
            elif [[ "$vmc" == "2" ]]; then
                if [ ! -f /root/amneziawg-install.sh ]; then curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; chmod +x /root/amneziawg-install.sh; fi
                bash /root/amneziawg-install.sh
            elif [[ "$vmc" == "3" ]]; then
                if [ ! -f /root/hysteria-install.sh ]; then curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; chmod +x /root/hysteria-install.sh; fi
                bash /root/hysteria-install.sh
            fi
            cd /root
            mv /root/*.conf "$CLIENTS_DIR"/ 2>/dev/null
            mv /root/*.yaml "$CLIENTS_DIR"/ 2>/dev/null
            mv /root/*.yml "$CLIENTS_DIR"/ 2>/dev/null
            mv /root/*.json "$CLIENTS_DIR"/ 2>/dev/null
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        13)
            CLIENT_CONFS=()
            while IFS= read -r file; do CLIENT_CONFS+=("$file"); done < <(find "$CLIENTS_DIR" -type f \( -name "*.conf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.txt" \) -print 2>/dev/null)
            if [ ${#CLIENT_CONFS[@]} -gt 0 ]; then
                echo -e "${CYAN}Доступные конфигурации в $CLIENTS_DIR:${NC}"
                for i in "${!CLIENT_CONFS[@]}"; do echo "$((i+1)). $(basename "${CLIENT_CONFS[$i]}")"; done
                read -p "Номер файла (0 для отмены): " qrc
                if [[ "$qrc" -ge 1 && "$qrc" -le ${#CLIENT_CONFS[@]} ]]; then qrencode -t ansiutf8 < "${CLIENT_CONFS[$((qrc-1))]}"; fi
            else echo -e "${RED}Конфигов в $CLIENTS_DIR не найдено.${NC}"; fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        14)
            echo -e "${CYAN}TCP BBR${NC}"
            if command -v sysctl &> /dev/null; then
                CURRENT_BBR=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
                if [[ "$CURRENT_BBR" == "bbr" ]]; then
                    echo -e "${GREEN}BBR включен.${NC}"
                    read -p "Выключить и сбросить на cubic? [y/N]: " dbbr
                    if [[ "$dbbr" =~ ^[Yy]$ ]]; then
                        sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
                        sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
                        sed -i '/net.ipv4.tcp_congestion_control=cubic/d' /etc/sysctl.conf
                        echo "net.ipv4.tcp_congestion_control=cubic" >> /etc/sysctl.conf
                        sysctl -p > /dev/null 2>&1
                        echo -e "${YELLOW}BBR выключен, алгоритм: cubic.${NC}"
                    fi
                else
                    echo -e "Текущий алгоритм: ${YELLOW}${CURRENT_BBR:-?}${NC}"
                    read -p "Включить BBR? [y/N]: " ebbr
                    if [[ "$ebbr" =~ ^[Yy]$ ]]; then
                        sed -i '/net.ipv4.tcp_congestion_control=/d' /etc/sysctl.conf
                        sed -i '/net.core.default_qdisc=/d' /etc/sysctl.conf
                        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
                        sysctl -p > /dev/null 2>&1
                        echo -e "${GREEN}BBR включен!${NC}"
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        15)
            BACKUP_NAME="vk-proxy-backup-$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
            BACKUP_PATH="/root/$BACKUP_NAME"
            echo "Архивация..."
            tar -czf "$BACKUP_PATH" \
                "$CONFIG_DIR" \
                "$CLIENTS_DIR" \
                /root/server-linux-$SYS_ARCH \
                /etc/systemd/system/vk-proxy.service 2>/dev/null
            if [ -f "$BACKUP_PATH" ]; then
                echo -e "${GREEN}Backup создан: ${YELLOW}$BACKUP_PATH${NC}"
                echo "💡 Скачайте файл через SFTP/FileZilla."
            else
                echo -e "${RED}Ошибка архивации.${NC}"
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        16) journalctl -u vk-proxy -n 25 --no-pager; read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        17) bash <(curl -sfL --connect-timeout 10 "$INSTALLER_URL") --update-panel; echo -e "${GREEN}Обновлено!${NC}"; exit 0 ;;
        0) clear; exit 0 ;;
    esac
done
EOF
chmod +x /usr/local/bin/vk-panel
}

if [[ "$1" == "--update-panel" ]]; then echo "Обновление vk-panel до v${PANEL_VERSION}..."; create_panel; exit 0; fi

clear
echo "==================================================="
echo "   Ультимативный Установщик VPN + vk-turn-proxy    "
echo "==================================================="
echo ""
echo "[1/10] Установка зависимостей..."
if command -v apt-get &> /dev/null; then
    apt-get update -y > /dev/null 2>&1
    apt-get install -y curl wget jq ufw qrencode openssl > /dev/null 2>&1
elif command -v yum &> /dev/null; then
    yum install -y curl wget jq epel-release openssl > /dev/null 2>&1
    yum install -y ufw qrencode > /dev/null 2>&1
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

echo ""
echo "[2/10] Выбор реализации..."
echo -e "1) cacggghp/vk-turn-proxy (Оригинал)"
echo -e "2) kiper292/vk-turn-proxy (Форк, \e[9mподдержка WB Stream\e[0m)"
echo -e "3) Urtyom-Alyanov/turn-proxy (Rust)"
echo -e "4) Moroka8/vk-turn-proxy"
echo -e "5) alxmcp/vk-turn-proxy (Форк, \e[9mподдержка Yandex / SaluteJazz\e[0m)"
echo -e "6) samosvalishe/vk-turn-proxy"
echo -e "7) Свой репозиторий или прямая ссылка"
read -p "Выбор [1-7, По умолчанию: 1]: " repo_choice
case "${repo_choice:-1}" in
    1) PROXY_REPO="cacggghp/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
    2) PROXY_REPO="kiper292/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
    3) PROXY_REPO="Urtyom-Alyanov/turn-proxy"; set_conf "CORE_TYPE" "rust" ;;
    4) PROXY_REPO="Moroka8/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
    5) PROXY_REPO="alxmcp/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
    6) PROXY_REPO="samosvalishe/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
    7)
        read -p "owner/repo ИЛИ ссылка: " ci
        if [[ "$ci" =~ ^https?:// ]] && [[ ! "$ci" =~ ^https?://(www\.)?github\.com/[^/]+/[^/]+/?$ ]]; then
            PROXY_REPO="Прямая ссылка"; DOWNLOAD_URL_DIRECT="$ci"
        else
            PROXY_REPO=$(echo "$ci" | sed -E 's|^https?://github\.com/||' | sed 's/\.git$//' | awk -F/ '{print $1"/"$2}')
            if [[ -z "$PROXY_REPO" || "$PROXY_REPO" != *"/"* ]]; then PROXY_REPO="cacggghp/vk-turn-proxy"; fi
        fi
        echo -e "${CYAN}Какой тип аргументов использовать?${NC}"
        echo "1) Стандартные (Go)"
        echo "2) Rust"
        echo "3) Задать вручную (Raw command)"
        read -p "Твой выбор [1-3]: " cct
        if [[ "$cct" == "2" ]]; then set_conf "CORE_TYPE" "rust"
        elif [[ "$cct" == "3" ]]; then set_conf "CORE_TYPE" "custom"
        else set_conf "CORE_TYPE" "go"; fi
        ;;
    *) PROXY_REPO="cacggghp/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
esac
set_conf "PROXY_REPO" "$PROXY_REPO"

echo ""
echo "[3/10] Настройка внешнего порта прокси..."
DEFAULT_PROXY_PORT=56000
[[ "$(get_conf "CORE_TYPE")" == "rust" ]] && DEFAULT_PROXY_PORT=56040
while true; do
    read -p "Внешний порт (По умолчанию: $DEFAULT_PROXY_PORT): " IPP
    IPP=${IPP:-$DEFAULT_PROXY_PORT}
    if [[ "$IPP" =~ ^[0-9]+$ ]] && [ "$IPP" -ge 1 ] && [ "$IPP" -le 65535 ]; then
        set_conf "PROXY_PORT" "$IPP"; PROXY_PORT=$IPP; break
    else echo "⚠️ Некорректный порт."; fi
done

echo ""
echo "[4/10] Настройка VLESS..."
echo "1) Не использовать VLESS флаги"
echo "2) Включить стандартный VLESS (-vless)"
echo "3) Включить VLESS Bond (-vless -vless-bond)"
read -p "Выбор [1-3, По умолчанию: 1]: " vs
if [[ "$(get_conf "CORE_TYPE")" == "rust" ]]; then
    echo -e "${YELLOW}⚠️ Rust-ядро не поддерживает VLESS. Флаг будет проигнорирован.${NC}"
    set_conf "VLESS_MODE" "off"
else
    if [[ "$vs" == "3" ]]; then set_conf "VLESS_MODE" "vless-bond"
    elif [[ "$vs" == "2" ]]; then set_conf "VLESS_MODE" "vless"
    else set_conf "VLESS_MODE" "off"; fi
fi

echo ""
echo "[5/10] Настройка локального порта (цель для прокси)..."
echo "1) Установить WireGuard"
echo "2) Установить AmneziaWG"
echo "3) Установить Hysteria2"
echo "4) Ввести порт вручную"
read -p "Выбор [1-4]: " psc
TARGET_PORT=""
if [[ "$psc" == "4" ]]; then
    read -p "Локальный порт: " mp; TARGET_PORT=${mp:-51820}
elif [[ "$psc" == "3" ]]; then
    shopt -s nullglob; HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.yml /etc/hysteria/*.json); shopt -u nullglob
    if [ ${#HYS_CONFS[@]} -gt 0 ]; then
        echo "Найдены конфиги Hysteria2."
        read -p "Запустить установщик? [y/N]: " rh
        if [[ "$rh" =~ ^[Yy]$ ]]; then
            mkdir -p "$CLIENTS_DIR"; cd "$CLIENTS_DIR" || cd /root
            curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; bash /root/hysteria-install.sh
            cd /root; mv /root/*.yaml /root/*.yml /root/*.json "$CLIENTS_DIR"/ 2>/dev/null
            shopt -s nullglob; HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.yml /etc/hysteria/*.json "$CLIENTS_DIR"/*.yaml "$CLIENTS_DIR"/*.yml "$CLIENTS_DIR"/*.json); shopt -u nullglob
        fi
    else
        mkdir -p "$CLIENTS_DIR"; cd "$CLIENTS_DIR" || cd /root
        curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; bash /root/hysteria-install.sh
        cd /root; mv /root/*.yaml /root/*.yml /root/*.json "$CLIENTS_DIR"/ 2>/dev/null
        shopt -s nullglob; HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.yml /etc/hysteria/*.json "$CLIENTS_DIR"/*.yaml "$CLIENTS_DIR"/*.yml "$CLIENTS_DIR"/*.json); shopt -u nullglob
    fi
    if [ ${#HYS_CONFS[@]} -eq 1 ]; then
        TARGET_PORT=$(get_target_port_from_file "${HYS_CONFS[0]}")
    elif [ ${#HYS_CONFS[@]} -gt 1 ]; then
        for i in "${!HYS_CONFS[@]}"; do echo "$((i+1)). ${HYS_CONFS[$i]}"; done
        read -p "Номер: " cc; cc=${cc:-1}
        if [[ "$cc" -ge 1 && "$cc" -le ${#HYS_CONFS[@]} ]]; then
            TARGET_PORT=$(get_target_port_from_file "${HYS_CONFS[$((cc-1))]}")
        fi
    fi
elif [[ "$psc" == "2" ]]; then
    shopt -s nullglob; AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf); shopt -u nullglob
    if [ ${#AWG_CONFS[@]} -gt 0 ]; then
        read -p "Запустить установщик AmneziaWG? [y/N]: " ra
        if [[ "$ra" =~ ^[Yy]$ ]]; then
            mkdir -p "$CLIENTS_DIR"; cd "$CLIENTS_DIR" || cd /root
            curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; bash /root/amneziawg-install.sh
            cd /root; mv /root/*.conf "$CLIENTS_DIR"/ 2>/dev/null
            shopt -s nullglob; AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf "$CLIENTS_DIR"/*.conf); shopt -u nullglob
        fi
    else
        mkdir -p "$CLIENTS_DIR"; cd "$CLIENTS_DIR" || cd /root
        curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; bash /root/amneziawg-install.sh
        cd /root; mv /root/*.conf "$CLIENTS_DIR"/ 2>/dev/null
        shopt -s nullglob; AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf "$CLIENTS_DIR"/*.conf); shopt -u nullglob
    fi
    if [ ${#AWG_CONFS[@]} -eq 1 ]; then
        TARGET_PORT=$(get_target_port_from_file "${AWG_CONFS[0]}")
    elif [ ${#AWG_CONFS[@]} -gt 1 ]; then
        for i in "${!AWG_CONFS[@]}"; do echo "$((i+1)). ${AWG_CONFS[$i]}"; done
        read -p "Номер: " cc; cc=${cc:-1}
        if [[ "$cc" -ge 1 && "$cc" -le ${#AWG_CONFS[@]} ]]; then
            TARGET_PORT=$(get_target_port_from_file "${AWG_CONFS[$((cc-1))]}")
        fi
    fi
else
    shopt -s nullglob; WG_CONFS=(/etc/wireguard/*.conf); shopt -u nullglob
    if [ ${#WG_CONFS[@]} -gt 0 ]; then
        read -p "Запустить установщик WireGuard? [y/N]: " rw
        if [[ "$rw" =~ ^[Yy]$ ]]; then
            mkdir -p "$CLIENTS_DIR"; cd "$CLIENTS_DIR" || cd /root
            curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; bash /root/wireguard-install.sh
            cd /root; mv /root/*.conf "$CLIENTS_DIR"/ 2>/dev/null
            shopt -s nullglob; WG_CONFS=(/etc/wireguard/*.conf "$CLIENTS_DIR"/*.conf); shopt -u nullglob
        fi
    else
        mkdir -p "$CLIENTS_DIR"; cd "$CLIENTS_DIR" || cd /root
        curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; bash /root/wireguard-install.sh
        cd /root; mv /root/*.conf "$CLIENTS_DIR"/ 2>/dev/null
        shopt -s nullglob; WG_CONFS=(/etc/wireguard/*.conf "$CLIENTS_DIR"/*.conf); shopt -u nullglob
    fi
    if [ ${#WG_CONFS[@]} -eq 1 ]; then
        TARGET_PORT=$(get_target_port_from_file "${WG_CONFS[0]}")
    elif [ ${#WG_CONFS[@]} -gt 1 ]; then
        for i in "${!WG_CONFS[@]}"; do echo "$((i+1)). ${WG_CONFS[$i]}"; done
        read -p "Номер: " cc; cc=${cc:-1}
        if [[ "$cc" -ge 1 && "$cc" -le ${#WG_CONFS[@]} ]]; then
            TARGET_PORT=$(get_target_port_from_file "${WG_CONFS[$((cc-1))]}")
        fi
    fi
fi

if [[ -z "$TARGET_PORT" ]]; then
    echo -e "\033[0;33m⚠️ Порт не определён автоматически.\033[0m"
    read -p "Введи локальный порт: " TARGET_PORT
fi
TARGET_PORT=${TARGET_PORT:-51820}
set_conf "TARGET_PORT" "$TARGET_PORT"

echo ""
echo "[6/10] Загрузка ядра ($SYS_ARCH)..."
if [[ "$PROXY_REPO" == "Прямая ссылка" ]]; then
    wget -q --show-progress -O /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL_DIRECT"
    LATEST_TAG="Custom"
else
    API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"
    API_RESP=$(curl -s --connect-timeout 10 "$API_URL")
    LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
    if [[ "$PROXY_REPO" == *"Urtyom-Alyanov"* ]]; then
        DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "turn-proxy-server") | .browser_download_url' | head -n 1)
    else
        DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "server-linux-'"${SYS_ARCH}"'") | .browser_download_url' | head -n 1)
    fi
    wget -q --show-progress -O /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL"
fi
chmod +x /root/server-linux-$SYS_ARCH
set_conf "VERSION" "$LATEST_TAG"

echo ""
echo "[7/10] Настройка WRAP (Обфускация)..."
if [[ "$(get_conf "CORE_TYPE")" == "rust" ]]; then
    echo -e "${YELLOW}⚠️ Rust-ядро не поддерживает WRAP. Пропускаем.${NC}"
    set_conf "WRAP_ENABLED" "0"
else
    echo "1) Пропустить"
    echo "2) Включить (авто-генерация ключа)"
    echo "3) Включить и ввести свой 64-hex ключ"
    read -p "Выбор [1-3, По умолчанию: 1]: " wsc
    case "$wsc" in
        2)
            set_conf "WRAP_ENABLED" "1"
            NEW_KEY=$(generate_wrap_key)
            set_conf "WRAP_KEY" "$NEW_KEY"
            echo "✅ Сгенерирован ключ: $NEW_KEY"
            ;;
        3)
            set_conf "WRAP_ENABLED" "1"
            read -p "Твой 64-hex ключ: " iwk
            set_conf "WRAP_KEY" "$iwk"
            ;;
        *)
            set_conf "WRAP_ENABLED" "0"
            echo "WRAP пропущен."
            ;;
    esac
fi

echo ""
echo "[8/10] Настройка кастомных аргументов (Raw command)..."
echo "Обычно скрипт генерирует их автоматически на базе портов, но ты можешь задать команду вручную (Raw mode)."
echo "Внимание: при задании кастомных аргументов настройки портов/VLESS/WRAP из панели игнорируются."
read -p "Хочешь прописать кастомные аргументы запуска? [y/N]: " cac
if [[ "$cac" =~ ^[Yy]$ ]]; then
    read -p "Аргументы: " ic; set_conf "CUSTOM_ARGS" "$ic"
else
    set_conf "CUSTOM_ARGS" ""
fi

echo ""
echo "[9/10] Настройка службы..."
systemctl stop vk-proxy 2>/dev/null || true

# Используем ту же логику, что и в панели
CORE_TYPE=$(get_conf "CORE_TYPE"); CORE_TYPE=${CORE_TYPE:-"go"}
PROXY_PORT=$(get_conf "PROXY_PORT"); PROXY_PORT=${PROXY_PORT:-"56000"}
TARGET_PORT=$(get_conf "TARGET_PORT"); TARGET_PORT=${TARGET_PORT:-"51820"}

CUSTOM_ARGS=$(get_conf "CUSTOM_ARGS")
if [[ -n "$CUSTOM_ARGS" ]]; then
    EXEC_ARGS="$CUSTOM_ARGS"
else
    if [[ "$CORE_TYPE" == "rust" ]]; then
        EXEC_ARGS="-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000"
    else
        VLESS_FLAG=""
        VLESS_MODE=$(get_conf "VLESS_MODE")
        if [[ "$VLESS_MODE" == "vless" ]]; then VLESS_FLAG=" -vless"
        elif [[ "$VLESS_MODE" == "vless-bond" ]]; then VLESS_FLAG=" -vless -vless-bond"; fi

        DC_FLAG=""
        if [[ "$(get_conf "DC_MODE")" == "1" ]]; then
            JAZZ_ROOM=$(get_conf "JAZZ_ROOM")
            LINK=$(get_conf "YANDEX_LINK")
            if [[ -n "$JAZZ_ROOM" ]]; then DC_FLAG=" -jazz-room $JAZZ_ROOM -dc"
            elif [[ -n "$LINK" ]]; then DC_FLAG=" -yandex-link $LINK -dc"; fi
        fi

        WRAP_FLAG=""
        if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then
            WRAP_FLAG=" -wrap"
            WRAP_KEY=$(get_conf "WRAP_KEY")
            if [[ -z "$WRAP_KEY" ]]; then
                WRAP_KEY=$(generate_wrap_key)
                set_conf "WRAP_KEY" "$WRAP_KEY"
            fi
            WRAP_FLAG="$WRAP_FLAG -wrap-key $WRAP_KEY"
        fi

        EXEC_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT$DC_FLAG$VLESS_FLAG$WRAP_FLAG"
    fi
fi

cat <<EOF > /etc/systemd/system/vk-proxy.service
[Unit]
Description=VK TURN Proxy Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root
LimitNOFILE=1048576
ExecStart=/root/server-linux-$SYS_ARCH $EXEC_ARGS
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vk-proxy > /dev/null 2>&1
systemctl start vk-proxy
if command -v ufw &> /dev/null; then ufw allow $PROXY_PORT/tcp > /dev/null 2>&1; ufw allow $PROXY_PORT/udp > /dev/null 2>&1; fi

echo ""
echo "[10/10] Создание панели (vk-panel v${PANEL_VERSION})..."
create_panel

echo ""
echo "==================================================="
echo "✅ Установка полностью завершена!"
echo "Трафик прокси направляется на локальный порт: $TARGET_PORT"
echo "Внешний порт прокси: $PROXY_PORT"
echo "📁 Новые файлы клиентов будут сохраняться в: $CLIENTS_DIR"
echo "==================================================="
echo "⚠️  ВАЖНО ДЛЯ ОБЛАКОВ (Oracle, AWS, Yandex и др.):"
echo "Обязательно открой порт $PROXY_PORT (TCP/UDP) в панели"
echo "управления сервером на сайте твоего хостинг-провайдера!"
echo "==================================================="
echo "💡 Если у вас были старые или новые клиенты (конфиги) в /root,"
echo "переместите их в $CLIENTS_DIR вручную для"
echo "отображения в панели управления."
echo "==================================================="
echo "🔥 Для вызова панели управления просто напиши: vk-panel"
echo "==================================================="
