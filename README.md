# scripts for privte k8s cloud deployment

> **私有云部署脚本**

>  </br>-----------------------------------------------------------------------------------------------
>  </br>   cloud servers + traefix acme + frp servers
>  </br>-----------------------------------------------------------------------------------------------
>  </br>   local vmware k8s cluter + helm + cilium + istio + higress + frp clients
>  </br>-----------------------------------------------------------------------------------------------
>  </br>   opentelemetry + skywalking + db + mq + spring cloud + ......
>  </br>-----------------------------------------------------------------------------------------------
>  </br>
>  </br>

## 设置环境变量

```bash

# 代理
# export GHPROXY=https://ghproxy.org/
export GHPROXY=https://mirror.ghproxy.com/

export LABRING_REPO=${registry.cn-shanghai.aliyuncs.com} #
export BITNAMI_REPO=${xxxxx.mirror.aliyuncs.com} # 请替换自己的aliyun镜像地址

export SCRIPTS_REPO=${GHPROXY}https://raw.githubusercontent.com/robotism/private-cloud-scripts/master
export REPO=${SCRIPTS_REPO}


export ANSIBLE_VARS="\
export GHPROXY=${GHPROXY} && \
export REPO=${REPO} && \
export SCRIPTS_REPO=${SCRIPTS_REPO} && \
export LABRING_REPO=${LABRING_REPO} && \
export BITNAMI_REPO=${BITNAMI_REPO} && \
"

export DOMAIN=example.com
export TOKEN=pa44vv0rd

export TEMP=/opt/tmp
export DATA=/opt/data

# 云主机
export CLOUD_IPS=xxx,xxx # WAN
export CLOUD_SSH_PWD=xxxxxxxxx

# 本地主机
export K8S_MASTER_IPS=10.0.0.1,10.0.0.2 #VLAN
export K8S_NODE_IPS=10.0.0.3,10.0.0.4 #VLAN
export K8S_SSH_PWD=xxxxxxxxxx


```

----

## 部署云服务器

### 一键初始化debian和ansbile集群

```bash

bash <(curl -s ${REPO}/init_ansible_cluster.sh) \
--hostname cloud-node- \
--ips $CLOUD_IPS \
--password ${CLOUD_SSH_PWD}

ansible all -m raw -a "mkdir -p ${TEMP}"
ansible all -m raw -a "mkdir -p ${DATA}"

```

### 一键初始化debian和docker环境

```bash

# 单独操作
bash <(curl -s ${REPO}/init_debian_docker.sh) --profile ${PROFILE:-release}

# 批量操作
ansible all -m raw -a "${ANSIBLE_VARS} bash <(curl -s ${REPO}/init_debian_docker.sh) --install_docker true --profile ${PROFILE:-release}"

ansible all -m raw -a "sleep 3s && reboot"

ansible all -m raw -a "hostname && docker ps"

# test doamin->ip->nginx:80
#ansible all -m raw -a 'docker run -dit -p 80:80 --name=nginx nginx'
#ansible all -m raw -a 'docker rm -f $(docker ps -aq)'

```

---

### 一键生成acme免费证书


```bash

export DP_ID=xxxxx
export DP_KEY=xxxxxxxxxxxxxxxxxxx

bash <(curl -s ${REPO}/install_docker_acme.sh) \
--output ${TEMP}/acme.sh \
--dns dns_dp \
--apikey DP_Id=${DP_ID} \
--apisecret DP_Key=${DP_KEY} \
--domains ${DOMAIN},*.${DOMAIN} \
--server zerossl \
--daemon false
ansible all -m raw -a "rm -rf ${DATA}/acme.sh"
ansible all -m copy -a "src=${TEMP}/acme.sh dest=${DATA} force=yes"
ansible all -m raw -a "ls ${DATA}/acme.sh"

```

### 一键部署Traefik

- dnspod

```bash

ansible all -m raw -a "${ANSIBLE_VARS} \
bash <(curl -s ${REPO}/install_docker_traefik.sh) \
--datadir ${DATA}/traefik \
--acmedir ${DATA}/acme.sh \
--route_rule 'HostRegexp(\`.*\`)' \
--dashboard_route_rule 'Host(\`traefik.${DOMAIN}\`)' \
--dashboard_user traefik \
--dashboard_password ${TOKEN} \
"
ansible all -m raw -a "docker logs -n 10 traefik"


```

### 一键部署frps

- dnspod

```bash

ansible all -m raw -a "${ANSIBLE_VARS} \
bash <(curl -s ${REPO}/install_docker_frps.sh) \
--datadir ${DATA}/frp \
--http_route_rule 'HostRegexp(\`.*\`)&&!HostRegexp(\`^(traefik|frps|tcp)\`)' \
--tcp_route_rule 'HostSNI(\`tcp-*.${DOMAIN}\`)' \
--dashboard_route_rule 'Host(\`frps.${DOMAIN}\`)' \
--dashboard_user frps \
--token ${TOKEN} \
"

```

---

## 部署本地服务器

### 一键初始化系统

```bash
# init ansible  ------------------------
bash <(curl -s ${REPO}/init_ansible_cluster.sh) \
--hostname k8s-node- \
--ips ${K8S_MASTER_IPS},${K8S_NODE_IPS} \
--password ${K8S_SSH_PWD}

ansible all -m raw -a "mkdir -p ${TEMP}"
ansible all -m raw -a "mkdir -p ${DATA}"

# init linux  ------------------------
ansible all -m raw -a "${ANSIBLE_VARS} bash <(curl -s ${REPO}/init_debian_docker.sh) \
--profile ${PROFILE:-release} \
--sources ustc
"
# 本地k8s集群使用cri不需要安装docker

ansible all -m raw -a "sleep 3s && reboot"
ansible all -m raw -a "hostname"

```

### 一键初始化k8s集群(sealos)

```bash
bash <(curl -s ${REPO}/install_k8s_core.sh) \
--master_ips ${K8S_MASTER_IPS:-""} \
--node_ips ${K8S_NODE_IPS:-""} \
--password ${K8S_SSH_PWD} \
--ingress_class higress \
--higress_route_rule higress.${DOMAIN}
```


### 一键部署frpc

```bash
bash <(curl -s ${REPO}/install_k8s_frpc.sh) \
--bind_ips ${CLOUD_IPS} \
--http_upstream_host higress-gateway.higress-system.svc.cluster.local \
--http_upstream_port 80 \
--http_route_rule ${DOMAIN},*.${DOMAIN} \
--token ${TOKEN}
```

### 一键部署 rancher

```bash
bash <(curl -s ${REPO}/install_k8s_rancher.sh) \
--rancher_route_rule rancher.${DOMAIN} \
--ingress_class higress \
--password ${TOKEN}
```

### 一键部署 db

```bash
bash <(curl -s ${REPO}/install_k8s_db.sh) \
--ingress_class higress \
--password ${TOKEN}
```

### 一键部署 mq

```bash
bash <(curl -s ${REPO}/install_k8s_mq.sh) \
--ingress_class higress \
--password ${TOKEN}
```

### 一键部署 monitor

```bash
bash <(curl -s ${REPO}/install_k8s_monitor.sh) \
--ingress_class higress \
--kibana_route_rule kibana.${DOMAIN} \
--grafana_route_rule grafana.${DOMAIN} \
--prometheus_route_rule prometheus.${DOMAIN} \
--skywalking_route_rule skywalking.${DOMAIN} \
--password ${TOKEN}
```

### 一键部署 cloud-ide(code-server)

```bash
bash <(curl -s ${REPO}/install_k8s_ide.sh) \
--ingress_class higress \
--coder_route_rule coder.${DOMAIN} \
--password ${TOKEN}
```

### 一键部署 WordPress

```bash
bash <(curl -s ${REPO}/install_k8s_wordpress.sh) \
--ingress_class higress \
--wordpress_route_rule ${DOMAIN},www.${DOMAIN} \
--password ${TOKEN}
```

### 一键部署 Halo

```bash
bash <(curl -s ${REPO}/install_k8s_halo.sh) \
--ingress_class higress \
--halo_route_rule ${DOMAIN},www.${DOMAIN} \
--password ${TOKEN}
```