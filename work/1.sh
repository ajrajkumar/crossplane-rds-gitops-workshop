APP_NAMESPACE=mydb
EKS_CLUSTER_NAME=eksclu
AWS_REGION=us-east-2
EKS_VPC_ID=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo $EKS_VPC_ID
RDS_SUBNET_GROUP_NAME="my-subnet-group"
RDS_SUBNET_GROUP_DESCRIPTION="database subnet group"
EKS_SUBNET_IDS=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${EKS_VPC_ID}" --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text)
EKS_SUBNET_ID_1=`echo ${EKS_SUBNET_IDS} | awk '{print $1}'`
EKS_SUBNET_ID_2=`echo ${EKS_SUBNET_IDS} | awk '{print $2}'`
EKS_SUBNET_ID_3=`echo ${EKS_SUBNET_IDS} | awk '{print $3}'`
RDS_SECURITY_GROUP_NAME="ack-security-group"
RDS_SECURITY_GROUP_DESCRIPTION="ACK security group"
EKS_CIDR_RANGE=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)
echo ${EKS_CIDR_RANGE}
RDS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups  --filter Name=vpc-id,Values="${EKS_VPC_ID}" Name=group-name,Values="${RDS_SECURITY_GROUP_NAME}" --query 'SecurityGroups[*].[GroupId]' --output text )
RDS_DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .dbuser)
RDS_DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .password)
RDS_DB_SECRET_NAME="ack-creds"
RDS_INFO_SECRET_NAME="ack-creds-out"
RDS_INSTANCE_NAME="crossplane-db"
RDS_DB_SUBNET_NAME="crossplane-dbsubnet"

echo ${EKS_SUBNET_IDS}
