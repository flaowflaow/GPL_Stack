# Installation des prérequis
sudo apt install apt-transport-https software-properties-common wget unzip net-tools -y

# Installer Nginx
sudo apt update
sudo apt install -y nginx

# Configurer le site par défaut pour exposer les métriques de Nginx
sudo cat <<"EOF" > /etc/nginx/sites-available/default
server {
  listen 80 default_server;
  listen [::]:80 default_server;

  index index.html index.htm index.nginx-debian.html;

  server_name _;

  root /var/www/html;

  location / {
          try_files $uri $uri/ =404;
  }

  location /metrics {
  stub_status on;
  access_log off;
  allow 127.0.0.1;
  deny all;

  }

}
EOF

# Rédémarrer NGINx
sudo systemctl restart nginx

### Installation de Node_Exporter
# Télécharger et installer le node_exporter
sudo mkdir -p /tmp/prometheus && cd /tmp/prometheus \
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


### Installation de Nginx_Prometheus_Exporter
# Installer nginx-prometheus-exporter
mkdir -p /tmp/nginx_prometheus_exporter && cd /tmp/nginx_prometheus_exporter \
  && wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v1.1.0/nginx-prometheus-exporter_1.1.0_linux_amd64.tar.gz \
  && tar -xzv -f nginx-prometheus-exporter_1.1.0_linux_amd64.tar.gz \
  && sudo cp ./nginx-prometheus-exporter /usr/local/bin/
sudo cp ./nginx-prometheus-exporter /usr/local/bin/

# Créer l'utilisateur et le groupe node_exporter
sudo useradd --no-create-home --shell /bin/false nginx-prometheus-exporter
sudo groupadd nginx-prometheus-exporter
sudo chown nginx-prometheus-exporter:nginx-prometheus-exporter /usr/local/bin/nginx-prometheus-exporter

# Créer le service systemd pour nginx-prometheus-exporter
sudo cat <<"EOF" > /etc/systemd/system/nginx-prometheus-exporter.service
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=nginx-prometheus-exporter
Group=nginx-prometheus-exporter
Type=simple
ExecStart=/usr/local/bin/nginx-prometheus-exporter -nginx.scrape-uri=http://127.0.0.1/metrics

[Install]
WantedBy=multi-user.target
EOF

### Installation de Promtail      
# Ajout des clés et dépôts
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
sudo echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee -a /etc/apt/sources.list.d/grafana.list
sudo apt update      

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
  - url: http://192.168.200.20:3100/loki/api/v1/push
scrape_configs:
- job_name: nginx_system
  static_configs:
  - targets:
      - localhost
    labels:
      job: nginx_varlogs
      __path__: /var/log/*log
- job_name: nginx_logs
  static_configs:
  - targets:
      - localhost
    labels:
      job: nginx_access
      __path__: /var/log/nginx/access.log
- job_name: nginx_error_logs
  static_configs:
  - targets:
      - localhost
    labels:
      job: nginx_error
      __path__: /var/log/nginx/error.log
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

### Finalisation de l'installation
# Activation et redémarrage des services
sudo systemctl daemon-reload
sleep 5
sudo systemctl enable nginx
sleep 5
sudo systemctl start node_exporter
sleep 5
sudo systemctl enable nginx-prometheus-exporter
sleep 5
sudo systemctl enable promtail
sleep 5
sudo systemctl restart nginx
sleep 5
sudo systemctl restart node_exporter
sleep 5
sudo systemctl restart nginx-prometheus-exporter
sleep 5
sudo systemctl restart promtail
sleep 10