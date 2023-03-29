RDS_DB_SECRET_NAME="db-creds"
RDS_INFO_SECRET_NAME="db-creds-out"
RDS_DB_USERNAME=admin
RDS_DB_PASSWORD=admin1234

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

