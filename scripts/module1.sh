APP_NAMESPACE=mydb
EKS_CLUSTER_NAME=eksclu
AWS_REGION=us-east-2
EKS_VPC_ID=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
RDS_SUBNET_GROUP_NAME="my-subnet-group"
RDS_SUBNET_GROUP_DESCRIPTION="database subnet group"
EKS_SUBNET_IDS=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${EKS_VPC_ID}" --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text)
EKS_SUBNET_ID_1=`echo ${EKS_SUBNET_IDS} | awk '{print $1}'`
EKS_SUBNET_ID_2=`echo ${EKS_SUBNET_IDS} | awk '{print $2}'`
EKS_SUBNET_ID_3=`echo ${EKS_SUBNET_IDS} | awk '{print $3}'`
RDS_SECURITY_GROUP_NAME="ack-security-group"
RDS_SECURITY_GROUP_DESCRIPTION="ACK security group"
EKS_CIDR_RANGE=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)
RDS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups  --filter Name=vpc-id,Values="${EKS_VPC_ID}" Name=group-name,Values="${RDS_SECURITY_GROUP_NAME}" --query 'SecurityGroups[*].[GroupId]' --output text )
RDS_DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .dbuser)
RDS_DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .password)
RDS_DB_SECRET_NAME="ack-creds"
RDS_INFO_SECRET_NAME="ack-creds-out"
RDS_INSTANCE_NAME="crossplane-db"
RDS_DB_SUBNET_NAME="crossplane-dbsubnet"

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


echo "
apiVersion: rds.aws.upbound.io/v1beta1
kind: SubnetGroup
metadata:
  name: ${RDS_DB_SUBNET_NAME}
spec:
  forProvider:
    region: ${AWS_REGION}
    subnetIds: 
      - ${EKS_SUBNET_ID_1}
      - ${EKS_SUBNET_ID_2}
      - ${EKS_SUBNET_ID_3}
    tags:
      Name: DB Subnet group for module 1
" | kubectl apply -f -


echo "apiVersion: ec2.aws.upbound.io/v1beta1
kind: SecurityGroup
metadata:
  name: ${RDS_SECURITY_GROUP_NAME}
spec:
  forProvider:
    description: Allow TLS inbound traffic
    name: ${RDS_SECURITY_GROUP_NAME}
    region: ${AWS_REGION}
    vpcId: ${EKS_VPC_ID} 
" | kubectl apply -f -


echo "apiVersion: ec2.aws.upbound.io/v1beta1
kind: SecurityGroupRule
metadata:
  name: ${RDS_SECURITY_GROUP_NAME}-rule1
spec:
  forProvider:
    cidrBlocks:
      - ${EKS_CIDR_RANGE}
    fromPort: 5432
    protocol: tcp
    region: ${AWS_REGION}
    securityGroupIdRef:
      name: ${RDS_SECURITY_GROUP_NAME}
    toPort: 5432
    type: ingress
" | kubectl apply -f -

echo "apiVersion: ec2.aws.upbound.io/v1beta1
kind: SecurityGroupRule
metadata:
  name: ${RDS_SECURITY_GROUP_NAME}-rule2
spec:
  forProvider:
    cidrBlocks:
      - \"0.0.0.0/0\"
    fromPort: 0
    protocol: tcp
    region: ${AWS_REGION}
    securityGroupIdRef:
      name: ${RDS_SECURITY_GROUP_NAME}
    toPort: 0
    type: egress
" | kubectl apply -f -


echo "apiVersion: rds.aws.upbound.io/v1beta1
kind: Instance
metadata:
  annotations:
    upjet.upbound.io/manual-intervention: This resource has a password secret reference.
  name: ${RDS_INSTANCE_NAME}
  namespace: ${APP_NAMESPACE}
spec:
  forProvider:
    dbSubnetGroupNameRef:
       name: ${RDS_DB_SUBNET_NAME}
    vpcSecurityGroupIdRefs:
       - name: ${RDS_SECURITY_GROUP_NAME}
    allocatedStorage: 20
    autoMinorVersionUpgrade: true
    backupRetentionPeriod: 14
    backupWindow: 09:46-10:16
    engine: postgres
    engineVersion: \"13.7\"
    instanceClass: db.t3.micro
    maintenanceWindow: Mon:00:00-Mon:03:00
    passwordSecretRef:
      key: password
      name: ${RDS_DB_SECRET_NAME}
      namespace: ${APP_NAMESPACE}
    publiclyAccessible: false
    region: ${AWS_REGION}
    skipFinalSnapshot: true
    storageEncrypted: false
    storageType: gp2
    username: ${RDS_DB_USERNAME}
  writeConnectionSecretToRef:
    name: ${RDS_INFO_SECRET_NAME}
    namespace: ${APP_NAMESPACE}
" | kubectl apply -f -

