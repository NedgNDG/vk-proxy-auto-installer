#!/bin/bash

# === НАСТРОЙКИ ===
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"
API_URL="https://api.github.com/repos/kiper292/vk-turn-proxy/releases/latest"

# 0. Быстрое обновление только панели (скрытый режим)
if [[ "$1" == "--update-panel" ]]; then
    echo "Обновление панели vk-panel..."
    # Логика вынесена в функцию ниже, вызываем ее и выходим
fi

if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (команда: sudo bash)"
  exit 1
fi

# === ФУНКЦИЯ СОЗДАНИЯ ПАНЕЛИ ===
create_panel() {
cat << 'EOF' > /usr/local/bin/vk-panel
#!/bin/bash
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"
API_URL="https://api.github.com/repos/kiper292/vk-turn-proxy/releases/latest"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi
PUBLIC_IP=$(curl -s ifconfig.me)

if [[ -f /root/.vk-proxy-version ]]; then CURRENT_VERSION=$(cat /root/.vk-proxy-version); else CURRENT_VERSION="Неизвестно"; fi

while true; do
    clear
    echo "========================================="
    echo -e "${CYAN}      VK TURN Proxy Manager v2.1${NC}     "
    echo "========================================="
    if systemctl is-active --quiet vk-proxy; then echo -e "Статус прокси: ${GREEN}Активен (Работает)${NC}"; else echo -e "Статус прокси: ${RED}Остановлен${NC}"; fi
    echo -e "Текущая версия: ${YELLOW}${CURRENT_VERSION}${NC}"
    echo "Данные для приложения (Peer): $PUBLIC_IP:56000"
    echo "========================================="
    echo "1. 🟢 Запустить прокси"
    echo "2. 🔴 Остановить прокси"
    echo "3. 🔄 Перезапустить"
    echo "4. 📥 Обновить прокси (Умное обновление)"
    echo "5. 📊 Посмотреть логи"
    echo "6. ➕ Управление WireGuard (Добавить/Удалить)"
    echo "7. 📱 Показать QR-код существующего клиента"
    echo "8. ⚙️  Обновить саму панель vk-panel"
    echo "9. 🗑️  Полностью удалить vk-turn-proxy"
    echo "0. ❌ Выйти"
    echo "========================================="
    read -p "Выбери действие: " choice

    case $choice in
        1) systemctl start vk-proxy; echo -e "${GREEN}Запущено!${NC}"; sleep 1 ;;
        2) systemctl stop vk-proxy; echo -e "${RED}Остановлено!${NC}"; sleep 1 ;;
        3) systemctl restart vk-proxy; echo -e "${GREEN}Перезапущено!${NC}"; sleep 1 ;;
        4)
            echo "Проверка обновлений через GitHub API..."
            API_RESP=$(curl -s $API_URL)
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
                    DOWNLOAD_URL=$(echo "$API_RESP" | jq -r ".assets[] | select(.name == \"server-linux-${SYS_ARCH}\") | .browser_download_url")
                    systemctl stop vk-proxy
                    rm -f /root/server-linux-$SYS_ARCH
                    wget -qO /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL"
                    chmod +x /root/server-linux-$SYS_ARCH
                    echo "$LATEST_TAG" > /root/.vk-proxy-version
                    systemctl start vk-proxy
                    echo -e "${GREEN}Успешно обновлено до $LATEST_TAG!${NC}"
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        5) journalctl -u vk-proxy -n 20 --no-pager; read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        6) 
            if [ -f /root/wireguard-install.sh ]; then 
                bash /root/wireguard-install.sh
            else 
                echo -e "${RED}Установщик WG не найден.${NC}"
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." 
            ;;
        7)
            echo ""
            echo -e "${CYAN}Доступные конфигурации клиентов:${NC}"
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
            echo -e "${RED}ВНИМАНИЕ: Это удалит службу и бинарник прокси! WireGuard останется.${NC}"
            read -p "Вы АБСОЛЮТНО уверены? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop vk-proxy; systemctl disable vk-proxy; rm -f /etc/systemd/system/vk-proxy.service; systemctl daemon-reload
                if command -v ufw &> /dev/null; then ufw delete allow 56000/tcp >/dev/null 2>&1; ufw delete allow 56000/udp >/dev/null 2>&1; fi
                rm -f /root/server-linux-$SYS_ARCH /root/.vk-proxy-version /usr/local/bin/vk-panel
                echo -e "${GREEN}Прокси успешно удален.${NC}"; exit 0
            fi ;;
        0) clear; exit 0 ;;
        *) echo "Неверный выбор!"; sleep 1 ;;
    esac
done
EOF
chmod +x /usr/local/bin/vk-panel
}

# Если был передан флаг обновления панели, обновляем и выходим
if [[ "$1" == "--update-panel" ]]; then
    create_panel
    exit 0
fi

clear
echo "==================================================="
echo "   Ультимативный Установщик WG + vk-turn-proxy     "
echo "==================================================="
echo ""

# 1. Проверка зависимостей
echo "[1/7] Установка зависимостей (curl, wget, jq, ufw)..."
if command -v apt-get &> /dev/null; then
    apt-get update -y > /dev/null 2>&1
    apt-get install -y curl wget jq ufw > /dev/null 2>&1
elif command -v yum &> /dev/null; then
    yum install -y curl wget jq epel-release > /dev/null 2>&1
    yum install -y ufw > /dev/null 2>&1
fi

# 2. Архитектура
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

# 3. WireGuard: Проверка и установка
echo ""
echo "[2/7] Настройка WireGuard..."
shopt -s nullglob
WG_CONFS=(/etc/wireguard/*.conf)
shopt -u nullglob

if [ ${#WG_CONFS[@]} -gt 0 ]; then
    echo "Найдены существующие конфигурации WireGuard."
    read -p "Хочешь запустить установщик WireGuard? (выбери N, если WG уже настроен) [y/N]: " run_wg
    if [[ "$run_wg" =~ ^[Yy]$ ]]; then
        curl -O https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
        chmod +x wireguard-install.sh
        ./wireguard-install.sh
        # Обновляем список конфигов после установки
        shopt -s nullglob
        WG_CONFS=(/etc/wireguard/*.conf)
        shopt -u nullglob
    else
        echo "Пропускаем установку WireGuard..."
    fi
else
    curl -O https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
    chmod +x wireguard-install.sh
    ./wireguard-install.sh
    shopt -s nullglob
    WG_CONFS=(/etc/wireguard/*.conf)
    shopt -u nullglob
fi

# 4. Умный поиск порта
echo ""
echo "[3/7] Определение порта WireGuard..."
WG_PORT=""
if [ ${#WG_CONFS[@]} -eq 1 ]; then
    WG_PORT=$(grep "ListenPort" "${WG_CONFS[0]}" | awk '{print $3}')
    echo "Автоматически выбран конфиг: ${WG_CONFS[0]}"
elif [ ${#WG_CONFS[@]} -gt 1 ]; then
    echo "Найдено несколько конфигураций:"
    for i in "${!WG_CONFS[@]}"; do echo "$((i+1)). ${WG_CONFS[$i]}"; done
    read -p "Выбери номер конфига для привязки прокси: " conf_choice
    conf_choice=${conf_choice:-1}
    if [[ "$conf_choice" -ge 1 && "$conf_choice" -le ${#WG_CONFS[@]} ]]; then
        WG_PORT=$(grep "ListenPort" "${WG_CONFS[$((conf_choice-1))]}" | awk '{print $3}')
    fi
fi

if [[ -z "$WG_PORT" ]]; then
    read -p "Не удалось найти порт. Введи порт WireGuard вручную: " WG_PORT
else
    echo "Порт определен: $WG_PORT"
fi

# 5. Скачивание vk-turn-proxy через jq
echo ""
echo "[4/7] Загрузка vk-turn-proxy ($SYS_ARCH)..."
API_RESP=$(curl -s $API_URL)
DOWNLOAD_URL=$(echo "$API_RESP" | jq -r ".assets[] | select(.name == \"server-linux-${SYS_ARCH}\") | .browser_download_url")
LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")

if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
    echo "Ошибка получения ссылки. Лимит API GitHub или файл не найден."
    exit 1
fi

wget -qO /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL"
chmod +x /root/server-linux-$SYS_ARCH
echo "$LATEST_TAG" > /root/.vk-proxy-version

# 6. Служба и Фаервол
echo ""
echo "[5/7] Настройка службы и фаервола..."
pkill -f server-linux-$SYS_ARCH || true

cat <<EOF > /etc/systemd/system/vk-proxy.service
[Unit]
Description=VK TURN Proxy for WireGuard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/root/server-linux-$SYS_ARCH -listen 0.0.0.0:56000 -connect 127.0.0.1:$WG_PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vk-proxy > /dev/null 2>&1
systemctl start vk-proxy

if command -v ufw &> /dev/null && ufw status | grep -qiw "active"; then
    echo "Открываем порт 56000 в UFW..."
    ufw allow 56000/tcp > /dev/null 2>&1
    ufw allow 56000/udp > /dev/null 2>&1
fi

# 7. Панель
echo ""
echo "[6/7] Создание консольной панели (vk-panel)..."
create_panel

echo ""
echo "==================================================="
echo "✅ Установка полностью завершена!"
echo "Твой порт WG: $WG_PORT был успешно привязан."
echo "==================================================="
echo "⚠️  ВАЖНО ДЛЯ ОБЛАКОВ (Oracle, AWS, Yandex и др.):"
echo "Обязательно открой порт 56000 (TCP/UDP) в панели"
echo "управления сервером на сайте твоего хостинг-провайдера!"
echo "==================================================="
echo "🔥 Для вызова панели управления просто напиши:"
echo "vk-panel"
echo "==================================================="
