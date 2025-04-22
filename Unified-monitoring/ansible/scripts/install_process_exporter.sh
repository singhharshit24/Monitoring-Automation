#!/bin/bash
curl -LO https://github.com/ncabatoff/process-exporter/releases/download/v0.7.10/process-exporter-0.7.10.linux-amd64.tar.gz
tar xzvf process-exporter-*.linux-amd64.tar.gz
cp -rvi process-exporter-*.linux-amd64/process-exporter /usr/local/bin
useradd --no-create-home --shell /bin/false process_exporter

tee /etc/process-exporter.yml > /dev/null << EOF
process_names:
  - name: "{{.Comm}}"
    cmdline:
    - '.+'
EOF

tee /etc/systemd/system/process-exporter.service > /dev/null << EOF
[Unit]
Description=process_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=process_exporter
Type=simple
ExecStart=/usr/local/bin/process-exporter --config.path /etc/process-exporter.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start process-exporter
systemctl enable process-exporter
