#!/usr/bin/sh

export PATH=/usr/local/bin:${PATH}
export AWS_PAGER=""

function wait_loop
{

	echo "Waiting for the resource to be available"
	cmd_to_run=$1
	status=$2
    typeset -i counter=0
    while [ $counter -lt 10 ]
    do 
        output=$(${cmd_to_run})
		echo "Output of the current operation : ${output}"
        if [ "${output}" == "${status}" ]; then
            echo "Status is ${status} breaking the loop"
            break
        fi
        sleep 10
        counter=$counter+1
    done

}

function set_env
{
	export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
	export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
	export VPCID=$(aws ec2 describe-vpcs --filter "Name=is-default,Values=true" --query Vpcs[].VpcId --output text)
	export CIDR_BLOCK=$(aws ec2 describe-vpcs --filter "Name=is-default,Values=true" --query Vpcs[].CidrBlock --output text)
	export SUBNETS=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${VPCID}" --query Subnets[].SubnetId --output text)
	export SUBNET_1=`echo $SUBNETS | awk '{print $1}'`
	export SUBNET_2=`echo $SUBNETS | awk '{print $2}'`
	export SUBNET_3=`echo $SUBNETS | awk '{print $3}'`
    export SUBNET_LIST="[\"${SUBNET_1}\",\"${SUBNET_2}\",\"${SUBNET_3}\"]"

	export DBSUBNET="dynblog_subnet"
	export SG_NAME="dynblog_sg"
	export DBPARAM_NAME="dynblog-dbparam"

	export SOURCE_PG="source-pg"
	export STAGE_PG="stage-pg"

	export DBUSERNAME="postgres"
	export DBPASSWORD="postgres"
	export DBNAME="postgres"

	export DMS_INSTANCE_NAME="dynblog-dms-instance"
	export DMS_SUBNET_NAME="dynblog-dms-subnet-group"

	export SOURCE_DMS_SOURCE_EP="source-source-ep"
	export STAGE_DMS_SOURCE_EP="stage-source-ep"
    export STAGE_DMS_TARGET_EP="stage-target-ep"
	export DYNAMODB_DMS_TARGET_EP="dynamodb-target-ep"

	export DYNAMODB_DMS_ROLE="dynblog-dms-access-role"
	export DYNAMODB_DMS_POLICY="dynblog-dms-access-policy"

}


function create_dbsubnet
{

	echo "Creating database subnet"	
echo ${ID}
	aws rds create-db-subnet-group \
    --db-subnet-group-name ${DBSUBNET} \
    --db-subnet-group-description " DB subnet group for dynamodb blog" \
    --subnet-ids "${SUBNET_LIST}"

}


function create_securitygroup
{
	echo "Creating database security group"
	aws ec2 create-security-group --group-name ${SG_NAME} --description "DynamoDB security blog" --vpc-id ${VPCID}
    sleep 2
    export SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SG_NAME}" --query SecurityGroups[].GroupId --output text)
    aws ec2 wait security-group-exists --group-ids ${SG_ID}
	aws ec2 authorize-security-group-ingress --group-id ${SG_ID} --protocol tcp  --port 5432  --cidr ${CIDR_BLOCK}
	aws ec2 authorize-security-group-egress --group-id ${SG_ID} --ip-permissions IpProtocol=tcp,FromPort=0,ToPort=0,IpRanges='[{CidrIp=0.0.0.0/0}]'
}

function create_dbparam_group
{
	echo "Creating database parameter group"

	aws rds create-db-parameter-group \
    --db-parameter-group-name ${DBPARAM_NAME} \
    --db-parameter-group-family postgres14 \
    --description "My new parameter group" \
	--no-paginate

	sleep 1

	aws rds modify-db-parameter-group \
    --db-parameter-group-name ${DBPARAM_NAME} \
    --parameters "ParameterName='rds.logical_replication',ParameterValue=1,ApplyMethod=pending-reboot"

}

function create_source_pg
{
	echo "Creating source postgres instance"

	aws rds create-db-instance \
    --db-instance-identifier ${SOURCE_PG} \
    --db-instance-class db.t3.small \
    --engine postgres \
    --engine-version 14.6 \
    --master-username ${DBUSERNAME} \
    --master-user-password ${DBPASSWORD} \
    --allocated-storage 20 \
    --db-subnet-group-name ${DBSUBNET} \
    --db-parameter-group-name ${DBPARAM_NAME} \
    --vpc-security-group-ids "[\"${SG_ID}\"]" \
	--no-paginate

	sleep 2
	wait_loop "aws rds describe-db-instances --db-instance-identifier ${SOURCE_PG} --query DBInstances[].DBInstanceStatus --output text" "available"
	echo "Source postgres instance created successfully"
	export SOURCE_PG_EP=$(aws rds describe-db-instances --db-instance-identifier ${SOURCE_PG} --query DBInstances[].Endpoint.Address --output text)
	echo "Source PG EP ${SOURCE_PG_EP}"
}


function create_stage_pg
{
	echo "Creating stage postgres instance"

	aws rds create-db-instance \
    --db-instance-identifier ${STAGE_PG} \
    --db-instance-class db.t3.small \
    --engine postgres \
    --engine-version 14.6 \
    --master-username ${DBUSERNAME} \
    --master-user-password ${DBPASSWORD} \
    --allocated-storage 20 \
    --db-subnet-group-name ${DBSUBNET} \
    --vpc-security-group-ids "[\"${SG_ID}\"]" \
	--no-paginate

	sleep 2
	wait_loop "aws rds describe-db-instances --db-instance-identifier ${STAGE_PG} --query DBInstances[].DBInstanceStatus --output text" "available"
	echo "Stage postgres instance created successfully"
	export STAGE_PG_EP=$(aws rds describe-db-instances --db-instance-identifier ${STAGE_PG} --query DBInstances[].Endpoint.Address --output text)
	echo "Stage PG EP ${STAGE_PG_EP}"

}


function create_dms_replication_role
{

	echo "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
	  \"Sid\": \"\",
      \"Effect\": \"Allow\",
      \"Principal\": {
        \"Service\": \"dms.amazonaws.com\"
      },
      \"Action\": \"sts:AssumeRole\"
    }
  ]
}" > /tmp/dmsAssumeRolePolicyDocument.json 

	aws iam create-role --role-name dms-vpc-role --assume-role-policy-document file:///tmp/dmsAssumeRolePolicyDocument.json 
	aws iam attach-role-policy --role-name dms-vpc-role --policy-arn arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole 

}



function create_replication_instance
{

	echo "Creating DMS replication subnet group"

	aws dms create-replication-subnet-group \
    --replication-subnet-group-identifier "${DMS_SUBNET_NAME}" \
    --replication-subnet-group-description "DynamoDB DMS subnet group" \
    --subnet-ids "${SUBNET_LIST}" \
	--no-paginate

	sleep 5

	echo "Creating DMS replication instance "

	aws dms create-replication-instance \
    --replication-instance-identifier ${DMS_INSTANCE_NAME} \
    --replication-instance-class dms.t2.small \
    --allocated-storage 10 \
	--engine-version 3.4.7 \
	--no-publicly-accessible \
	--no-paginate

	sleep 5
	export DMS_REP_INSTANCE_ARN=$(aws dms describe-replication-instances --filter "Name=replication-instance-id,Values=${DMS_INSTANCE_NAME}" --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)

	wait_loop "aws dms describe-replication-instances --filter Name=replication-instance-id,Values=${DMS_INSTANCE_NAME} --query ReplicationInstances[].ReplicationInstanceStatus --output text" "available"
	echo "Replication instance created successfully"
	echo "Replication instance ARN : ${DMS_REP_INSTANCE_ARN}" }

}


function create_ep
{
	echo "Creating source DMS endpoint"
	aws dms create-endpoint \
	--endpoint-identifier ${SOURCE_DMS_SOURCE_EP} \
	--endpoint-type source \
	--engine-name postgres \
	--username ${DBUSERNAME} \
	--password ${DBPASSWORD} \
	--server-name ${SOURCE_PG_EP} \
	--port 5432 \
	--database-name ${DBNAME}

	sleep 2
	export SOURCE_DMS_SOURCE_EP_ARN=$(aws dms describe-endpoints --filter="Name=endpoint-id,Values=${SOURCE_DMS_SOURCE_EP} " --query="Endpoints[0].EndpointArn" --output text)


	echo "Creating Staging DMS source endpoint"
	aws dms create-endpoint \
	--endpoint-identifier ${STAGE_DMS_SOURCE_EP} \
	--endpoint-type source \
	--engine-name postgres \
	--username ${DBUSERNAME} \
	--password ${DBPASSWORD} \
	--server-name ${STAGE_PG_EP} \
	--port 5432 \
	--database-name ${DBNAME}

	sleep 2
	export STAGE_DMS_SOURCE_EP_ARN=$(aws dms describe-endpoints --filter="Name=endpoint-id,Values=${STAGE_DMS_SOURCE_EP} " --query="Endpoints[0].EndpointArn" --output text)

	echo "Creating Staging DMS target endpoint"
	aws dms create-endpoint \
	--endpoint-identifier ${STAGE_DMS_TARGET_EP} \
	--endpoint-type target \
	--engine-name postgres \
	--username ${DBUSERNAME} \
	--password ${DBPASSWORD} \
	--server-name ${STAGE_PG_EP} \
	--port 5432 \
	--database-name ${DBNAME}

	sleep 2
	export STAGE_DMS_TARGET_EP_ARN=$(aws dms describe-endpoints --filter="Name=endpoint-id,Values=${STAGE_DMS_TARGET_EP} " --query="Endpoints[0].EndpointArn" --output text)

}

function check_ep
{

	for ep_arn in ${SOURCE_DMS_SOURCE_EP_ARN} ${STAGE_DMS_SOURCE_EP_ARN} ${STAGE_DMS_TARGET_EP_ARN} ${DYNAMODB_DMS_TARGET_EP_ARN}
	do
		echo "Testing the connection for ${ep_arn}"
		aws dms test-connection --replication-instance-arn ${DMS_REP_INSTANCE_ARN}  --endpoint-arn ${ep_arn}
	done

	for ep_arn in ${SOURCE_DMS_SOURCE_EP_ARN} ${STAGE_DMS_SOURCE_EP_ARN} ${STAGE_DMS_TARGET_EP_ARN} ${DYNAMODB_DMS_TARGET_EP_ARN} 
	do
		echo "Waiting for the connection test for : ${ep_arn}"
		wait_loop "aws dms describe-connections --filter Name=endpoint-arn,Values=${ep_arn} --query Connections[].Status --output text" "successful"
		echo "Connection test successfull for ${ep_arn}"
	done

}

function create_dynamodb_role
{
	echo "Creating DynaomoDB role"

	echo "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
	  \"Sid\": \"\",
      \"Effect\": \"Allow\",
      \"Principal\": {
        \"Service\": \"dms.amazonaws.com\"
      },
      \"Action\": \"sts:AssumeRole\"
    }
  ]
}" > /tmp/dmsDynamoDBAssumeRole.json 


aws iam create-role \
    --role-name ${DYNAMODB_DMS_ROLE} \
    --assume-role-policy-document file:///tmp/dmsDynamoDBAssumeRole.json


	echo "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Action\": [
                \"dynamodb:*\"
            ],
            \"Effect\": \"Allow\",
            \"Resource\": [ \"*\" ]
        }
    ]
} " > /tmp/dmsDynamoDBAssumeRolePolicyDocument.json


	aws iam create-policy \
    --policy-name ${DYNAMODB_DMS_POLICY} \
    --policy-document file:///tmp/dmsDynamoDBAssumeRolePolicyDocument.json

	sleep 5

	aws iam attach-role-policy \
    --role-name ${DYNAMODB_DMS_ROLE} \
    --policy-arn  arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${DYNAMODB_DMS_POLICY}
	
	sleep 5

}


function create_gateway_ep
{

	echo "Creating gateway ep for DynamoDB access"

	aws ec2 create-vpc-endpoint \
    --vpc-id ${VPCID} \
    --service-name com.amazonaws.${AWS_REGION}.dynamodb  \
    --route-table-ids "$(aws ec2 describe-route-tables --filter Name=vpc-id,Values=${VPC_ID} --query RouteTables[].RouteTableId)"

}

function create_dynamodb_ep
{
	echo "Creating DynamoDB DMS endpoint"

	aws dms create-endpoint \
	--endpoint-identifier ${DYNAMODB_DMS_TARGET_EP} \
	--endpoint-type target \
	--engine-name dynamodb \
	--service-access-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${DYNAMODB_DMS_ROLE}

	sleep 2
	export DYNAMODB_DMS_TARGET_EP_ARN=$(aws dms describe-endpoints --filter="Name=endpoint-id,Values=${DYNAMODB_DMS_TARGET_EP} " --query="Endpoints[0].EndpointArn" --output text)
}

if [ "X"${1} == "X" ]; then
	echo "Please enter proper parameters"
	echo "Valid values are build,populate_data, load_data"
	exit
fi

set_env

if [ "X"${1} == "Xbuild" ] ;  then
	create_dbsubnet
	create_securitygroup
	create_dbparam_group
	create_source_pg
	create_stage_pg
	create_dms_replication_role
	create_replication_instance
	create_ep
	create_dynamodb_role
	create_gateway_ep
	create_dynamodb_ep
	check_ep
fi

if [ "X"${1} == "Xpopulate" ] ;  then
	create_source_table
	create_stage_table
	load_source_table
	create_source_table
fi

