kubectl delete -f apgserverless.yaml
kubectl delete -f upbound_aurora_serverless_crd.yaml
kubectl delete -f upbound_aurora_serverless_comp.yaml
sleep 1
kubectl apply -f upbound_aurora_serverless_crd.yaml
kubectl apply -f upbound_aurora_serverless_comp.yaml

APP_NAMESPACE=default
EKS_CLUSTER_NAME=eksclu
AWS_REGION=us-east-2
ENGINE_VERSION="13.7"
RDS_DB_SECRET_NAME="db-creds"
RDS_INFO_SECRET_NAME="db-creds-out-serverless"
MAX_ACU=4
MIN_ACU=0.5
PORT=5432

EKS_VPC_ID=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
EKS_SUBNET_IDS=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${EKS_VPC_ID}" --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text)
EKS_SUBNET_ID_1=`echo ${EKS_SUBNET_IDS} | awk '{print $1}'`
EKS_SUBNET_ID_2=`echo ${EKS_SUBNET_IDS} | awk '{print $2}'`
EKS_SUBNET_ID_3=`echo ${EKS_SUBNET_IDS} | awk '{print $3}'`
EKS_CIDR_RANGE=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)
RDS_DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .dbuser)
RDS_DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .password)

#echo "apiVersion: v1
#kind: Namespace
#metadata:
#  name: ${APP_NAMESPACE}
#" | kubectl apply -f -

echo "apiVersion: v1
kind: Secret
metadata:
  name: ${RDS_DB_SECRET_NAME}
  namespace: ${APP_NAMESPACE}
type: Opaque
data:
  password: `echo -n ${RDS_DB_PASSWORD} | base64`
  username: `echo -n ${RDS_DB_USERNAME} | base64`
" | kubectl apply -f -

echo "apiVersion: aws.database.example.org/v1alpha1
kind: CrossplaneAPGServerless
metadata:
  name: crossplane-apg-serverless
spec:
  databaseName: mydb
  subnetIds:
   - ${EKS_SUBNET_ID_1}
   - ${EKS_SUBNET_ID_2}
   - ${EKS_SUBNET_ID_3}
  region: ${AWS_REGION}
  vpcId: ${EKS_VPC_ID}
  cidrBlocks: 
   - \"${EKS_CIDR_RANGE}\"
  engine: aurora-postgresql
  port: ${PORT}
  instanceClass: db.serverless
  maxCapacity: ${MAX_ACU}
  minCapacity: ${MIN_ACU}
  engineVersion: \"${ENGINE_VERSION}\"
  masterUsername: ${RDS_DB_USERNAME}
  masterPasswordSecret:  ${RDS_DB_SECRET_NAME}
  connectionInfoSecret: ${RDS_INFO_SECRET_NAME}
  namespace: ${APP_NAMESPACE}
  resourceConfig:
    providerConfigName: default " > apgserverless.yaml

kubectl apply -f apgserverless.yaml
