#!/bin/bash

# === НАСТРОЙКИ ===
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"

if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (команда: sudo bash)"
  exit 1
fi

# === ФУНКЦИЯ СОЗДАНИЯ ПАНЕЛИ ===
create_panel() {
cat << 'EOF' > /usr/local/bin/vk-panel
#!/bin/bash
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

# Принудительно получаем IPv4
PUBLIC_IP=$(curl -4 -s ifconfig.me || curl -s https://api.ipify.org)

if [[ -f /root/.vk-proxy-version ]]; then CURRENT_VERSION=$(cat /root/.vk-proxy-version); else CURRENT_VERSION="Неизвестно"; fi
if [[ -f /root/.vk-proxy-port ]]; then PROXY_PORT=$(cat /root/.vk-proxy-port); else PROXY_PORT="56000"; fi

# Получаем целевой порт (с защитой от старых версий скрипта)
if [[ -f /root/.vk-proxy-target-port ]]; then 
    TARGET_PORT=$(cat /root/.vk-proxy-target-port)
else 
    TARGET_PORT=$(grep -oP '(?:-connect |-p )127\.0\.0\.1:\K\d+' /etc/systemd/system/vk-proxy.service | head -1)
    TARGET_PORT=${TARGET_PORT:-51820}
    echo "$TARGET_PORT" > /root/.vk-proxy-target-port
fi

# Читаем и мигрируем репозиторий
if [[ -f /root/.vk-proxy-repo ]]; then 
    PROXY_REPO=$(cat /root/.vk-proxy-repo)
    if [[ "$PROXY_REPO" != *"/"* ]]; then
        if [[ "$PROXY_REPO" == "Urtyom-Alyanov" ]]; then
            PROXY_REPO="Urtyom-Alyanov/turn-proxy"
        else
            PROXY_REPO="${PROXY_REPO}/vk-turn-proxy"
        fi
        echo "$PROXY_REPO" > /root/.vk-proxy-repo
    fi
else 
    PROXY_REPO="cacggghp/vk-turn-proxy"
fi

get_download_url() {
    local api_resp="$1"
    local arch="$2"
    local repo="$3"
    local url=""
    
    if [[ "$repo" == *"Urtyom-Alyanov"* ]]; then
        url=$(echo "$api_resp" | jq -r '.assets[] | select(.name == "turn-proxy-server") | .browser_download_url' | head -n 1)
    else
        url=$(echo "$api_resp" | jq -r '.assets[] | select(.name == "server-linux-'"${arch}"'") | .browser_download_url' | head -n 1)
    fi
    echo "$url"
}

while true; do
    clear
    echo "========================================="
    echo -e "${CYAN}      VK TURN Proxy Manager v1.3${NC}     "
    echo "========================================="
    if systemctl is-active --quiet vk-proxy; then echo -e "Статус прокси: ${GREEN}Активен (Работает)${NC}"; else echo -e "Статус прокси: ${RED}Остановлен${NC}"; fi
    echo -e "Текущая версия: ${YELLOW}${CURRENT_VERSION}${NC} [Реализация: ${CYAN}${PROXY_REPO}${NC}]"
    echo "Данные для приложения (Peer): $PUBLIC_IP:$PROXY_PORT"
    echo "========================================="
    echo "1.  🟢 Запустить прокси"
    echo "2.  🔴 Остановить прокси"
    echo "3.  🔄 Перезапустить"
    echo "4.  📥 Обновить ядро прокси"
    echo "5.  📊 Посмотреть логи"
    echo "6.  ➕ Управление WireGuard (Добавить/Удалить)"
    echo "7.  📱 Показать QR-код существующего WG-клиента"
    echo "8.  ⚙️  Обновить саму панель vk-panel"
    echo "9.  🗑️  Полностью удалить vk-turn-proxy"
    echo "10. 🔀 Сменить реализацию ядра"
    echo "0.  ❌ Выйти"
    echo "========================================="
    read -p "Выбери действие: " choice

    API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"

    case $choice in
        1) systemctl start vk-proxy; echo -e "${GREEN}Запущено!${NC}"; sleep 1 ;;
        2) systemctl stop vk-proxy; echo -e "${RED}Остановлено!${NC}"; sleep 1 ;;
        3) if systemctl restart vk-proxy; then echo -e "${GREEN}Успешно перезапущено!${NC}"; else echo -e "${RED}Ошибка перезапуска! Проверьте логи (Пункт 5).${NC}"; fi; sleep 2 ;;
        4)
            echo "Проверка обновлений через GitHub API ($PROXY_REPO)..."
            API_RESP=$(curl -s "$API_URL")
            LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
            
            if [[ "$LATEST_TAG" == "null" || -z "$LATEST_TAG" ]]; then
                echo -e "${RED}Ошибка API GitHub (возможно исчерпан лимит). Попробуй позже.${NC}"; read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi

            if [[ "$LATEST_TAG" == "$CURRENT_VERSION" ]]; then
                echo -e "${GREEN}У вас уже установлена актуальная версия ($CURRENT_VERSION)!${NC}"
            else
                echo -e "Доступна новая версия: ${YELLOW}$LATEST_TAG${NC} (текущая: $CURRENT_VERSION)"
                read -p "Хотите обновить? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    DOWNLOAD_URL=$(get_download_url "$API_RESP" "$SYS_ARCH" "$PROXY_REPO")
                    if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
                        echo -e "${RED}Ошибка получения ссылки на скачивание. Отмена.${NC}"
                    else
                        echo "Скачивание обновления..."
                        if wget -qO /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                            systemctl stop vk-proxy
                            mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                            chmod +x /root/server-linux-$SYS_ARCH
                            echo "$LATEST_TAG" > /root/.vk-proxy-version
                            systemctl start vk-proxy
                            CURRENT_VERSION=$LATEST_TAG
                            echo -e "${GREEN}Успешно обновлено до $LATEST_TAG!${NC}"
                        else
                            echo -e "${RED}Ошибка скачивания файла обновления.${NC}"
                        fi
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        5) journalctl -u vk-proxy -n 20 --no-pager; read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        6) 
            if [ -f /root/wireguard-install.sh ]; then 
                bash /root/wireguard-install.sh
            else 
                echo -e "${RED}Установщик WG не найден. Запустите установку через основной скрипт.${NC}"
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." 
            ;;
        7)
            echo ""
            echo -e "${CYAN}Доступные конфигурации WG-клиентов:${NC}"
            shopt -s nullglob
            CLIENT_CONFS=(/root/*.conf)
            shopt -u nullglob

            if [ ${#CLIENT_CONFS[@]} -eq 0 ]; then
                echo -e "${RED}Файлы конфигурации клиентов (.conf) не найдены в /root/${NC}"
            else
                for i in "${!CLIENT_CONFS[@]}"; do
                    echo "$((i+1)). $(basename "${CLIENT_CONFS[$i]}")"
                done
                echo ""
                read -p "Выбери номер клиента для показа QR-кода: " qr_choice
                if [[ "$qr_choice" -ge 1 && "$qr_choice" -le ${#CLIENT_CONFS[@]} ]]; then
                    TARGET_CONF="${CLIENT_CONFS[$((qr_choice-1))]}"
                    echo -e "${GREEN}QR-код для $(basename "$TARGET_CONF"):${NC}"
                    qrencode -t ansiutf8 < "$TARGET_CONF"
                else
                    echo -e "${RED}Неверный выбор.${NC}"
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." 
            ;;
        8)
            echo -e "${YELLOW}Скачивание обновления панели...${NC}"
            bash <(curl -sL "$INSTALLER_URL") --update-panel
            echo -e "${GREEN}Панель обновлена! Перезапустите команду vk-panel.${NC}"
            exit 0 ;;
        9)
            echo -e "${RED}ВНИМАНИЕ: Это удалит службу и бинарник прокси! Остальные VPN (WG, Xray, Hysteria) останутся нетронутыми.${NC}"
            read -p "Вы АБСОЛЮТНО уверены? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop vk-proxy; systemctl disable vk-proxy; rm -f /etc/systemd/system/vk-proxy.service; systemctl daemon-reload
                if command -v ufw &> /dev/null; then ufw delete allow $PROXY_PORT/tcp >/dev/null 2>&1; ufw delete allow $PROXY_PORT/udp >/dev/null 2>&1; fi
                rm -f /root/server-linux-$SYS_ARCH /root/.vk-proxy-version /usr/local/bin/vk-panel /root/.vk-proxy-repo /root/.vk-proxy-port /root/.vk-proxy-target-port
                echo -e "${GREEN}Прокси успешно удален.${NC}"; exit 0
            fi ;;
        10)
            echo -e "${YELLOW}======================================================${NC}"
            echo -e "${YELLOW}ВНИМАНИЕ: При смене реализации ваши текущие клиенты   ${NC}"
            echo -e "${YELLOW}могут перестать подключаться! Возможно, потребуется   ${NC}"
            echo -e "${YELLOW}перенастройка на стороне клиента или его смена.       ${NC}"
            echo -e "${YELLOW}======================================================${NC}"
            echo -e "Текущая реализация: ${CYAN}${PROXY_REPO}${NC}"
            echo "Доступные реализации:"
            echo "1) cacggghp/vk-turn-proxy (Оригинал)"
            echo "2) kiper292/vk-turn-proxy (Поддержка WB Stream)"
            echo "3) Urtyom-Alyanov/turn-proxy (Ядро на Rust, только amd64/x86_64)"
            echo "4) Moroka8/vk-turn-proxy (Поддержка VLESS, флаг -vless)"
            echo "0) Отмена"
            read -p "Выберите новую реализацию [1-4 или 0]: " repo_choice
            
            case "$repo_choice" in
                1) NEW_REPO="cacggghp/vk-turn-proxy" ;;
                2) NEW_REPO="kiper292/vk-turn-proxy" ;;
                3) NEW_REPO="Urtyom-Alyanov/turn-proxy" ;;
                4) NEW_REPO="Moroka8/vk-turn-proxy" ;;
                0) continue ;;
                *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1; continue ;;
            esac
            
            if [[ "$NEW_REPO" == "$PROXY_REPO" ]]; then
                echo -e "${YELLOW}Эта реализация уже установлена!${NC}"; sleep 1; continue
            fi
            
            read -p "Вы уверены, что хотите сменить на $NEW_REPO? [y/N]: " confirm_switch
            if [[ "$confirm_switch" =~ ^[Yy]$ ]]; then
                echo "Получение данных с GitHub ($NEW_REPO)..."
                NEW_API_URL="https://api.github.com/repos/${NEW_REPO}/releases/latest"
                API_RESP=$(curl -s "$NEW_API_URL")
                LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
                
                if [[ "$LATEST_TAG" == "null" || -z "$LATEST_TAG" ]]; then
                    echo -e "${RED}Ошибка API GitHub (возможно исчерпан лимит или нет релизов). Отмена.${NC}"
                else
                    DOWNLOAD_URL=$(get_download_url "$API_RESP" "$SYS_ARCH" "$NEW_REPO")
                    if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
                        echo -e "${RED}Ошибка получения релиза $NEW_REPO. Возможно бинарник не опубликован. Отмена.${NC}"
                    else
                        echo "Скачивание ядра..."
                        if wget -qO /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                            systemctl stop vk-proxy
                            mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                            chmod +x /root/server-linux-$SYS_ARCH
                            
                            # Переписываем аргументы службы под новое ядро
                            if [[ "$NEW_REPO" == *"Urtyom-Alyanov"* ]]; then
                                EXEC_ARGS="-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000"
                            elif [[ "$NEW_REPO" == *"Moroka8"* ]]; then
                                EXEC_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT -vless"
                            else
                                EXEC_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT"
                            fi

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
                            
                            echo "$NEW_REPO" > /root/.vk-proxy-repo
                            echo "$LATEST_TAG" > /root/.vk-proxy-version
                            systemctl start vk-proxy
                            PROXY_REPO=$NEW_REPO
                            CURRENT_VERSION=$LATEST_TAG
                            echo -e "${GREEN}Успешно изменено на реализацию $NEW_REPO ($LATEST_TAG)!${NC}"
                        else
                            echo -e "${RED}Ошибка скачивания ядра. Отмена.${NC}"
                        fi
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..."
            ;;
        0) clear; exit 0 ;;
        *) echo "Неверный выбор!"; sleep 1 ;;
    esac
done
EOF
chmod +x /usr/local/bin/vk-panel
}

# 0. Быстрое обновление только панели (скрытый режим)
if [[ "$1" == "--update-panel" ]]; then
    echo "Обновление панели vk-panel..."
    create_panel
    exit 0
fi

clear
echo "==================================================="
echo "   Ультимативный Установщик VPN + vk-turn-proxy    "
echo "==================================================="
echo ""

# 1. Проверка зависимостей
echo "[1/8] Установка зависимостей (curl, wget, jq, ufw, qrencode)..."
if command -v apt-get &> /dev/null; then
    apt-get update -y > /dev/null 2>&1
    apt-get install -y curl wget jq ufw qrencode > /dev/null 2>&1
elif command -v yum &> /dev/null; then
    yum install -y curl wget jq epel-release > /dev/null 2>&1
    yum install -y ufw qrencode > /dev/null 2>&1
fi

# 2. Архитектура
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

# 3. Выбор реализации
echo ""
echo "[2/8] Выбор реализации vk-turn-proxy..."
echo "1) cacggghp/vk-turn-proxy (Оригинал, по умолчанию)"
echo "2) kiper292/vk-turn-proxy (Поддержка WB Stream)"
echo "3) Urtyom-Alyanov/turn-proxy (Ядро на Rust, только amd64/x86_64)"
echo "4) Moroka8/vk-turn-proxy (Поддержка VLESS, флаг -vless)"
read -p "Твой выбор [1-4]: " repo_choice

case "$repo_choice" in
  2) PROXY_REPO="kiper292/vk-turn-proxy" ;;
  3) PROXY_REPO="Urtyom-Alyanov/turn-proxy" ;;
  4) PROXY_REPO="Moroka8/vk-turn-proxy" ;;
  *) PROXY_REPO="cacggghp/vk-turn-proxy" ;;
esac

echo "$PROXY_REPO" > /root/.vk-proxy-repo
API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"

# 4. Выбор порта прокси
echo ""
echo "[3/8] Настройка внешнего порта прокси (к нему будут подключаться клиенты через VK)..."
DEFAULT_PROXY_PORT=56000
if [[ "$PROXY_REPO" == "Urtyom-Alyanov/turn-proxy" ]]; then
    DEFAULT_PROXY_PORT=56040
fi

while true; do
    read -p "Введи внешний порт прокси (нажми Enter для $DEFAULT_PROXY_PORT): " INPUT_PROXY_PORT
    if [[ -z "$INPUT_PROXY_PORT" ]]; then
        INPUT_PROXY_PORT="$DEFAULT_PROXY_PORT"
    fi

    if [[ "$INPUT_PROXY_PORT" =~ ^[0-9]+$ ]] && [ "$INPUT_PROXY_PORT" -ge 1 ] && [ "$INPUT_PROXY_PORT" -le 65535 ]; then
        if command -v ss &> /dev/null && ss -tuln | grep -qE ":$INPUT_PROXY_PORT\b"; then
            echo "⚠️ Ошибка: Порт $INPUT_PROXY_PORT уже занят другим приложением. Выбери другой."
        else
            PROXY_PORT="$INPUT_PROXY_PORT"
            break
        fi
    else
        echo "⚠️ Ошибка: Введи корректный порт от 1 до 65535."
    fi
done

echo "$PROXY_PORT" > /root/.vk-proxy-port
echo "Выбран внешний порт: $PROXY_PORT"

# 5. Выбор типа установки и настройка целевого локального порта
echo ""
echo "[4/8] Настройка локального порта (цель для прокси)..."
echo "Куда прокси должен перенаправлять трафик?"
echo "1) Установить WireGuard с нуля (автоматически установит и привяжет порт)"
echo "2) Ввести порт вручную (если WireGuard, Hysteria2, Xray или 3X-UI уже установлены)"
read -p "Твой выбор [1/2]: " port_setup_choice

TARGET_PORT=""

if [[ "$port_setup_choice" == "2" ]]; then
    echo ""
    read -p "Введи локальный порт (например, 51820 для WG, 443 для Hysteria2/Xray/VLESS): " manual_port
    if [[ "$manual_port" =~ ^[0-9]+$ ]] && [ "$manual_port" -ge 1 ] && [ "$manual_port" -le 65535 ]; then
        TARGET_PORT="$manual_port"
        echo "Выбран ручной порт: $TARGET_PORT"
    else
        echo "Ошибка: введено некорректное значение порта. Используем стандартный порт WG: 51820"
        TARGET_PORT=51820
    fi
else
    # 6. WireGuard: Проверка и установка
    echo ""
    echo "[5/8] Установка и поиск порта WireGuard..."
    shopt -s nullglob
    WG_CONFS=(/etc/wireguard/*.conf)
    shopt -u nullglob

    if [ ${#WG_CONFS[@]} -gt 0 ]; then
        echo "Найдены существующие конфигурации WireGuard."
        read -p "Хочешь запустить установщик WireGuard? (выбери N, если WG уже настроен) [y/N]: " run_wg
        if [[ "$run_wg" =~ ^[Yy]$ ]]; then
            if curl -sLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; then
                chmod +x /root/wireguard-install.sh
                bash /root/wireguard-install.sh
            else
                echo "❌ Ошибка скачивания установщика WireGuard."
            fi
            shopt -s nullglob
            WG_CONFS=(/etc/wireguard/*.conf)
            shopt -u nullglob
        else
            echo "Пропускаем установку WireGuard..."
        fi
    else
        if curl -sLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; then
            chmod +x /root/wireguard-install.sh
            bash /root/wireguard-install.sh
        else
            echo "❌ Ошибка скачивания установщика WireGuard."
        fi
        shopt -s nullglob
        WG_CONFS=(/etc/wireguard/*.conf)
        shopt -u nullglob
    fi

    # Умный поиск порта из файлов WG
    if [ ${#WG_CONFS[@]} -eq 1 ]; then
        TARGET_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' "${WG_CONFS[0]}")
        echo "Автоматически выбран конфиг: ${WG_CONFS[0]}"
    elif [ ${#WG_CONFS[@]} -gt 1 ]; then
        echo "Найдено несколько конфигураций:"
        for i in "${!WG_CONFS[@]}"; do echo "$((i+1)). ${WG_CONFS[$i]}"; done
        read -p "Выбери номер конфига для привязки прокси: " conf_choice
        conf_choice=${conf_choice:-1}
        if [[ "$conf_choice" -ge 1 && "$conf_choice" -le ${#WG_CONFS[@]} ]]; then
            TARGET_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' "${WG_CONFS[$((conf_choice-1))]}")
        fi
    fi

    if [[ -z "$TARGET_PORT" ]]; then
        read -p "Не удалось найти порт. Введи целевой порт вручную: " TARGET_PORT
    else
        echo "Порт определен: $TARGET_PORT"
    fi
fi

# Сохраняем целевой порт для перегенерации службы в будущем
echo "$TARGET_PORT" > /root/.vk-proxy-target-port

# 7. Скачивание ядра
echo ""
echo "[6/8] Загрузка ядра ($SYS_ARCH) из репозитория $PROXY_REPO..."
API_RESP=$(curl -s "$API_URL")
LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
DOWNLOAD_URL=""

if [[ "$PROXY_REPO" == *"Urtyom-Alyanov"* ]]; then
    # Для Rust-ядра берем конкретный файл
    DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "turn-proxy-server") | .browser_download_url' | head -n 1)
else
    # Для остальных ищем стандартное имя
    DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "server-linux-'"${SYS_ARCH}"'") | .browser_download_url' | head -n 1)
fi

if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
    echo "Ошибка получения ссылки на бинарник. Лимит API GitHub, или нет готовых сборок под $SYS_ARCH в репозитории $PROXY_REPO."
    echo "Для справки: ядро на Rust в данный момент публикует только amd64 бинарники."
    exit 1
fi

# Сохраняем всегда под одним стандартным именем, чтобы не менять systemd
if ! wget -qO /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
    echo "❌ Ошибка: Не удалось скачать ядро прокси. Проверьте интернет или лимиты GitHub API."
    exit 1
fi
chmod +x /root/server-linux-$SYS_ARCH
echo "$LATEST_TAG" > /root/.vk-proxy-version

# 8. Служба и Фаервол
echo ""
echo "[7/8] Настройка службы и фаервола..."
systemctl stop vk-proxy 2>/dev/null || true

# Генерируем правильные аргументы в зависимости от ядра
if [[ "$PROXY_REPO" == *"Urtyom-Alyanov"* ]]; then
    EXEC_ARGS="-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000"
elif [[ "$PROXY_REPO" == *"Moroka8"* ]]; then
    EXEC_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT -vless"
else
    EXEC_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT"
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

if command -v ufw &> /dev/null; then
    echo "Открываем порт $PROXY_PORT в UFW..."
    ufw allow $PROXY_PORT/tcp > /dev/null 2>&1
    ufw allow $PROXY_PORT/udp > /dev/null 2>&1
fi

# 9. Панель
echo ""
echo "[8/8] Создание консольной панели (vk-panel)..."
create_panel

echo ""
echo "==================================================="
echo "✅ Установка полностью завершена!"
echo "Трафик прокси направляется на локальный порт: $TARGET_PORT"
echo "Внешний порт прокси для подключения: $PROXY_PORT"
echo "==================================================="
echo "⚠️  ВАЖНО ДЛЯ ОБЛАКОВ (Oracle, AWS, Yandex и др.):"
echo "Обязательно открой порт $PROXY_PORT (TCP/UDP) в панели"
echo "управления сервером на сайте твоего хостинг-провайдера!"
echo "==================================================="
echo "🔥 Для вызова панели управления просто напиши:"
echo "vk-panel"
echo "==================================================="
