kubectl delete -f upbound_rds_crd.yaml
kubectl delete -f upbound_rds_comp.yaml
kubectl delete -f rds.yaml
sleep 1
kubectl apply -f upbound_rds_crd.yaml
kubectl apply -f upbound_rds_comp.yaml

APP_NAMESPACE=default
EKS_CLUSTER_NAME=eksclu
AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
ENGINE_VERSION="13.7"
INSTANCE_CLASS="db.t3.micro"
RDS_STORAGE_TYPE="gp2"
RDS_STORAGE_SIZE="20"
RDS_DB_SECRET_NAME="db-creds"
RDS_INFO_SECRET_NAME="db-creds-out"

EKS_VPC_ID=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
EKS_SUBNET_IDS=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${EKS_VPC_ID}" --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text)
EKS_SUBNET_ID_1=`echo ${EKS_SUBNET_IDS} | awk '{print $1}'`
EKS_SUBNET_ID_2=`echo ${EKS_SUBNET_IDS} | awk '{print $2}'`
EKS_SUBNET_ID_3=`echo ${EKS_SUBNET_IDS} | awk '{print $3}'`
EKS_CIDR_RANGE=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)
RDS_DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .dbuser)
RDS_DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .password)

echo "apiVersion: v1
kind: Namespace
metadata:
  name: ${APP_NAMESPACE}
" | kubectl apply -f -

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
kind: CrossplanePG
metadata:
  name: crossplane-pg
spec:
  storageGB: ${RDS_STORAGE_SIZE}
  databaseName: mydb
  subnetIds:
   - ${EKS_SUBNET_ID_1}
   - ${EKS_SUBNET_ID_2}
   - ${EKS_SUBNET_ID_3}
  region: ${AWS_REGION}
  vpcId: ${EKS_VPC_ID}
  port: 5432
  cidrBlocks: 
   - \"${EKS_CIDR_RANGE}\"
  engine: postgres
  engineVersion: \"${ENGINE_VERSION}\"
  instanceClass: \"${INSTANCE_CLASS}\"
  passwordSecret:  ${RDS_DB_SECRET_NAME}
  connectionInfoSecret: ${RDS_INFO_SECRET_NAME}
  namespace: ${APP_NAMESPACE}
  storageType: ${RDS_STORAGE_TYPE}
  username: ${RDS_DB_USERNAME}
  resourceConfig:
    providerConfigName: default " > rds.yaml

kubectl apply -f rds.yaml
