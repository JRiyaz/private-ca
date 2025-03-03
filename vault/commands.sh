#!/bin/sh

VAULT_ROOT_DOMAIN="$VAULT_ROOT_DOMAIN"
VAULT_ROOT_DOMAIN_URL="$VAULT_ROOT_DOMAIN_URL"
VAULT_ALT_NAMES="$VAULT_ALT_NAMES"
VAULT_REQUIRED_DOMAIN="$VAULT_REQUIRED_DOMAIN"
VAULT_SUB_DOMAIN="$VAULT_SUB_DOMAIN"
VAULT_USER="$VAULT_USER"
VAULT_PASSWORD="$VAULT_PASSWORD"
CERT_PATH="$CERT_PATH"
ROOT_CA_TTL="$ROOT_CA_TTL"
INTERMEDIATE_CA_TTL="$INTERMEDIATE_CA_TTL"
LEAF_CA_TTL="$LEAF_CA_TTL"
ROLE_TTL="$ROLE_TTL"
ROOT_COMMON_NAME="$ROOT_COMMON_NAME"
ROOT_ISSUER_NAME="$ROOT_ISSUER_NAME"
INTER_COMMON_NAME="$INTER_COMMON_NAME"
INTER_ISSUER_NAME="$INTER_ISSUER_NAME"
ORGANIZATION_NAME="$ORGANIZATION_NAME"
ORGANIZATION_UNIT="$ORGANIZATION_UNIT"

export DIR_PATH="/vault/certs/${CERT_PATH}"
if [ ! -d "DIR_PATH" ]; then
  # If it doesn't exist, create the directory
  mkdir -p "$DIR_PATH"
  echo "Directory created: $DIR_PATH"
fi

vault login root
vault status
vault audit enable file file_path=/vault/logs/vault_audit.log
vault audit enable -path="file_raw" file  log_raw=true file_path=/vault/logs/vault_audit_raw.log

### ENABLE PKI ENGINE         **************** ROOT CA ****************
vault secrets enable pki

### UPDATE TTL OF PKI ENGINE
vault secrets tune -max-lease-ttl="${ROOT_CA_TTL}" pki

### GENERATE ROOT CA
vault write -format=json pki/root/generate/internal common_name="${ROOT_COMMON_NAME}" issuer_name="${ROOT_ISSUER_NAME}" ttl="${ROOT_CA_TTL}" > pki-ca-root.json

### EXTRACT CERT DATA INTO PEM FILE
cat pki-ca-root.json | jq -r .data.certificate > ca-root.pem

### CREATE PATH FOR ROOT CA
vault write pki/config/urls issuing_certificates="${VAULT_ADDR}/v1/pki/ca" crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

### COPY PEM FILE TO DESIRED LOCATION
cp ca-root.pem /vault/certs/"${CERT_PATH}"/ca-root.pem

### ENABLE PKI ENGINE FOR INTERMEDIATE CA          **************** INTERMEDIATE CA ****************
vault secrets enable -path=pki_int pki

### UPDATE INTERMEDIATE CA TTL
vault secrets tune -max-lease-ttl="${INTERMEDIATE_CA_TTL}" pki_int

### CREATE INTERMEDIATE CA
vault write -format=json pki_int/intermediate/generate/internal common_name="${INTER_COMMON_NAME}" issuer_name="${INTER_ISSUER_NAME}" | jq -r '.data.csr' > pki-ca-inter.csr

### SIGN INTERMEDIATE CA WITH ROOT CA
vault write -format=json pki/root/sign-intermediate csr=@pki-ca-inter.csr format=pem_bundle ttl="${INTERMEDIATE_CA_TTL}" issuer_ref="${ROOT_ISSUER_NAME}"  | jq -r '.data.certificate' > ca-inter.pem

### COPY INTERMEDIATE CERTS TO DESIRED LOCATION
cp ca-inter.pem /vault/certs/"${CERT_PATH}"/ca-inter.pem

vault write pki_int/intermediate/set-signed certificate=@ca-inter.pem

vault write pki_int/config/urls issuing_certificates="${VAULT_ADDR}/v1/pki_int/ca" crl_distribution_points="${VAULT_ADDR}/v1/pki_int/crl"

#          **************** CREATE ROLE ****************
# shellcheck disable=SC2086
# allowed_domains = ["example.com", "foobar.com"]   https://developer.hashicorp.com/vault/api-docs/secret/pki#sample-response-1
export ROLES_PATH="pki_int/roles/${VAULT_ROOT_DOMAIN_URL}"
vault write "${ROLES_PATH}" allowed_domains="${VAULT_ROOT_DOMAIN}" allow_subdomains=true issuer_ref="$(vault read -field=default pki_int/config/issuers)" country="IN" locality="Bengaluru" street_address="SouthEnd Road" organization="${ORGANIZATION_NAME}" ou="${ORGANIZATION_UNIT}" postal_code="560004" province="English, Hindi" max_ttl="${ROLE_TTL}"

#          **************** POLICY ****************
vault policy fmt pki_int.hcl
vault policy write pki_int pki_int.hcl

vault auth enable userpass
# shellcheck disable=SC2086
vault write auth/userpass/users/"${VAULT_USER}" password=${VAULT_PASSWORD} token_policies="pki_int"

# Generate certificate
# shellcheck disable=SC2086
vault login -format=json -method=userpass username=${VAULT_USER} password=${VAULT_PASSWORD} | jq -r .auth.client_token > user.token
# shellcheck disable=SC2006
export VAULT_TOKEN=`cat user.token`

### GENERATE LEAF CERTIFICATE
vault write -format=json pki_int/issue/"${VAULT_ROOT_DOMAIN_URL}" common_name="${VAULT_REQUIRED_DOMAIN}" issuer_ref="${INTER_ISSUER_NAME}" alt_names="${VAULT_ALT_NAMES}" ttl="${LEAF_CA_TTL}" > "${VAULT_SUB_DOMAIN}".json

# shellcheck disable=SC2002
cat "${VAULT_SUB_DOMAIN}".json | jq -r .data.certificate > /vault/certs/"${CERT_PATH}"/"${VAULT_SUB_DOMAIN}".crt
# shellcheck disable=SC2002
cat "${VAULT_SUB_DOMAIN}".json | jq -r .data.issuing_ca >> /vault/certs/"${CERT_PATH}"/"${VAULT_SUB_DOMAIN}".crt
# shellcheck disable=SC2002
cat "${VAULT_SUB_DOMAIN}".json | jq -r .data.private_key > /vault/certs/"${CERT_PATH}"/"${VAULT_SUB_DOMAIN}".key

openssl x509 -outform der -in ca-root.pem -out /vault/certs/"${CERT_PATH}"/ca-root.crt
openssl x509 -outform der -in ca-inter.pem -out /vault/certs/"${CERT_PATH}"/ca-inter.crt

# https://developer.hashicorp.com/vault/api-docs/secret/pki#import-ca-certificates-and-keys
# To Use/Import existing CA
# curl --header "X-Vault-Token: root" --request POST --data "@payload.json" http://127.0.0.1:8200/v1/pki/config/ca
