#!/bin/bash

PRIVATE_IP="$(hostname --ip-address)"
export PRIVATE_IP

export DEBIAN_FRONTEND=noninteractive
UNAME="$(uname -r)"
export UNAME

INSTANCE_ID=$(cloud-init query local_hostname)
export INSTANCE_ID

echo "----------------------------------------"
echo "        Tuning kernel parameters"
echo "----------------------------------------"
if [ -f /sys/block/nvme0n1/queue/scheduler ] && grep -q 'mq-deadline' /sys/block/nvme0n1/queue/scheduler
then
    echo 'mq-deadline' > /sys/block/nvme0n1/queue/scheduler
    echo 'ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/scheduler}="mq-deadline"' > /etc/udev/rules.d/99-circleci-io-scheduler.rules
    update-grub
fi

echo "-------------------------------------------"
echo "     Performing System Updates"
echo "-------------------------------------------"
apt-get update && apt-get -y upgrade

echo "--------------------------------------"
echo "        Installing NTP"
echo "--------------------------------------"
apt-get install -y ntp

echo "--------------------------------------"
echo "        Installing Docker"
echo "--------------------------------------"
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get install -y "linux-image-$UNAME"
apt-get update
apt-get -y install docker-ce=5:19.03.13~3-0~ubuntu-focal \
                   docker-ce-cli=5:19.03.13~3-0~ubuntu-focal

# force docker to use userns-remap to mitigate CVE 2019-5736
apt-get -y install jq
mkdir -p /etc/docker
[ -f /etc/docker/daemon.json ] || echo '{}' > /etc/docker/daemon.json
tmp=$(mktemp)
cp /etc/docker/daemon.json /etc/docker/daemon.json.orig
jq '.["userns-remap"]="default"' /etc/docker/daemon.json > "$tmp" && mv "$tmp" /etc/docker/daemon.json
echo 'export no_proxy="true"' >> /etc/default/docker
service docker restart
sleep 5

echo "--------------------------------------"
echo " Populating /etc/circleci/public-ipv4"
echo "--------------------------------------"
export aws_instance_metadata_url="http://169.254.169.254"
export PUBLIC_IP="$(curl $aws_instance_metadata_url/latest/meta-data/public-ipv4)"
export PRIVATE_IP="$(curl $aws_instance_metadata_url/latest/meta-data/local-ipv4)"
if ! (echo $PUBLIC_IP | grep -qP "^[\d.]+$"); then
    echo "Setting the IPv4 address below in /etc/circleci/public-ipv4."
    echo "This address will be used in builds with \"Rebuild with SSH\"."
    mkdir -p /etc/circleci
    echo $PRIVATE_IP | tee /etc/circleci/public-ipv4
fi

echo "--------------------------------------"
echo "         Installing nomad"
echo "--------------------------------------"
apt-get install -y zip
curl -o nomad.zip https://releases.hashicorp.com/nomad/0.11.8/nomad_0.11.8_linux_amd64.zip
unzip nomad.zip
mv nomad /usr/bin

echo "--------------------------------------"
echo "       Installling TLS certs"
echo "--------------------------------------"
mkdir -p /etc/ssl/nomad
cat <<EOT > /etc/ssl/nomad/cert.pem
${client_tls_cert}
EOT
cat <<EOT > /etc/ssl/nomad/key.pem
${client_tls_key}
EOT
cat <<EOT > /etc/ssl/nomad/ca.pem
${tls_ca}
EOT

echo "--------------------------------------"
echo "      Creating config.hcl"
echo "--------------------------------------"

mkdir -p /etc/nomad
cat <<EOT > /etc/nomad/config.hcl
log_level = "DEBUG"
name = "$INSTANCE_ID"
data_dir = "/opt/nomad"
datacenter = "default"
advertise {
    http = "$PRIVATE_IP"
    rpc = "$PRIVATE_IP"
    serf = "$PRIVATE_IP"
}
client {
    enabled = true
    # Expecting to have DNS record for nomad server(s)
    server_join = {
        retry_join = ["${nomad_server_endpoint}"]
    }
    node_class = "linux-64bit"
    options = {"driver.raw_exec.enable" = "1"}
}
EOT

if [ "${client_tls_cert}" ]; then
cat <<EOT >> /etc/nomad/config.hcl
tls {
http = false
    rpc  = true
     # This verifies the CN ([role].[region].nomad) in the certificate,
    # not the hostname or DNS name of the of the remote party.
    # https://learn.hashicorp.com/tutorials/nomad/security-enable-tls?in=nomad/transport-security#node-certificates
    verify_server_hostname = true
    ca_file   = "/etc/ssl/nomad/ca.pem"
    cert_file = "/etc/ssl/nomad/cert.pem"
    key_file  = "/etc/ssl/nomad/key.pem"
}
EOT
fi

echo "--------------------------------------"
echo "      Creating nomad.conf"
echo "--------------------------------------"
cat <<EOT > /etc/systemd/system/nomad.service
[Unit]
Description="nomad"
[Service]
Restart=always
RestartSec=30
TimeoutStartSec=1m
ExecStart=/usr/bin/nomad agent -config /etc/nomad/config.hcl
[Install]
WantedBy=multi-user.target
EOT

echo "--------------------------------------"
echo "   Creating ci-privileged network"
echo "--------------------------------------"
docker network create --label keep --driver=bridge --opt com.docker.network.bridge.name=ci-privileged ci-privileged

echo "--------------------------------------"
echo "      Starting Nomad service"
echo "--------------------------------------"
systemctl enable --now nomad

echo "--------------------------------------"
echo "  Set Up Docker Garbage Collection"
echo "--------------------------------------"

cat <<EOT > /etc/systemd/system/docker-gc.service
[Unit]
Description=Docker garbage collector
[Service]
Type=simple
Restart=always
ExecStart=/etc/docker-gc-start.rc
ExecStop=/bin/bash -c "docker rm -f docker-gc || true"
[Install]
WantedBy=cloud-init.target
EOT
chown root:root /etc/systemd/system/docker-gc.service
chmod 0644 /etc/systemd/system/docker-gc.service

cat <<EOT > /etc/docker-gc-start.rc
#!/bin/bash
set -euo pipefail
timeout 1m docker pull circleci/docker-gc:1.0
docker rm -f docker-gc || true
# Will return exit 0 if volume already exists
docker volume create docker-gc --label=keep
# --net=host is used to allow the container to talk to the local statsd agent
docker run \
  --rm \
  --interactive \
  --name "docker-gc" \
  --privileged \
  --net=host \
  --userns=host \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume /var/lib/docker:/var/lib/docker:ro \
  --volume docker-gc:/state \
  "circleci/docker-gc:1.0" \
  -threshold "1000 KB"
EOT
chmod 0700 /etc/docker-gc-start.rc

echo "--------------------------------------"
echo "  Start Docker Garbage Collection"
echo "--------------------------------------"
systemctl enable --now docker-gc

echo "--------------------------------------"
echo "  Securing Docker network interfaces"
echo "--------------------------------------"
docker_chain="DOCKER-USER"
# Blocking meta-data endpoint access
/sbin/iptables --wait --insert $docker_chain -i docker+ --destination "169.254.0.0/16" --jump DROP
/sbin/iptables --wait --insert $docker_chain -i br-+ --destination "169.254.0.0/16" --jump DROP
# Blocking internal cluster resources
%{ for cidr_block in blocked_cidrs ~}
/sbin/iptables --wait --insert $docker_chain -i docker+ --destination "${cidr_block}" --jump DROP
/sbin/iptables --wait --insert $docker_chain -i br+ --destination "${cidr_block}" --jump DROP
%{ endfor ~}
/sbin/iptables --wait --insert $docker_chain 1 -i br+ --destination "${dns_server}" -p tcp --dport 53 --jump RETURN
/sbin/iptables --wait --insert $docker_chain 2 -i br+ --destination "${dns_server}" -p udp --dport 53 --jump RETURN
