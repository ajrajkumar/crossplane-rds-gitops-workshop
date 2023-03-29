kubectl delete -f memorydb.yaml
kubectl delete -f upbound_memorydb_crd.yaml
kubectl delete -f upbound_memorydb_comp.yaml
sleep 1
kubectl apply -f upbound_memorydb_crd.yaml
kubectl apply -f upbound_memorydb_comp.yaml

APP_NAMESPACE=default
EKS_CLUSTER_NAME=eksclu
AWS_REGION=us-east-2
RDS_INFO_SECRET_NAME="memorydb-creds-out"
RDS_INFO_CM_NAME="memorydb-creds-out-cm"
PORT=6379

EKS_VPC_ID=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
MEMORYDB_SUBNET_IDS=$(aws cloudformation describe-stacks --region $AWS_REGION --query 'Stacks[].Outputs[?OutputKey == `MemoryDBAllowedSubnets`].OutputValue' --output text)
MEMORYDB_SUBNET_ID_1=`echo ${MEMORYDB_SUBNET_IDS} | awk -F',' '{print $1}'`
MEMORYDB_SUBNET_ID_2=`echo ${MEMORYDB_SUBNET_IDS} | awk -F',' '{print $2}'`
MEMORYDB_SUBNET_ID_3=`echo ${MEMORYDB_SUBNET_IDS} | awk -F',' '{print $3}'`
EKS_CIDR_RANGE=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)


#echo "apiVersion: v1
#kind: Namespace
#metadata:
#  name: ${APP_NAMESPACE}
#" | kubectl apply -f -

echo "apiVersion: aws.database.example.org/v1alpha1
kind: CrossplaneMemoryDB
metadata:
  name: crossplane-memorydb
spec:
  subnetIds:
   - ${MEMORYDB_SUBNET_ID_1}
   - ${MEMORYDB_SUBNET_ID_2}
   - ${MEMORYDB_SUBNET_ID_3}
  region: ${AWS_REGION}
  cidrBlocks: 
   - \"${EKS_CIDR_RANGE}\"
  port: ${PORT}
  instanceClass: db.t4g.small
  connectionInfoSecret: ${RDS_INFO_SECRET_NAME}
  connectionInfoCM: ${RDS_INFO_CM_NAME}
  namespace: ${APP_NAMESPACE}
  name: retailapp-memorydb
  resourceConfig:
    providerConfigName: default " > memorydb.yaml

kubectl apply -f memorydb.yaml
