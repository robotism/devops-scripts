#/bin/bash -e

if [ -n "$(echo $REPO | grep ^http)" ]
then
source <(curl -s ${REPO}/env_function.sh) 
else
source ${REPO}/env_function.sh
fi

#-----------------------------------------------------------------------------------------------
# env

WORK_DIR=${WORK_DIR:-`pwd`}

namespace=`getarg namespace $@ 2>/dev/null`
namespace=${namespace:-"web-system"}
password=`getarg password $@ 2>/dev/null`
password=${password:-"Pa44VV0rd14VVrOng"}
storage_class=`getarg storage_class $@  2>/dev/null`
storage_class=${storage_class:-""}

ingress_class=`getarg ingress_class $@ 2>/dev/null`
ingress_class=${ingress_class:-higress}

db_namespace=`getarg db_namespace $@ 2>/dev/null`
db_namespace=${db_namespace:-db-system}


# kubectl exec -i -t -n ${db_namespace} mysql-primary-0 -c mysql -- sh -c "(bash || ash || sh)"
# mysql -uroot -p${password} -e "CREATE DATABASE IF NOT EXISTS waline;show databases;"
# mysql -uroot -p${password} -e "alter user 'root'@'%' identified with mysql_native_password by '${password}';flush privileges;";
# 

# https://waline.js.org/reference/server/env.html
# https://waline.js.org/guide/database.html#mysql
# https://github.com/walinejs/waline/blob/main/assets/waline.sql

echo "
kind: Deployment
apiVersion: apps/v1
metadata:
  name: waline
  namespace: ${namespace:-default}
  labels:
    app: waline
spec:
  replicas: 1
  selector:
    matchLabels:
      app: waline
  template:
    metadata:
      labels:
        app: waline
    spec:
      containers:
        - name: waline
          image: docker.io/lizheming/waline:latest
          ports:
            - name: waline
              containerPort: 8360 
          env:
            - name: MYSQL_DB
              value: \"waline\"
            - name: MYSQL_USER
              value: \"root\"
            - name: MYSQL_PASSWORD
              value: \"${password}\"
            - name: MYSQL_HOST
              value: \"mysql-primary.${db_namespace}.svc\"
            - name: MYSQL_PORT
              value: \"3306\"
          readinessProbe:
            failureThreshold: 1
            httpGet:
              path: /
              port: 8360
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 2
" | kubectl apply -f -


echo "
apiVersion: v1
kind: Service
metadata:
  name: waline
  namespace: ${namespace:-default}
spec:
  type: ClusterIP
  ports:
    - protocol: TCP
      name: waline
      port: 8360
      targetPort: 8360
  selector:
    app: waline
" | kubectl apply -f -


waline_route_rule=`getarg waline_route_rule $@ 2>/dev/null`
waline_route_rule=${waline_route_rule:-'waline.localhost'}
srv_name=$(kubectl get service -n ${namespace} | grep waline | awk '{print $1}')
src_port=$(kubectl get services -n ${namespace} $srv_name -o jsonpath="{.spec.ports[0].port}")
install_ingress_rule \
--name waline \
--namespace ${namespace} \
--ingress_class ${ingress_class} \
--service_name $srv_name \
--service_port $src_port \
--domain ${waline_route_rule}



echo "---------------------------------------------"
echo "done: ${waline_route_rule}/ui"
echo "---------------------------------------------"

