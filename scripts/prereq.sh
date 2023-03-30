#!/bin/sh

function print_line()
{
    echo "---------------------------------"
}

function install_packages()
{
    sudo yum install -y jq  > ${TERM} 2>&1
    print_line
    echo "Installing aws cli v2"
    print_line
    aws --version | grep aws-cli\/2 > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        cd $current_dir
	return
    fi
    current_dir=`pwd`
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" > ${TERM} 2>&1
    unzip -o awscliv2.zip > ${TERM} 2>&1
    sudo ./aws/install --update > ${TERM} 2>&1
    cd $current_dir
}

function install_k8s_utilities()
{
    print_line
    echo "Installing Kubectl"
    print_line
    sudo curl -o /usr/local/bin/kubectl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"  > ${TERM} 2>&1
    sudo chmod +x /usr/local/bin/kubectl > ${TERM} 2>&1
    print_line
    echo "Installing eksctl"
    print_line
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp > ${TERM} 2>&1
    sudo mv /tmp/eksctl /usr/local/bin
    sudo chmod +x /usr/local/bin/eksctl
    print_line
    echo "Installing helm"
    print_line
    curl -s https://fluxcd.io/install.sh | sudo bash > ${TERM} 2>&1
    curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash > ${TERM} 2>&1

}

function install_postgresql()
{
    print_line
    echo "Installing Postgresql client"
    print_line
    sudo amazon-linux-extras install -y postgresql14 > ${TERM} 2>&1
}


function update_kubeconfig()
{
    print_line
    echo "Updating kubeconfig"
    print_line
    aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME}
}


function update_eks()
{
    print_line
    echo "Enabling clusters to use iam oidc"
    print_line
    eksctl utils associate-iam-oidc-provider --cluster ${EKS_CLUSTER_NAME} --region ${AWS_REGION} --approve
}


function chk_installation()
{ 
    print_line
    echo "Checking the current installation"
    print_line
    for command in kubectl aws eksctl flux helm jq
    do
        which $command &>${TERM} && echo "$command present" || echo "$command NOT FOUND"
    done

}


function clone_git()
{
    print_line
    echo "Cloning the git repository"
    print_line
    cd ${HOME}/environment
    rm -rf crossplane.gitlab crossplane.codecommit
    git clone https://github.com/ajrajkumar/crossplane-rds-gitops-workshop crossplane.gitlab
    git clone https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/crossplane-rds-gitops-workshop crossplane.codecommit
    cd crossplane.codecommit
    cp -rp ../crossplane.gitlab/* .
    print_line
}

function fix_git()
{
    print_line
    echo "Fixing the git repository"
    print_line

    cd ${HOME}/environment/crossplane.codecommit

    # Update infrastructure manifests
    #sed -i -e "s/<region>/$AWS_REGION/g" ./infrastructure/production/crossplane/*release*.yaml
    sed -i -e "s/<account_id>/$AWS_ACCOUNT_ID/g" ./infrastructure/production/crossplane/*serviceaccount.yaml

    # Update application manifests
    sed -i -e "s/<region>/$AWS_REGION/g" \
         -e "s/<account_id>/$AWS_ACCOUNT_ID/g" \
         -e "s/<vpcSecurityGroupIDs>/$VPCID/g" \
       ./apps/production/retailapp/*.yaml

    sed -i -e "s/<region>/$AWS_REGION/g" \
   	-e "s/<account_id>/$AWS_ACCOUNT_ID/g" \
   	-e "s/<apgSubnetId1>/$SUBNET_ID_1/g" \
   	-e "s/<apgSubnetId2>/$SUBNET_ID_2/g" \
   	-e "s/<apgSubnetId3>/$SUBNET_ID_3/g" \
   	-e "s/<vpcSecurityGroupIDs>/$VPCSG/g" \
   	-e "s/<cidrBlock>/$CIDR_BLOCK/g" \
	-e "s/<db-creds>/$DB_CREDS/g" \
	-e "s/<memorydbSubnetId1>/$MEMDB_SUBNET_ID_1/g" \
	-e "s/<memorydbSubnetId2>/$MEMDB_SUBNET_ID_2/g" \
	-e "s/<memorydbSubnetId3>/$MEMDB_SUBNET_ID_3/g" \
	-e "s/<userName>/$RDS_DB_USERNAME/g" \
	-e "s/<dbUserName>/$RDS_DB_USERNAME/g" \
	-e "s/<dbPassword>/$RDS_DB_PASSWORD/g" \
   	./apps/production/*.yaml

    git add .
    git commit -a -m "Initial version"
    git push
}

function install_loadbalancer()
{

    print_line
    echo "Installing load balancer"
    print_line
    eksctl create iamserviceaccount \
     --cluster=${EKS_CLUSTER_NAME} \
     --namespace=${EKS_NAMESPACE} \
     --name=aws-load-balancer-controller \
     --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
     --override-existing-serviceaccounts \
     --approve

    helm repo add eks https://aws.github.io/eks-charts

    kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     --set clusterName=${EKS_CLUSTER_NAME} \
     --set serviceAccount.create=false \
     --set region=${AWS_REGION} \
     --set vpcId=${VPCID} \
     --set serviceAccount.name=aws-load-balancer-controller \
     -n ${EKS_NAMESPACE}

}


function chk_aws_environment()
{
    print_line
    echo "Checking AWS environment"
    print_line
    for myenv in "${AWS_DEFAULT_REGION}" "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" "${AWS_SESSION_TOKEN}"
    do
        if [ x"${myenv}" == "x" ] ; then
            echo "AWS environment is missing. Please import from event engine"
	    exit
	fi
    done
    echo "AWS environment exists"
    
}


function run_kubectl()
{
    print_line
    echo "kubectl get nodes -o wide"
    print_line
    kubectl get nodes -o wide
    print_line
    echo "kubectl get pods --all-namespaces"
    print_line
    kubectl get pods --all-namespaces
}

function create_iam_user()
{
    print_line
    echo "Creating AWS IAM User for git"
    print_line
    aws iam create-user --user-name gituser
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Failed to create user"
    fi
    print_line
    aws iam attach-user-policy --user-name gituser \
      --policy-arn arn:aws:iam::aws:policy/AWSCodeCommitFullAccess
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Failed to attach plicy to user"
    fi
    print_line
}

function build_and_publish_container_images()
{
    print_line
    echo "Create docker container images for application and publish to ECR"
    cd ~/environment/crossplane.codecommit/apps/src
    export TERM=xterm
    make
    cd -
    print_line
} 

function create_secret()
{ 
    print_line
    aws secretsmanager create-secret     --name dbCredential     --description "RDS DB username/password"     --secret-string "{\"dbuser\":\"adminer\",\"password\":\"postgres\"}" 
    print_line
}

function install_c9()
{
    print_line
    npm install -g c9
    print_line
}

function install_crossplane()
{
    print_line
    echo "Installing up"
    print_line
    curl -sL "https://cli.upbound.io" | sh > ${TERM} 2>&1
    sudo mv up /usr/local/bin/
    /usr/local/bin/up uxp install
    kubectl get pods -n upbound-system
    print_line
    echo "Waiting for the controller plane is up and running"
    typeset -i counter=0
    while [ $counter -lt 10 ]
    do
        pods=`kubectl get pods -n ${CROSSPLANE_NAMESPACE} | grep Running | wc -l`
	if [ ${pods} -ge 3 ]; then
            echo "Crossplane pods started successfully"
            break
	fi
	sleep 10
	counter=$counter+1
    done

}


function setup_irsa()
{
    print_line
    echo "Setting up the IRSA for the kubecluster"
    kubectl create sa ${CROSSPLANE_IAM_ROLE} -n ${CROSSPLANE_NAMESPACE}
    IRSA_ROLE_ARN="eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CROSSPLANE_IAM_ROLE}"
    IRSA_ROLE_ARN_CONFIG="eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CROSSPLANE_IAM_ROLE}"
    kubectl annotate serviceaccount -n ${CROSSPLANE_NAMESPACE} ${CROSSPLANE_IAM_ROLE} $IRSA_ROLE_ARN 
    print_line
    echo "Creating the controller config"
    echo "apiVersion: pkg.crossplane.io/v1alpha1
kind: ControllerConfig
metadata:
  name: irsa-controllerconfig
  annotations:
    ${IRSA_ROLE_ARN_CONFIG}
spec: "  | kubectl apply -f -

}

function install_aws_provider()
{

   print_line
   echo "Installing AWS provider"

   echo "apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: xpkg.upbound.io/upbound/provider-aws:v0.31.0
  controllerConfigRef:
    name: irsa-controllerconfig " | kubectl apply -f -

    echo "Waiting for the provider to be available"
    typeset -i counter=0
    while [ $counter -lt 30 ]
    do
        pods=`kubectl get pods -n ${CROSSPLANE_NAMESPACE} | grep provider-aws | grep Running | wc -l`
	if [ ${pods} -eq 1 ]; then
            echo "Crossplane AWS provider started successfully"
            break
	fi
	sleep 10
	counter=$counter+1
    done

  echo "Installing provider config"
  echo "apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: provider-aws
spec:
  credentials:
    source: IRSA" | kubectl apply -f -
}


function install_k8s_provider()
{

    print_line
    echo "Installing Kuberntes provider"

    echo "apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
   name: provider-kubernetes
spec:
   package: xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.7.0
   controllerConfigRef:
      name: irsa-controllerconfig"  | kubectl apply -f -

    echo "Waiting for the provider to be available"
    typeset -i counter=0
    while [ $counter -lt 30 ]
    do
        pods=`kubectl get pods -n ${CROSSPLANE_NAMESPACE} | grep provider-kubernetes | grep Running | wc -l`
	if [ ${pods} -eq 1 ]; then
            echo "Crossplane Kubernetes provider started successfully"
            break
	fi
	sleep 10
	counter=$counter+1
    done


    echo "Installing Kubernetes provider config"

    echo "apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: provider-kubernetes
spec:
  credentials:
    source: InjectedIdentity " | kubectl apply -f - 

    echo "Granting the required role to kubernetes provider"

    SA=$(kubectl get sa -n ${CROSSPLANE_NAMESPACE} -o name | grep provider-kubernetes | sed -e "s|serviceaccount\/|${CROSSPLANE_NAMESPACE}:|g")
    echo "SA Role is ${SA}"
    kubectl create clusterrolebinding provider-kubernetes-admin-binding --clusterrole cluster-admin --serviceaccount="${SA}"

}


function chk_cloud9_permission()
{
    return #raj
    aws sts get-caller-identity | grep ${INSTANCE_ROLE}  
    if [ $? -ne 0 ] ; then
	echo "Fixing the cloud9 permission"
        environment_id=`aws ec2 describe-instances --instance-id $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --query "Reservations[*].Instances[*].Tags[?Key=='aws:cloud9:environment'].Value" --output text`
        aws cloud9 update-environment --environment-id ${environment_id} --region ${AWS_REGION} --managed-credentials-action DISABLE
	sleep 10
        ls -l $HOME/.aws/credentials > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
             echo "!!! Credentials file exists"
        else
            echo "Credentials file does not exists"
        fi
	echo "After fixing the credentials. Current role"
        aws sts get-caller-identity | grep ${INSTANCE_ROLE}
    fi
}


function initial_cloud9_permission()
{
    return #raj
    print_line
    echo "Checking initial cloud9 permission"
    typeset -i counter=0
    managed_role="FALSE"
    while [ ${counter} -lt 2 ] 
    do
        aws sts get-caller-identity | grep ${INSTANCE_ROLE}  
        if [ $? -eq 0 ] ; then
            echo "Called identity is Instance role .. Waiting - ${counter}"
	    sleep 30
	    counter=$counter+1
	else
	    echo "Called identity is AWS Managed Role .. breaking"
	    managed_role="TRUE"
	    break
	fi
    done

    if [ ${managed_role} == "TRUE" ] ;  then
        echo "Current role is AWS managed role"
    else
        echo "Current role is Instance role.. May cause issue later deployment. But still continuing"
    fi

    chk_cloud9_permission
}


function print_environment()
{
    print_line
    echo "Current Region : ${AWS_REGION}"
    echo "EKS Namespace  : ${EKS_NAMESPACE}"
    echo "EKS Cluster Name : ${EKS_CLUSTER_NAME}"
    echo "VPCID           : ${VPCID}"
    echo "VPC SG           : ${VPCSG}"
    print_line
}

# Main program starts here

export INSTANCE_ROLE="C9Role"

if [ ${1}X == "-xX" ] ; then
    TERM="/dev/tty"
else
    TERM="/dev/null"
fi

echo "Process started at `date`"
install_packages
install_k8s_utilities
install_postgresql

export AWS_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r`
initial_cloud9_permission
export EKS_NAMESPACE="kube-system"
export CROSSPLANE_NAMESPACE="upbound-system"
export CROSSPLANE_IAM_ROLE="crossplane-controller-role"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) 
export VPCID=$(aws cloudformation describe-stacks --region $AWS_REGION --query 'Stacks[].Outputs[?OutputKey == `VPC`].OutputValue' --output text)


export EKS_VPC_ID=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
export SUBNET_IDS=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=${EKS_VPC_ID}" --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text)
export SUBNET_ID_1=`echo ${SUBNET_IDS} | awk '{print $1}'`
export SUBNET_ID_2=`echo ${SUBNET_IDS} | awk '{print $2}'`
export SUBNET_ID_3=`echo ${SUBNET_IDS} | awk '{print $3}'`
export CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)

export MEMDB_SUBNET_IDS=$(aws cloudformation describe-stacks --region ${AWS_REGION} --query 'Stacks[].Outputs[?OutputKey == `MemoryDBAllowedSubnets`].OutputValue' --output text)
export MEMDB_SUBNET_ID_1=`echo ${MEMDB_SUBNET_IDS} | awk -F',' '{print $1}'`
export MEMDB_SUBNET_ID_2=`echo ${MEMDB_SUBNET_IDS} | awk -F',' '{print $2}'`
export MEMDB_SUBNET_ID_3=`echo ${MEMDB_SUBNET_IDS} | awk -F',' '{print $3}'`
 
#create_iam_user
clone_git
chk_cloud9_permission
export EKS_CLUSTER_NAME=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'EKSClusterName')][].{OutputValue:OutputValue}" --output text)
export VPCSG=$(aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=5432 Name=ip-permission.to-port,Values=5432 --query "SecurityGroups[0].GroupId" --output text)
create_secret
export RDS_DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .dbuser)
export RDS_DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id dbCredential  | jq --raw-output '.SecretString' | jq -r .password)
export DB_CREDS="db-creds"
print_environment
fix_git
update_kubeconfig
chk_cloud9_permission
update_eks
chk_cloud9_permission
install_crossplane
setup_irsa
install_aws_provider
install_k8s_provider
install_loadbalancer
chk_installation
chk_cloud9_permission
run_kubectl
chk_cloud9_permission
build_and_publish_container_images
print_line
install_c9
print_line

echo "Process completed at `date`"
