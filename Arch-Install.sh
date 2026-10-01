#!/bin/bash

set -euo pipefail

DYSK="/dev/sda"
HOSTNAME="Fabian-PC"
USERNAME="fabian"


instalacja_arch()
{
    echo
    echo "======================================"
    echo "      Instalacja Arch Linux"
    echo "======================================"
    echo
    echo "Wybrany dysk: $DYSK"
    echo
    lsblk "$DYSK"
    echo

    read -rp "UWAGA! CAŁY DYSK $DYSK ZOSTANIE WYMAZANY. Kontynuować? [YES/NO]: " potwierdzenie

    if [[ "$potwierdzenie" != "YES" ]]; then
        echo "Instalacja anulowana."
        exit 1
    fi


    # --------------------------------------
    # Klawiatura
    # --------------------------------------

    echo
    echo "Ustawianie polskiej klawiatury..."

    loadkeys pl


    # --------------------------------------
    # Sprawdzenie połączenia z Internetem
    # --------------------------------------

    echo
    echo "Sprawdzanie połączenia z Internetem..."

    if ! ping -c 3 archlinux.org &>/dev/null; then
        echo "Brak połączenia z Internetem!"
        echo "Skonfiguruj sieć przed uruchomieniem instalatora."
        exit 1
    fi


    # --------------------------------------
    # Partycjonowanie
    # --------------------------------------

    echo
    echo "Czyszczenie tablicy partycji..."

    sgdisk --zap-all "$DYSK"
    sgdisk -o "$DYSK"


    echo "Tworzenie partycji..."

    sgdisk \
        -n 1:0:+1G \
        -t 1:ef00 \
        -c 1:"EFI System Partition" \
        -n 2:0:+8G \
        -t 2:8200 \
        -c 2:"Linux Swap" \
        -n 3:0:0 \
        -t 3:8300 \
        -c 3:"Linux Root" \
        "$DYSK"


    # --------------------------------------
    # Formatowanie
    # --------------------------------------

    echo
    echo "Formatowanie partycji..."

    mkfs.fat -F32 "${DYSK}p1"
    mkswap "${DYSK}p2"
    mkfs.ext4 -F "${DYSK}p3"


    # --------------------------------------
    # Montowanie
    # --------------------------------------

    echo
    echo "Montowanie systemu plików..."

    swapon "${DYSK}p2"

    mount "${DYSK}p3" /mnt

    mkdir -p /mnt/boot/efi

    mount "${DYSK}p1" /mnt/boot/efi


    # --------------------------------------
    # Instalacja podstawowego systemu
    # --------------------------------------

    echo
    echo "Instalowanie Arch Linux..."

    pacstrap -K /mnt \
        base \
        linux \
        linux-firmware \
        sof-firmware \
        grub \
        efibootmgr \
        intel-ucode \
        networkmanager \
        sudo \
        nano


    # --------------------------------------
    # Fstab
    # --------------------------------------

    echo
    echo "Generowanie /etc/fstab..."

    genfstab -U /mnt > /mnt/etc/fstab


    # --------------------------------------
    # Hasło użytkownika
    # --------------------------------------

    echo
    read -rsp "Podaj hasło dla użytkownika $USERNAME: " HASLO
    echo

    read -rsp "Powtórz hasło: " HASLO2
    echo

    if [[ "$HASLO" != "$HASLO2" ]]; then
        echo "Hasła nie są takie same!"
        exit 1
    fi


    # --------------------------------------
    # Konfiguracja systemu w chroot
    # --------------------------------------

    echo
    echo "Konfigurowanie zainstalowanego systemu..."


    arch-chroot /mnt /bin/bash <<EOF

set -e

# --------------------------------------
# Strefa czasowa
# --------------------------------------

ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime

hwclock --systohc


# --------------------------------------
# Locale
# --------------------------------------

sed -i 's/^#pl_PL.UTF-8 UTF-8/pl_PL.UTF-8 UTF-8/' /etc/locale.gen

locale-gen

echo 'LANG=pl_PL.UTF-8' > /etc/locale.conf


# --------------------------------------
# Klawiatura
# --------------------------------------

echo 'KEYMAP=pl' > /etc/vconsole.conf


# --------------------------------------
# Hostname
# --------------------------------------

echo '$HOSTNAME' > /etc/hostname


# --------------------------------------
# Hosts
# --------------------------------------

cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS


# --------------------------------------
# Użytkownik
# --------------------------------------

useradd -m -G wheel -s /bin/bash $USERNAME

echo '$USERNAME:$HASLO' | chpasswd


# --------------------------------------
# Sudo
# --------------------------------------

echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

chmod 440 /etc/sudoers.d/wheel

visudo -c


# --------------------------------------
# GRUB
# --------------------------------------

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=GRUB \
    --recheck


# --------------------------------------
# GRUB_DISABLE_BOOTNEXT
# --------------------------------------

if grep -q '^GRUB_DISABLE_BOOTNEXT=' /etc/default/grub; then
    sed -i 's/^GRUB_DISABLE_BOOTNEXT=.*/GRUB_DISABLE_BOOTNEXT=true/' /etc/default/grub
else
    echo 'GRUB_DISABLE_BOOTNEXT=true' >> /etc/default/grub
fi


# --------------------------------------
# Generowanie konfiguracji GRUB
# --------------------------------------

grub-mkconfig -o /boot/grub/grub.cfg


# --------------------------------------
# NetworkManager
# --------------------------------------

systemctl enable NetworkManager


# --------------------------------------
# Initramfs
# --------------------------------------

mkinitcpio -P

EOF


    # --------------------------------------
    # Koniec instalacji
    # --------------------------------------

    echo
    echo "======================================"
    echo "     Instalacja zakończona!"
    echo "======================================"
    echo
    echo "Możesz teraz zrestartować komputer."
    echo
    echo "Wykonaj:"
    echo
    echo "    umount -R /mnt"
    echo "    swapoff ${DYSK}p2"
    echo "    reboot"
    echo

}


# ==========================================
# Sprawdzenie root
# ==========================================

if [[ "$EUID" -ne 0 ]]; then
    echo "Ten skrypt musi być uruchomiony jako root."
    echo "Uruchom:"
    echo
    echo "    sudo ./install.sh"
    echo
    exit 1
fi


# ==========================================
# Sprawdzenie dysku
# ==========================================

if [[ ! -b "$DYSK" ]]; then
    echo "Nie znaleziono dysku: $DYSK"
    exit 1
fi


# ==========================================
# Potwierdzenie instalacji
# ==========================================

echo
echo "Czy na pewno chcesz zainstalować Arch Linux?"
echo
read -rp "Wpisz Y lub N: " wybor

if [[ "$wybor" == "N" || "$wybor" == "n" ]]; then

    echo "Instalacja anulowana."
    exit 0

elif [[ "$wybor" == "Y" || "$wybor" == "y" ]]; then

    instalacja_arch

else

    echo "Nieprawidłowy wybór."
    echo "Wpisz Y lub N."
    exit 1

fi
