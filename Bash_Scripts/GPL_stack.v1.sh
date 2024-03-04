#!/bin/bash
# Script d'installation d'un serveur de supervision Grafana.
# Services : Loki, Prometheus, Promtail & (R)Syslog
# v1

sudo apt-get install dos2unix -y
dos2unix /tmp/GPL_stack.v1.sh


# Installation des prérequis
sudo apt-get install apt-transport-https software-properties-common wget curl unzip net-tools -y


### Installation de Grafana
# Ajout des clés et dépôts de Grafana
mkdir -p /etc/apt/keyrings/ && \
wget -vO - https://packages.grafana.com/gpg.key | sudo apt-key add - && \
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main" -y
      
# Installer grafana
sudo apt-get update && sudo apt-get install -y grafana

# Modification du fichier grafana.ini
sudo cat <<"EOF" >> /etc/grafana/grafana.ini
[paths]
data = /var/lib/grafana
temp_data_lifetime = 24h
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning
  
[server]
protocol = http
;min_tls_version = ""
http_addr = 192.168.200.20
http_port = 3000
domain = 192.168.200.20
enforce_domain = false
EOF
      
# Configurer le datasource prometheus
sudo cat <<"EOF" > /etc/grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1

datasources:
 - name: Prometheus
   type: prometheus
   access: proxy
   url: http://127.0.0.1:9090
   isDefault: true
   version: 1
   editable: true
EOF

# Configurer le datasource loki
sudo cat <<"EOF" > /etc/grafana/provisioning/datasources/loki.yaml
apiVersion: 1

datasources:
 - name: Loki
   type: loki
   access: proxy
   url: http://127.0.0.1:3100
   jsonData:
     timeout: 60
     maxLines: 1000
EOF


### Installation de Prometheus
# Télécharger et extraire le binaire prometheus
mkdir -p /tmp/prometheus && cd /tmp/prometheus \
  && curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest \
  | grep browser_download_url \
  | cut -d '"' -f 4 \
  | grep linux-amd64.tar.gz \
  | wget -vO - -i - \
  | tar -xzv --strip-components=1

# Créer le répertoire et copier les fichiers
sleep 20
sudo mkdir /etc/prometheus
sudo cp prometheus /usr/bin/
sudo cp promtool /usr/bin/
sudo cp -r consoles /etc/prometheus
sudo cp -r console_libraries /etc/prometheus
sudo mkdir -p /var/lib/prometheus/

# Créer l'user prometheus et attibution des droits
sudo useradd --no-create-home --shell /bin/false prometheus
sudo chown -R prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /usr/bin/prometheus
sudo chown prometheus:prometheus /usr/bin/promtool
sudo chown prometheus:prometheus /var/lib/prometheus/

# Configuration de prometheus.yaml et prometheus.service
sudo cat <<"EOF" > /etc/prometheus/prometheus.yaml
global:
  scrape_interval: 15s
    
scrape_configs:
  - job_name: "prometheus"
    scrape_interval: 5s
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "apache2"
    scrape_interval: 5s
    metrics_path: /metrics
    static_configs:
      - targets: ["192.168.200.21:9117"]
  - job_name: "node_exporter_apache2"
    scrape_interval: 5s
    static_configs:
      - targets: ["192.168.200.21:9100"]
  - job_name: "nginx"
    scrape_interval: 5s
    metrics_path: /metrics
    static_configs:
      - targets: ["192.168.200.22:9113"]
  - job_name: "node_exporter_nginx"
    scrape_interval: 5s
    static_configs:
      - targets: ["192.168.200.22:9100"]
EOF

sudo cat <<"EOF" > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/bin/prometheus \
  --config.file /etc/prometheus/prometheus.yaml \
  --storage.tsdb.path /var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF


### Installation de Loki
# Installer Loki
cd /tmp && \
curl -s https://api.github.com/repos/grafana/loki/releases/latest | \
grep browser_download_url | cut -d '"' -f 4 | grep loki-linux-amd64.zip | \
wget -v -i - && \
unzip loki-linux-amd64.zip && \
sudo mv loki-linux-amd64 /usr/bin/loki

# Création de l'user loki et attribution des droits
sudo groupadd -r loki
sudo useradd -r -g loki -s /bin/false loki
sudo chown -R loki:loki /usr/bin/loki

# Configuration de loki.yaml et loki.service
sudo mkdir -p /data/loki && sudo mkdir /etc/loki
sudo cat <<"EOF" > /etc/loki/loki.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /data/loki
  storage:
    filesystem:
      chunks_directory: /data/loki/chunks
      rules_directory: /data/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093
EOF

sudo cat <<"EOF" > /etc/systemd/system/loki.service
[Unit]
Description=Loki service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/loki -config.file /etc/loki/loki.yaml
# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec = 120
Restart = on-failure
RestartSec = 2

[Install]
WantedBy=multi-user.target
EOF


### Installation de Promtail
# Installer Promtail
cd /tmp && \
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
  - url: http://localhost:3100/loki/api/v1/push
scrape_configs:
- job_name: system
  static_configs:
  - targets:
      - localhost
    labels:
      job: varlogs
      __path__: /var/log/*log
- job_name: syslog
  syslog:
    listen_address: 0.0.0.0:1514
    labels:
      job: syslog
  relabel_configs:
    - source_labels: [__syslog_message_hostname]
      target_label: host
    - source_labels: [__syslog_message_hostname]
      target_label: hostname
    - source_labels: [__syslog_message_severity]
      target_label: level
    - source_labels: [__syslog_message_app_name]
      target_label: application
    - source_labels: [__syslog_message_facility]
      target_label: facility
    - source_labels: [__syslog_connection_hostname]
      target_label: connection_hostname
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

### Configuration de rsyslog.conf
sudo cat <<"EOF" > /etc/rsyslog.conf
#################
#### MODULES ####
#################

module(load="imuxsock") # provides support for local system logging
#module(load="immark")  # provides --MARK-- message capability

# provides UDP syslog reception
module(load="imudp")
input(type="imudp" port="514")

# provides TCP syslog reception
module(load="imtcp")
input(type="imtcp" port="514")

# provides kernel logging support and enable non-kernel klog messages
module(load="imklog" permitnonkernelfacility="on")

###########################
#### GLOBAL DIRECTIVES ####
###########################

#
# Use traditional timestamp format.
# To enable high precision timestamps, comment out the following line.
#
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat

# Filter duplicated messages
$RepeatedMsgReduction on

#
# Set the default permissions for all log files.
#
$FileOwner syslog
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
$Umask 0022
$PrivDropToUser syslog
$PrivDropToGroup syslog

#
# Where to place spool and state files
#
$WorkDirectory /var/spool/rsyslog

#
# Include all config files in /etc/rsyslog.d/
#
$IncludeConfig /etc/rsyslog.d/*.conf

# Forward everything
*.*  action(type="omfwd"
       protocol="tcp" target="127.0.0.1" port="1514"
       Template="RSYSLOG_SyslogProtocol23Format"
       TCP_Framing="octet-counted" KeepAlive="on"
       action.resumeRetryCount="-1"
       queue.type="linkedlist" queue.size="50000")
EOF

# Activation des services
# Activation et redémarrage des services
sudo systemctl daemon-reload
sleep 5
sudo systemctl enable grafana-server
sudo systemctl restart grafana-server
sleep 5
sudo systemctl enable prometheus
sudo systemctl restart prometheus
sleep 5
sudo systemctl enable loki
sudo systemctl restart loki
sleep 5
sudo systemctl enable promtail
sudo systemctl restart promtail