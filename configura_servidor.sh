#!/bin/bash

# ==============================================================================
# SCRIPT DE CONFIGURAÇÃO DE SERVIDOR WEB (APACHE + BIND9 DNS) PARA UBUNTU
# ==============================================================================
# Este script deve ser executado com privilégios de root (sudo).
#
# O que ele faz:
# 1. Configura um endereço IP estático usando NetworkManager (nmcli).
# 2. Atualiza o sistema e instala Apache2, BIND9 e OpenSSH Server.
# 3. Configura o firewall (UFW) para permitir tráfego SSH, HTTP/S e DNS.
# 4. Configura uma zona DNS local para resolver um nome de domínio para o IP.
# 5. Cria uma página de teste no servidor web.
# ==============================================================================


# --- (!!! IMPORTANTE !!!) CONFIGURE SUAS VARIÁVEIS AQUI ---

# Nome da sua conexão de rede. 
# Para descobrir, rode o comando: nmcli connection show
# Geralmente é algo como "Wired connection 1" ou o nome da sua placa (ex: "ens33").
CONNECTION_NAME="Wired connection 1"

# O endereço IP estático que este servidor terá. Inclua a máscara (/24).
STATIC_IP="192.168.56.10/24"

# O gateway (roteador) da sua rede.
GATEWAY="192.168.56.1"

# Servidores DNS para acesso à internet (ex: Google, Cloudflare).
DNS_SERVERS="8.8.8.8,1.1.1.1"

# O nome do domínio local que você quer criar (ex: meulab.local, minhaempresa.lan).
DOMAIN_NAME="meulab.local"

# O nome do host para o servidor web (ex: www). O resultado será www.meulab.local.
WEB_SERVER_HOSTNAME="www"

# -------------------- FIM DA CONFIGURAÇÃO --------------------


# --- O SCRIPT COMEÇA AQUI. NÃO EDITE ABAIXO DESTA LINHA. ---

# Checagem de root
if [ "$EUID" -ne 0 ]; then 
  echo "ERRO: Por favor, execute este script como root (usando sudo)."
  exit 1
fi

echo "========================================================"
echo " PASSO 1: CONFIGURANDO IP ESTÁTICO"
echo "========================================================"
nmcli connection modify "$CONNECTION_NAME" \
    ipv4.method manual \
    ipv4.addresses "$STATIC_IP" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS_SERVERS"

echo "Aplicando as configurações de rede..."
nmcli connection down "$CONNECTION_NAME"
sleep 2
nmcli connection up "$CONNECTION_NAME"
sleep 2

echo "Configuração de rede aplicada. Verifique seu novo IP:"
ip addr show | grep "inet .*brd"

echo
echo "========================================================"
echo " PASSO 2: ATUALIZANDO O SISTEMA E INSTALANDO PACOTES"
echo "========================================================"
apt-get update
apt-get install -y apache2 bind9 openssh-server

echo
echo "========================================================"
echo " PASSO 3: CONFIGURANDO O FIREWALL (UFW)"
echo "========================================================"
ufw allow 'Apache Full'
ufw allow 'Bind9'
ufw allow 'OpenSSH'
ufw --force enable

echo "Status do Firewall:"
ufw status verbose

echo
echo "========================================================"
echo " PASSO 4: CONFIGURANDO O SERVIDOR DNS (BIND9)"
echo "========================================================"
# Remove o IP sem o /24 para usar no arquivo de zona
SERVER_IP_CLEAN=$(echo $STATIC_IP | cut -f1 -d'/')

echo "Configurando /etc/bind/named.conf.local..."
cat <<EOF > /etc/bind/named.conf.local
// Arquivo de configuração local gerado pelo script
//
// Faça adições a este arquivo, e não a /etc/bind/named.conf.
//

zone "$DOMAIN_NAME" {
    type master;
    file "/etc/bind/db.$DOMAIN_NAME";
};
EOF

echo "Criando o arquivo de zona /etc/bind/db.$DOMAIN_NAME..."
cat <<EOF > /etc/bind/db.$DOMAIN_NAME
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMAIN_NAME.

; Nossos registros
ns1     IN      A       $SERVER_IP_CLEAN
@       IN      A       $SERVER_IP_CLEAN
$WEB_SERVER_HOSTNAME IN A       $SERVER_IP_CLEAN
EOF

echo "Verificando a sintaxe da configuração do BIND..."
named-checkconf
named-checkzone "$DOMAIN_NAME" "/etc/bind/db.$DOMAIN_NAME"

echo "Reiniciando o serviço BIND9..."
systemctl restart bind9
systemctl status bind9 --no-pager

echo
echo "========================================================"
echo " PASSO 5: CRIANDO PÁGINAS DE TESTE NO APACHE"
echo "========================================================"
echo "<h1>Servidor Apache Funcionando!</h1><p>Acessado via $WEB_SERVER_HOSTNAME.$DOMAIN_NAME</p>" > /var/www/html/index.html
echo "<h2>Página teste.html</h2><p>Este arquivo foi acessado diretamente.</p>" > /var/www/html/teste.html

# Ajustando permissões do diretório web
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

echo "Páginas de teste criadas."

echo
echo "========================================================"
echo " SCRIPT FINALIZADO COM SUCESSO!"
echo "========================================================"
