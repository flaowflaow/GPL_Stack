#!/bin/bash
# Script d'installation d'un serveur Apache supervisé par la pile Grafana / Prometheus / Loki.
# Services : Apache, Node_Exporter, Prometheus_Apache_Exporter, Promtail
# V1


### Installation d'Apache2
# Installation des prérequis
sudo apt install apt-transport-https software-properties-common wget unzip net-tools -y

# Installer Apache
sudo apt update
sudo apt install -y apache2
sudo systemctl daemon-reload
sudo systemctl start apache2
sudo systemctl enable apache2

# Création de la page Apache server-status
sudo cat <<"EOF" > /etc/apache2/conf-available/server-status.conf
ExtendedStatus on
<Location /server-status>
    SetHandler server-status
    Order deny,allow
    Deny from all
    Allow from 127.0.0.1
</Location>
EOF

# Activation de la configuration Apache
cd /etc/apache2/conf-enabled
sudo ln -s ../conf-available/server-status.conf server-status.conf && cd
sudo systemctl restart apache2


### Installation de Prometheus_Apache_Exporter 
# Téléchargement et installation de la librairie Apache Exporter
mkdir -p /tmp/apache_node_exporter && cd /tmp/apache_node_exporter \
  && curl -s https://api.github.com/repos/Lusitaniae/apache_exporter/releases/latest \
  | grep browser_download_url \
  | cut -d '"' -f 4 \
  | grep linux-amd64.tar.gz \
  | wget -vO - -i - \
  | tar -xzv --strip-components=1
sudo cp ./apache_exporter /usr/local/bin/

# Création de l'user Apache_exporter & attribution des droits
sudo useradd -M -r -s /bin/false apache_exporter
sudo groupadd apache_exporter
sudo chown apache_exporter:apache_exporter /usr/local/bin/apache_exporter

# Créer le service systemd pour Prometheus-Apache-exporter
sudo cat <<"EOF" > /etc/systemd/system/prometheus-apache-exporter.service
[Unit]
Description=Prometheus Apache Exporter
Wants=network-online.target
After=network-online.target
      
[Service]
User=apache_exporter
Group=apache_exporter
Type=simple
ExecStart=/usr/local/bin/apache_exporter
      
[Install]
WantedBy=multi-user.target
EOF

### Installation de Apache_Node_Exporter
# Télécharger et installer le node_exporter
mkdir -p /tmp/prometheus && cd /tmp/prometheus \
  && curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest \
  | grep browser_download_url \
  | cut -d '"' -f 4 \
  | grep linux-amd64.tar.gz \
  | wget -vO - -i - \
  | tar -xzv --strip-components=1
sudo cp ./node_exporter /usr/local/bin/

# Créer l'utilisateur et le groupe node_exporter
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo groupadd node_exporter
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Créer le service systemd pour node_exporter
sudo cat <<"EOF" > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

### Installation de Promtail
# Ajout des clés et dépôts
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee -a /etc/apt/sources.list.d/grafana.list
apt update      
      
# Installer Promtail
sudo mkdir -p /tmp/promtail && cd /tmp && \
curl -s https://api.github.com/repos/grafana/loki/releases/latest | \
grep browser_download_url | cut -d '"' -f 4 | grep promtail-linux-amd64.zip | \
wget -v -i - && \
unzip promtail-linux-amd64.zip && \
sudo mv promtail-linux-amd64 /usr/bin/promtail

# Création de l'user promtail et attribution des droits
sudo groupadd -r promtail
sudo useradd -r -g promtail -s /bin/false promtail
sudo chown -R promtail:promtail /usr/bin/promtail

# Configuration de promtail.yaml et promtail.service
sudo mkdir /etc/promtail
sudo cat <<"EOF" > /etc/promtail/promtail.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://192.168.33.20:3100/loki/api/v1/push
scrape_configs:
- job_name: apache_system
  static_configs:
  - targets:
      - localhost
    labels:
      job: apache_varlogs
      __path__: /var/log/*log
- job_name: apache_logs
  static_configs:
  - targets:
      - localhost
    labels:
      job: apache_access
      __path__: /var/log/apache2/access.log
- job_name: apache_error_logs
  static_configs:
  - targets:
      - localhost
    labels:
      job: apache_error
      __path__: /var/log/apache2/error.log
EOF

sudo cat <<"EOF" > /etc/systemd/system/promtail.service
[Unit]
Description=Promtail service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/promtail -config.file /etc/promtail/promtail.yaml
# Give a reasonable amount of time for promtail to start up/shut down
TimeoutSec = 60
Restart = on-failure
RestartSec = 2

[Install]
WantedBy=multi-user.target
EOF

# Activation et redémarrage des services
sudo systemctl daemon-reload
# Activation et démarrage du service Apache
sudo systemctl enable apache2
sudo systemctl restart apache2
# Activation et démarrage du service prometheus-apache-exporter
sudo systemctl enable prometheus-apache-exporter.service
sudo systemctl start prometheus-apache-exporter.service
# Activation et démarrage du service Node_Exporter
sudo systemctl enable node_exporter
sudo systemctl restart node_exporter
# Activation et démarrage du service Promtail
sudo systemctl enable promtail
sudo systemctl restart promtail